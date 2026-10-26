#!/usr/bin/env python3
"""Run M4 retention scenarios and verify rejection of a corrupted restore."""
import argparse
from collections import Counter
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["rtl/cdc_primitives.sv", "rtl/power_manager_retention.sv",
           "tb/models/async_clock_controller.sv", "tb/models/power_supply.sv",
           "tb/models/retention_domain.sv", "tb/models/retention_scoreboard.sv", "tb/tb_m4.sv"]
REQUIRED = {"retention.normal", "retention.repeated", "retention.delayed",
            "wake.during_save", "wake.during_poweroff", "fault.missing_power_good",
            "fault.missing_clock_ready", "fault.missing_save", "fault.save_ack_stuck",
            "fault.missing_restore", "fault.restore_ack_stuck", "fault.missing_power_off",
            "fault.unexpected_power_loss", "reset.powered_off", "reset.during_restore"}


def run(command, log, expected_failure=None):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    log.write_text(output)
    if expected_failure:
        if result.returncode == 0 or expected_failure not in output:
            raise RuntimeError(f"corruption escaped or failed for wrong reason: {output}")
    elif result.returncode:
        raise RuntimeError(f"M4 failed: {shlex.join(command)}\n{output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--half-periods", nargs="+", type=int, default=[3, 7, 13])
    parser.add_argument("--phases", nargs="+", type=int, default=[1, 4])
    parser.add_argument("--delays", nargs="+", type=int, default=[1, 5])
    parser.add_argument("--waves", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    out = Path("build/m4")
    out.mkdir(parents=True, exist_ok=True)
    report = {"source_sha256": {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in SOURCES},
              "required_scenarios": sorted(REQUIRED), "runs": [], "corruption_detected": False}
    for half, phase, delay in itertools.product(args.half_periods, args.phases, args.delays):
        name = f"half-{half}-phase-{phase}-delay-{delay}"
        executable = out / f"{name}.vvp"
        compile_command = shlex.split(os.environ.get("IVERILOG", "iverilog")) + [
            "-g2012", "-Wall", "-s", "tb_m4", f"-Ptb_m4.SOURCE_HALF={half}",
            f"-Ptb_m4.PHASE={phase}", f"-Ptb_m4.RESPONSE_DELAY={delay}",
            "-o", str(executable)] + SOURCES
        run(compile_command, out / f"{name}.compile.log")
        events = out / f"{name}.csv"
        command = shlex.split(os.environ.get("VVP", "vvp")) + [str(executable), f"+COVERAGE={events}"]
        if args.waves:
            command.append(f"+VCD={out / (name + '.vcd')}")
        output = run(command, out / f"{name}.log")
        counts = Counter(events.read_text().splitlines()[1:])
        if set(counts) != REQUIRED or "PASS: M4 period=" not in output:
            raise RuntimeError(f"missing M4 scenarios or PASS: {name}")
        metrics = re.search(r"PASS: M4 accounting accepted=(\d+) completed=(\d+) canceled=(\d+) saves=(\d+) restores=(\d+)", output)
        if not metrics:
            raise RuntimeError(f"missing M4 accounting: {name}")
        accounting = dict(zip(["accepted", "completed", "reset_canceled", "saves", "restores"], map(int, metrics.groups())))
        if accounting["accepted"] != accounting["completed"] + accounting["reset_canceled"]:
            raise RuntimeError(f"unaccounted work: {name}")
        report["runs"].append({"source_period_ns": 2*half, "phase_ns": phase,
                               "response_delay_cycles": delay, "accounting": accounting,
                               "hits": dict(sorted(counts.items())),
                               "compile_command": compile_command, "run_command": command})
        if not report["corruption_detected"]:
            negative_command = shlex.split(os.environ.get("VVP", "vvp")) + [
                str(executable), "+CORRUPT_RESTORE", f"+COVERAGE={out / 'corrupt.csv'}",
                f"+VCD={out / 'corrupt.vcd'}"]
            diagnostic = "retention scoreboard: restored data mismatch"
            run(negative_command, out / "corrupt.log", expected_failure=diagnostic)
            report["corruption_detected"] = True
            report["negative_command"] = negative_command
            report["negative_diagnostic"] = diagnostic
        (out / "coverage.json").write_text(json.dumps(report, indent=2) + "\n")
        print(next(line for line in output.splitlines() if line.startswith("PASS: M4 period=")))
    print(f"PASS: {len(report['runs'])} M4 runs, {len(REQUIRED)}/{len(REQUIRED)} scenarios per run; corrupted restore rejected")


if __name__ == "__main__":
    main()
