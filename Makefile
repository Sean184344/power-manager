IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python3
YOSYS ?= yosys
.DEFAULT_GOAL := test
export IVERILOG VVP YOSYS
.PHONY: test m2 m3 m4 mutations formal synthesis schematic m5 check clean

check: test m5

m5: formal synthesis

formal:
	$(PYTHON) scripts/run_formal.py

synthesis:
	$(PYTHON) scripts/run_synthesis.py

# Optional presentation output; requires Graphviz (dot) in addition to Yosys.
schematic: synthesis
	$(YOSYS) -Q -T -p 'read_json build/synthesis/power_manager.netlist.json; show -format svg -viewer none -prefix build/synthesis/power_manager-schematic power_manager'

test: build/tb.vvp build/workload.vvp
	$(VVP) build/tb.vvp
	$(VVP) build/workload.vvp
	$(PYTHON) scripts/run_m2.py
	$(PYTHON) scripts/run_mutations.py
	$(PYTHON) scripts/run_m3.py
	$(PYTHON) scripts/run_m4.py

m2:
	$(PYTHON) scripts/run_m2.py

m3:
	$(PYTHON) scripts/run_m3.py

m4:
	$(PYTHON) scripts/run_m4.py

mutations:
	$(PYTHON) scripts/run_mutations.py

build/m2.vvp: rtl/power_manager.sv tb/models/managed_workload.sv tb/models/transaction_scoreboard.sv tb/models/clock_controller.sv tb/tb_m2.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_m2 -o $@ $^

build/workload.vvp: rtl/power_manager.sv tb/models/managed_workload.sv tb/models/transaction_scoreboard.sv tb/tb_workload.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_workload -o $@ $^

build/tb.vvp: rtl/power_manager.sv tb/tb_power_manager.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_power_manager -o $@ $^

clean:
	rm -rf build
