# Power-Manager Race Verification

An educational SystemVerilog project focused on safe sleep/wake sequencing and event races. Target: VLSI design-verification portfolio, with later RTL synthesis and physical-design extensions.

## What problem are we solving?

A hardware block must finish its accepted work before its clock stops. Its outputs must be isolated before it becomes unavailable. Wakeup must restore a usable clock before work is accepted again. A request arriving at the wrong transition can otherwise cause lost wakeups, unfinished transactions, or a stuck system.

The always-on controller stays clocked while the managed domain sleeps. Its state machine coordinates shutdown and restart. Verification deliberately places conflicting events on the same cycle and around transition boundaries.

## Current scope: clock sleep, CDC, and modeled power gating

One managed domain, one always-on clock, synchronous control inputs, clock-gated sleep (power remains on), a sticky wake flag during transitions, a request rearm mechanism, bounded waits, a sticky fault output, and a self-checking directed testbench. This is plain SystemVerilog, not UVM.

The baseline testbench drives acknowledgements directly. M2 adds a single-slot managed workload, independent transaction scoreboard, seeded clock-readiness model, race coverage, timeout sweeps and mutation checks. M3 wraps the synchronous core with separate clock domains, synchronized control handshakes, wake-pulse capture and local reset release. M4 adds a separate power-gating sequencer, behavioral power loss and isolation, retained-state save/restore, and an independent data scoreboard. There is no physical clock gate, isolation cell, power switch, retention cell, UPF simulation, physical CDC signoff, or measured power saving yet. `clk_en_o` and `clock_req_o` are logical requests; never AND them directly with a clock in hardware. An implementation must use an appropriate glitch-free clock controller and meet control timing.

M5 adds inductive safety and conditional progress proofs for the synchronous
core, reachability witnesses, and generic synthesis of all three controllers.
The proofs use explicit sampled-reset and acknowledgement assumptions; the
multi-clock and retention configurations retain their simulation scope.

## Sequence

RUN -> DRAIN -> ISOLATE -> SLEEP -> START -> RELEASE -> RUN

- RUN: work allowed; clock requested on; outputs connected.
- DRAIN: block new work, allow accepted work to finish, wait for idle.
- ISOLATE: isolate outputs for a full controller cycle before stopping the clock.
- SLEEP: clock requested off; isolation and work blocking remain asserted.
- START: clock requested on; wait for clock-ready acknowledgement.
- RELEASE: hold isolation for one more controller cycle, then resume RUN.
- FAULT: keep work blocked and outputs isolated; request clock on; reset required.

Wake in DRAIN aborts entry. Wake in ISOLATE cancels clock shutdown through RELEASE. Wake in SLEEP starts the clock. Wake wins a simultaneous sleep request in RUN. See `docs/specification.md` for interface contracts and exact deadline priorities.

The separate M4 configuration saves state before isolation, stops the clock
before removing power, and restores state before reopening admission. A wake
during its shutdown is retained while shutdown completes, then triggers restart.
See [M4 retention](docs/m4-retention.md) for that sequence and fault policy.

## Run

Requires Icarus Verilog with SystemVerilog support (`iverilog`, `vvp`), Make and Python 3 (standard library only).

```sh
cd power-manager
make test
```

A failing check exits with a nonzero status. `make test` runs the baseline, workload integration, twelve M2 seed/timeout combinations, two expected-failure RTL mutation checks, twenty-four M3 clock/phase/delay combinations, and twelve M4 retention/fault configurations plus an expected-failure restore-corruption check. The baseline waveforms are `build/power_manager.vcd` and `build/workload.vcd`; coverage and replay logs are under `build/m2/`, `build/m3/` and `build/m4/`. `make clean` removes generated build files. See [M2 verification](docs/m2-verification.md), [M3 CDC verification](docs/m3-cdc.md) and [M4 retention](docs/m4-retention.md) for the contracts, coverage scope and replay commands.

`make m5` runs formal and synthesis checks using Yosys and its bundled ABC;
`make check` runs simulations plus M5. No external SMT solver is required.
See [M5 formal and synthesis](docs/m5-formal-synthesis.md) for assumptions,
proof scope, cell counts and constraint limitations. Archived evidence is in
`reports/m5/`; generated netlists and complete replay scripts are in `build/`.

Start with the [architecture and FSM diagrams](docs/architecture.md),
[annotated waveforms](docs/waveforms.md), and [verification matrix](docs/verification-matrix.md).
For implementation details, read `docs/specification.md`, `rtl/power_manager.sv`,
then `tb/tb_power_manager.sv`. The [milestone checklist](docs/milestones.md) records
completion and remaining review items.

## Why this can become a strong project

The final evidence should be a traceable specification, protocol-aware workload model, independent scoreboard, race coverage, seeded regressions, intentionally broken RTL caught by tests, and formal safety/liveness checks with explicit assumptions. A basic FSM alone is only the starting point.

The design is original educational RTL. OpenTitan's power-manager documentation is architectural background, not a claim of OpenTitan compatibility or verification:
https://opentitan.org/book/hw/top_earlgrey/ip_autogen/pwrmgr/doc/theory_of_operation.html

The tested M5 snapshot is published at
[Sean184344/power-manager](https://github.com/Sean184344/power-manager), commit
[`d136475`](https://github.com/Sean184344/power-manager/commit/d136475800f6b3f1c1e3f6cf4831973db5143e26).
M6 adds portfolio documentation and an automated regression workflow.
See the milestone checklist for the latest hosted CI status.
See [portfolio notes](docs/portfolio.md) for measured resume claims, release review
and CI scope. No license has been selected; the owner's license decision remains pending.
