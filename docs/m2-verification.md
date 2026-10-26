# M2 verification scope and replay

M2 verifies the synchronous, single-domain clock-sleep contract with a single
outstanding transaction. It does not introduce separate domain clocks or CDC;
those belong to M3. The controller RTL is unchanged.

## Environment

- `managed_workload.sv` accepts IDs and positive work latencies, completes accepted
  work while admission is blocked, and derives idle from its pending slot.
- `clock_controller.sv` observes the logical clock-enable request. Delay D makes
  readiness visible before the Dth START sampling edge. Readiness stays high
  until reset or clock disable. Delay zero selects a seeded delay from 1 through
  N+2, where N is the controller timeout; positive delays select directed cases.
- `tb_m2.sv` permits worker progress only when both clock enable and readiness
  are high. It does not generate a physical clock. Model outputs change on
  falling edges; stimulus changes one time unit later, avoiding sampling races.
- `transaction_scoreboard.sv` checks public request/completion signals against its
  own transaction ID, age and counters. The M2 runner settles work before each
  reset: reset cannot silently remove a transaction from the random tests.
  Reset cancellation remains separately tested by `tb_workload.sv`.

Each M2 run includes directed race cases, every clock delay from 1 to N+2,
32 random clock-start episodes, and 100 random workload/wake episodes. The latter
vary work latency from 1 to N+3, wake arrival from the first DRAIN edge to its
nominal deadline, and whether wake is asserted. If draining finishes earlier,
the scheduled wake may instead hit ISOLATE, SLEEP or restart. Phase coverage uses
actual sampled events, not the stimulus's intended phase.

The two random generators use explicit 32-bit xorshift state and separate seed
initialization. Seeds are printed for replay. The default regression runs seeds
1, 17 and 2026 for N=1, 2, 3 and the unoverridden RTL default (currently 8).

## Coverage plan

Coverage observes state and inputs immediately before rising edges. The first
edge spent in DRAIN/START is age 1; age N is the deadline. An `early` event has
age less than N. Completion/outputs are checked after sequential updates.

| Sampled event | Required combinations |
|---|---|
| Wake in RUN | workload idle / busy |
| Wake in DRAIN | idle / busy crossed with early / deadline |
| Wake in ISOLATE, SLEEP, RELEASE | idle in each phase |
| Wake in START | clock ready / waiting crossed with early / deadline; workload idle |
| Wake in FAULT | idle; requests cannot escape lockout |
| Idle acknowledgement in DRAIN without wake | early / deadline |
| Ready acknowledgement in START | early / deadline |
| Timeout | DRAIN / START |
| Selected clock-start delay | every integer from 1 through N+2 |

The model contract requires work to finish before ISOLATE, SLEEP, START after
sleep, or RELEASE. Global reset cancels any outstanding work; FAULT is reached
from START. Busy combinations in those phases are therefore illegal, not missing
coverage. RUN/ISOLATE/SLEEP/RELEASE/FAULT have no deadline. For N=1, early DRAIN
and START events are impossible; those six bins are excluded explicitly.

There are 17 required bins for N=1, 24 for N=2, 25 for N=3, and 30 for default 8.
Every bin must be hit in **each** seed/parameter run; aggregate coverage cannot
hide a missing run. The runner also rejects unplanned bin names. CSV event logs
and JSON hit counts are written under `build/m2/`. This is closure of this finite
M2 test plan, not exhaustive state-space coverage or formal proof.

## Commands and artifacts

Requirements: Icarus Verilog/vvp, Make, and Python 3 (standard library only).

```sh
make test                         # baseline, workload, M2 matrix, mutation checks
make m2                           # M2 matrix only
python3 scripts/run_m2.py --timeouts 3 --seeds 17
make mutations                    # positive control and expected failures
```

`build/m2/coverage.json` contains per-run hit counts and replay commands.
Each run has a compile log, simulation log, CSV events, and compiled executable.
The runner replays its first parameter/seed pair and compares both simulation
output and raw coverage events byte-for-byte. Coverage counts are checked on
every run. Add `+VCD=build/replay.vcd` to a recorded vvp command for a waveform.
The historical baseline and workload waves remain `build/power_manager.vcd`
and `build/workload.vcd`. `make clean` removes generated build artifacts.

## Mutation evidence

Two deliberate RTL faults are applied only to copies in `build/mutations/`:

1. Lost wake: remove the SLEEP-to-START transition. The directed wake assertion
   fails immediately; the test does not rely on waiting for the global watchdog.
2. Early clock stop: deassert clock enable in DRAIN while idle is low. The
   scoreboard detects shutdown with a pending transaction.

An unmodified positive control must pass using the same harness and seed 17.
Each mutant must compile, exit nonzero, and produce its specific expected
assertion message. Compilation failures or unrelated failures do not count as
successful detection. The production RTL's contents must remain unchanged.

The reviewed evidence is in `reports/m2_mutations/`: patches, logs, source SHA-256
hashes, compiler/run commands and expected diagnostics. Regenerate it explicitly:

```sh
python3 scripts/run_mutations.py --archive reports/m2_mutations
```

Ordinary `make test` writes fresh mutation evidence only under `build/`.
Mutation waveforms are also generated there. These two mutations demonstrate
specific detectors; they are not a broad mutation-score claim.
