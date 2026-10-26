#!/usr/bin/env python3
"""Generic cell synthesis and structural checks, without physical PPA claims."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["rtl/power_manager.sv", "rtl/cdc_primitives.sv",
           "rtl/power_manager_cdc.sv", "rtl/power_manager_retention.sv"]


def main():
    os.chdir(ROOT)
    out = Path("build/synthesis")
    out.mkdir(parents=True, exist_ok=True)
    yosys = shlex.split(os.environ.get("YOSYS", "yosys"))
    version = subprocess.run(yosys + ["-V"], text=True, capture_output=True, check=True).stdout.strip()
    report = {"tool": version, "mapping": "Yosys generic gates, no Liberty library or physical constraints",
              "source_sha256": {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in SOURCES}, "designs": []}
    for top in ["power_manager", "power_manager_cdc", "power_manager_retention"]:
        script = out / f"{top}.ys"
        script.write_text("\n".join([
            "read_verilog -sv " + " ".join(SOURCES), f"hierarchy -check -top {top}",
            "proc", "select -assert-none t:$dlatch t:$adlatch", "check -assert",
            f"synth -top {top} -flatten", "check -assert",
            "select -assert-none t:*LATCH* t:$dlatch t:$adlatch",
            f"tee -o {out / (top + '.stat.json')} stat -json",
            f"write_json {out / (top + '.netlist.json')}",
            f"write_verilog -noattr {out / (top + '.netlist.v')}"
        ]) + "\n")
        result = subprocess.run(yosys + ["-Q", "-T", "-s", str(script)], text=True, capture_output=True, timeout=60)
        (out / f"{top}.log").write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f"synthesis failed for {top}: {result.stderr}")
        stats = json.loads((out / f"{top}.stat.json").read_text())
        module = stats["modules"]["\\" + top]
        cells = module["num_cells_by_type"]
        flops = sum(count for cell, count in cells.items() if "DFF" in cell)
        report["designs"].append({"top": top, "cells": module["num_cells"], "flip_flops": flops, "cell_types": cells,
                                  "latches": 0, "structural_check": "passed", "script": str(script)})
        print(f"PASS: synthesis {top}: {module['num_cells']} generic cells, zero latches, structural checks passed", flush=True)
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
