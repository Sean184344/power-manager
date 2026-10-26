#!/usr/bin/env python3
"""M3 clock ratio/phase/ack-delay matrix and directed scenario coverage gate."""
import argparse
from collections import Counter
import hashlib
import itertools
import json
import os
import re
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["rtl/power_manager.sv", "rtl/cdc_primitives.sv", "rtl/power_manager_cdc.sv",
           "tb/models/managed_workload.sv", "tb/models/transaction_scoreboard.sv",
           "tb/models/async_clock_controller.sv", "tb/tb_m3.sv"]
REQUIRED = {"wake.repeated", "sleep.busy", "sleep.held_request", "sleep.rearmed",
            "work.accepted_during_drain", "ack.delayed_quiesce", "wake.drain_abort_rearm",
            "timeout.drain", "clock.stale_ready", "timeout.start", "reset.pending_wake"}
REQUIRED |= {f"reset.state{state}" for state in range(7)}


def run(command, log):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"M3 command failed: {shlex.join(command)}\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--half-periods", nargs="+", type=int, default=[3, 5, 7, 13])
    parser.add_argument("--phases", nargs="+", type=int, default=[0, 1, 4])
    parser.add_argument("--delays", nargs="+", type=int, default=[1, 7])
    parser.add_argument("--waves", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    out = Path("build/m3")
    out.mkdir(parents=True, exist_ok=True)
    report = {"source_sha256": {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in SOURCES},
              "required_bins": sorted(REQUIRED), "runs": []}
    for half, phase, delay in itertools.product(args.half_periods, args.phases, args.delays):
        name = f"half-{half}-phase-{phase}-delay-{delay}"
        executable = out / f"{name}.vvp"
        compile_command = shlex.split(os.environ.get("IVERILOG", "iverilog")) + [
            "-g2012", "-Wall", "-s", "tb_m3", f"-Ptb_m3.SOURCE_HALF={half}",
            f"-Ptb_m3.SOURCE_PHASE={phase}", f"-Ptb_m3.START_DELAY={delay}",
            "-o", str(executable)] + SOURCES
        run(compile_command, out / f"{name}.compile.log")
        events = out / f"{name}.csv"
        command = shlex.split(os.environ.get("VVP", "vvp")) + [str(executable), f"+COVERAGE={events}"]
        if args.waves:
            command.append(f"+VCD={out / (name + '.vcd')}")
        output = run(command, out / f"{name}.log")
        counts = Counter(events.read_text().splitlines()[1:])
        if set(counts) != REQUIRED or "PASS: M3 period=" not in output:
            raise RuntimeError(f"M3 coverage mismatch: {name}; missing={REQUIRED-set(counts)} extra={set(counts)-REQUIRED}")
        metrics = re.search(r"PASS: M3 accounting work=(\d+) completed=(\d+) canceled=(\d+) wake=(\d+) delivered=(\d+) wake_canceled=(\d+)", output)
        if not metrics:
            raise RuntimeError(f"missing accounting summary: {name}")
        accounting = dict(zip(["work_accepted", "work_completed", "work_reset_canceled",
                               "wake_accepted", "wake_delivered", "wake_reset_canceled"], map(int, metrics.groups())))
        report["runs"].append({"accounting": accounting, "source_period_ns": 2*half, "aon_period_ns": 10,
                               "phase_ns": phase, "start_delay_cycles": delay,
                               "hits": dict(sorted(counts.items())),
                               "compile_command": compile_command, "run_command": command})
        (out / "coverage.json").write_text(json.dumps(report, indent=2) + "\n")
        print(next(line for line in output.splitlines() if line.startswith("PASS: M3 period=")))
    print(f"PASS: {len(report['runs'])} M3 runs, {len(REQUIRED)}/{len(REQUIRED)} scenarios per run; {out / 'coverage.json'}")


if __name__ == "__main__":
    main()
