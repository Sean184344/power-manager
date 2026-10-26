#!/usr/bin/env python3
"""Reproducible M2 regression and coverage gate; Python standard library only."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["rtl/power_manager.sv", "tb/models/managed_workload.sv",
           "tb/models/transaction_scoreboard.sv", "tb/models/clock_controller.sv", "tb/tb_m2.sv"]


def run(command, log):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}); see {log}\n{result.stdout}{result.stderr}")
    return result.stdout


def compile_tb(output, timeout, rtl="rtl/power_manager.sv"):
    command = shlex.split(os.environ.get("IVERILOG", "iverilog")) + ["-g2012", "-Wall", "-s", "tb_m2"]
    if timeout == "default":
        command += ["-DUSE_DEFAULT_TIMEOUT"]
    else:
        command += [f"-Ptb_m2.TIMEOUT={timeout}"]
    command += ["-o", str(output), rtl] + SOURCES[1:]
    run(command, output.with_suffix(".compile.log"))
    return command


def planned_bins(n):
    bins = {"wake.RUN.idle", "wake.RUN.busy", "wake.ISOLATE.idle",
            "wake.SLEEP.idle", "wake.RELEASE.idle", "wake.FAULT.idle",
            "timeout.DRAIN", "timeout.START"}
    for position in (["deadline"] if n == 1 else ["early", "deadline"]):
        bins |= {f"wake.DRAIN.{work}.{position}" for work in ("busy", "idle")}
        bins |= {f"wake.START.{ready}.{position}" for ready in ("waiting", "ready")}
        bins |= {f"idle.DRAIN.{position}", f"ready.START.{position}"}
    bins |= {f"clock.delay.{delay}" for delay in range(1, n + 3)}
    return bins


def read_events(path):
    # Verilog %s pads conditional string literals to equal widths.
    return Counter(".".join(part.strip() for part in line.split("."))
                   for line in path.read_text().splitlines()[1:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeouts", nargs="+", default=["1", "2", "3", "default"],
                        choices=["1", "2", "3", "default"])
    parser.add_argument("--seeds", nargs="+", type=int, default=[1, 17, 2026])
    args = parser.parse_args()
    os.chdir(ROOT)
    out = Path("build/m2")
    out.mkdir(parents=True, exist_ok=True)
    summary = {"runs": [], "deterministic_replay": False}
    for timeout in args.timeouts:
        n = 8 if timeout == "default" else int(timeout)
        executable = out / f"timeout-{timeout}.vvp"
        compile_tb(executable, timeout)
        for seed in args.seeds:
            stem = out / f"timeout-{timeout}-seed-{seed}"
            events = stem.with_suffix(".csv")
            command = shlex.split(os.environ.get("VVP", "vvp")) + [str(executable), f"+SEED={seed}", f"+COVERAGE={events}"]
            output = run(command, stem.with_suffix(".log"))
            if f"PASS: M2 timeout={n} seed={seed}" not in output:
                raise RuntimeError(f"missing PASS result: {stem}")
            counts = read_events(events)
            missing = sorted(planned_bins(n) - counts.keys())
            unexpected = sorted(counts.keys() - planned_bins(n))
            if unexpected:
                raise RuntimeError(f"unplanned coverage bins for {stem}: {unexpected}")
            record = {"timeout": timeout, "cycles": n, "seed": seed,
                      "bins": dict(sorted(counts.items())), "missing": missing,
                      "required_bins": len(planned_bins(n)), "command": command}
            summary["runs"].append(record)
            (out / "coverage.json").write_text(json.dumps(summary, indent=2) + "\n")
            if missing:
                raise RuntimeError(f"uncovered bins for {stem}: {missing}")
            if not summary["deterministic_replay"]:
                replay_events = out / "replay.csv"
                replay = run(command[:-1] + [f"+COVERAGE={replay_events}"], out / "replay.log")
                if replay != output or replay_events.read_bytes() != events.read_bytes():
                    raise RuntimeError("same seed did not reproduce identical output and events")
                summary["deterministic_replay"] = True
            print(next(line for line in output.splitlines() if line.startswith("PASS: M2")))
            print(f"  coverage: {len(planned_bins(n))}/{len(planned_bins(n))} required bins")
    (out / "coverage.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"PASS: {len(summary['runs'])} M2 runs; deterministic replay matched; {out / 'coverage.json'}")


if __name__ == "__main__":
    main()
