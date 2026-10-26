#!/usr/bin/env python3
"""Inject two M2 RTL faults in build copies; fail if either fault escapes detection."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess

from run_m2 import ROOT, SOURCES, compile_tb

MUTATIONS = {
    "lost-wake": (
        "SLEEP: if (wake_seen) state_d = START;", "SLEEP: state_d = SLEEP;",
        "M2: wake enters START"),
    "early-clock-stop": (
        "DRAIN: isolate_o = 0;",
        "DRAIN: begin isolate_o = 0; if (!idle_i) clk_en_o = 0; end",
        "scoreboard: unsafe clock shutdown with outstanding work"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="copy patches, diagnostics and manifest to this directory")
    args = parser.parse_args()
    os.chdir(ROOT)
    out = Path("build/mutations")
    out.mkdir(parents=True, exist_ok=True)
    source_path = Path(SOURCES[0])
    original = source_path.read_text()
    manifest = {"seed": 17, "timeout": "default (8)",
                "source_sha256": {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in SOURCES},
                "mutations": []}
    # Positive control: identical harness/seed must pass before fault injection.
    control = out / "control.vvp"
    compile_tb(control, "default")
    control_command = shlex.split(os.environ.get("VVP", "vvp")) + [str(control), "+SEED=17", f"+COVERAGE={out / 'control.csv'}"]
    control_result = subprocess.run(control_command, text=True, capture_output=True, timeout=30)
    (out / "control.log").write_text(control_result.stdout + control_result.stderr)
    if control_result.returncode or "PASS: M2" not in control_result.stdout:
        raise RuntimeError("mutation positive control failed")
    manifest["control_command"] = control_command
    for name, (old, new, expected) in MUTATIONS.items():
        if original.count(old) != 1:
            raise RuntimeError(f"mutation anchor must match exactly once: {name}")
        modified = original.replace(old, new)
        mutant = out / f"{name}.sv"
        mutant.write_text(modified)
        patch = out / f"{name}.patch"
        patch.write_text("".join(difflib.unified_diff(original.splitlines(True), modified.splitlines(True),
                                                    fromfile="a/rtl/power_manager.sv", tofile="b/rtl/power_manager.sv")))
        executable = out / f"{name}.vvp"
        compile_command = compile_tb(executable, "default", str(mutant))
        command = shlex.split(os.environ.get("VVP", "vvp")) + [str(executable), "+SEED=17",
                    f"+COVERAGE={out / (name + '.csv')}", f"+VCD={out / (name + '.vcd')}"]
        result = subprocess.run(command, text=True, capture_output=True, timeout=30)
        diagnostic = result.stdout + result.stderr
        (out / f"{name}.log").write_text(diagnostic)
        if result.returncode == 0 or expected not in diagnostic:
            raise RuntimeError(f"{name} escaped or failed for an unexpected reason:\n{diagnostic}")
        manifest["mutations"].append({"name": name, "compile_command": compile_command,
                                      "run_command": command, "exit_status": result.returncode,
                                      "expected_diagnostic": expected})
        print(f"PASS: detected {name}: {expected}")
    if source_path.read_text() != original:
        raise RuntimeError("production RTL changed during mutation tests")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.archive:
        args.archive.mkdir(parents=True, exist_ok=True)
        for name in ["manifest.json", "control.log"] + [f"{m}.{ext}" for m in MUTATIONS for ext in ("patch", "log")]:
            shutil.copyfile(out / name, args.archive / name)
    print("PASS: positive control and 2/2 expected mutation failures; production RTL unchanged")


if __name__ == "__main__":
    main()
