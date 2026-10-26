#!/usr/bin/env python3
"""Prove core safety/progress and produce concrete reachability witnesses."""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COVERS = ["RUN", "DRAIN", "ISOLATE", "SLEEP", "START", "RELEASE", "FAULT",
          "sleep_wake_round_trip", "drain_timeout_recovery", "ready_on_deadline",
          "wake_on_deadline", "reset_after_fault"]
SOURCES = ["rtl/power_manager.sv", "formal/power_manager_formal.sv"]


def execute(out, name, commands, expected, failure=False):
    script = out / f"{name}.ys"
    script.write_text("\n".join(commands) + "\n")
    result = subprocess.run(shlex.split(os.environ.get("YOSYS", "yosys")) + ["-Q", "-T", "-s", str(script)],
                            text=True, capture_output=True, timeout=90)
    output = result.stdout + result.stderr
    (out / f"{name}.log").write_text(output)
    if (result.returncode != 0) != failure or expected not in output:
        raise RuntimeError(f"formal check failed: {name}; see {out / (name + '.log')}\n{output[-2000:]}")
    return output


def prepare(timeout, fair, rtl="rtl/power_manager.sv"):
    return [f"read_verilog -formal -sv {rtl} formal/power_manager_formal.sv",
            f"chparam -set TIMEOUT {timeout} -set FAIR {fair} power_manager_formal",
            "prep -top power_manager_formal -flatten", "async2sync", "dffunmap",
            "chformal -cover -remove", "opt_clean"]


def main():
    os.chdir(ROOT)
    out = Path("build/formal")
    out.mkdir(parents=True, exist_ok=True)
    report = {"source_sha256": {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in SOURCES},
              "engine": "Yosys built-in SAT with temporal induction", "proofs": [], "covers": []}
    report["tool"] = subprocess.run(shlex.split(os.environ.get("YOSYS", "yosys")) + ["-V"],
                                    text=True, capture_output=True, check=True).stdout.strip()
    for timeout in [1, 2, 3, 8]:
        for fair, label in [(0, "safety"), (1, "progress")]:
            name = f"timeout-{timeout}-{label}"
            model = out / f"{name}.il"
            execute(out, name + "-prepare", prepare(timeout, fair) + [f"write_rtlil {model}"], "Output filename:")
            output = execute(out, name, [f"read_rtlil {model}",
                f"sat -seq 1 -tempinduct -maxsteps {2*timeout+12} -set-assumes -prove-asserts -verify -timeout 20 -dump_vcd {out / (name + '-failure.vcd')}"],
                "Induction step proven: SUCCESS!")
            lengths = re.findall(r"\[induction step (\d+)\]", output)
            report["proofs"].append({"timeout": timeout, "mode": label, "status": "proven",
                                     "induction_length": int(lengths[-1]), "script": str(out / (name + '.ys'))})
            print(f"PASS: formal timeout={timeout} {label}, induction length {lengths[-1]}", flush=True)
        for index, cover in enumerate(COVERS):
            name = f"timeout-{timeout}-cover-{cover}"
            depth = 2*timeout+16
            execute(out, name, [f"read_rtlil {out / ('timeout-' + str(timeout) + '-safety.il')}",
                "chformal -assert -remove", "opt_clean",
                f"sat -seq {depth} -set-assumes -prove reached[{index}] 0 -falsify -timeout 20 -show-ports -dump_vcd {out / (name + '.vcd')}"],
                "SAT proof finished - model found: FAIL!")
            report["covers"].append({"timeout": timeout, "scenario": cover, "status": "reached",
                                    "mode": "safety", "search_depth": depth, "witness": str(out / (name + '.vcd'))})
        # Demonstrate that progress assumptions permit a real sleep/wake trace.
        name = f"timeout-{timeout}-progress-cover"
        execute(out, name, [f"read_rtlil {out / ('timeout-' + str(timeout) + '-progress.il')}",
            "chformal -assert -remove", "opt_clean",
            f"sat -seq {depth} -set-assumes -prove reached[7] 0 -falsify -timeout 20 -show-ports -dump_vcd {out / (name + '.vcd')}"],
            "SAT proof finished - model found: FAIL!")
        report["covers"].append({"timeout": timeout, "scenario": "sleep_wake_round_trip", "status": "reached",
                                "mode": "progress", "search_depth": depth, "witness": str(out / (name + '.vcd'))})
        print(f"PASS: formal timeout={timeout}, {len(COVERS)} safety covers and a progress-environment witness", flush=True)

    # A negative control ensures the assertion harness detects an actual RTL bug.
    original = Path(SOURCES[0]).read_text()
    anchor = "SLEEP: if (wake_seen) state_d = START;"
    if original.count(anchor) != 1:
        raise RuntimeError("lost-wake mutation anchor changed")
    mutant = out / "lost-wake.sv"
    mutant.write_text(original.replace(anchor, "SLEEP: state_d = SLEEP;"))
    execute(out, "lost-wake", prepare(3, 0, str(mutant)) + [
        f"sat -seq 24 -set-assumes -prove-asserts -verify -timeout 20 -show-ports -dump_vcd {out / 'lost-wake.vcd'}"],
        "SAT proof finished - model found: FAIL!", failure=True)
    report["negative_control"] = {"mutation": "lost SLEEP wake transition", "status": "detected",
                                   "witness": str(out / "lost-wake.vcd")}
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['proofs'])} inductive proofs, {len(report['covers'])} cover witnesses; lost-wake mutation detected", flush=True)


if __name__ == "__main__":
    main()
