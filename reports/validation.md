# Baseline validation — 2026-10-26

Tool: Icarus Verilog 12.0 (Ubuntu package 12.0-2build2).
Compiled with `-g2012 -Wall -s tb_power_manager`. No compiler warnings were emitted.
Executed with vvp; exit status 0.

```text
PASS: 16 scenarios, 73 explicit checks plus continuous safety monitors
```

Scenarios: normal sleep/wake; held request and rearm; simultaneous wake/sleep;
wake with idle; wake during isolation; drain timeout; wake on drain deadline;
idle on drain deadline; clock-start timeout and fault lockout; ready on start deadline;
reset in RUN, DRAIN, ISOLATE, SLEEP, START and RELEASE.

All baseline scenarios use TIMEOUT_CYCLES=4. Parameter sweeps and random coverage
are future work. This is directed RTL simulation, not formal proof, CDC signoff,
physical low-power verification, or a functional-coverage closure claim.

Run on a machine with Icarus installed: `make test`.
The session used a locally extracted Icarus package because a system-wide install
was unavailable. The simulator package and build outputs are not part of the source archive.

## Workspace revalidation — 2026-10-26

Read the README, specification, milestone checklist, baseline report, RTL and
testbench. System tools now available on PATH:

| Tool | Version |
|---|---|
| Icarus Verilog / vvp | 12.0 / 12.0 |
| Verilator | 5.020 |
| Yosys | 0.33 (2584903a060) |
| GNU Make | 4.3 |

`iverilog`, `vvp`, `verilator` and `yosys` resolve under `/usr/bin`.
GHDL, SymbiYosys (`sby`), nextpnr-ice40, Vivado and Quartus (`quartus_sh`)
were not found on PATH.

`make test` rebuilt `build/tb.vvp` with `iverilog -g2012 -Wall -s
tb_power_manager`, then ran vvp. No compiler warnings were emitted; exit status
was 0, with the same 16 scenarios and 73 explicit checks plus safety monitors
passing. Waveforms were written to `build/power_manager.vcd`.

The testbench still uses TIMEOUT_CYCLES=4 (RTL default: 8). Verilator and Yosys
versions were checked, but lint, synthesis and formal validation were not run.
No RTL or testbench changes were made. The workspace is not currently a Git
repository; nothing was pushed to GitHub.

## M2 increments: managed workload and scoreboard — 2026-10-26

Before changes, `make test` passed the existing 16 scenarios and 73 checks.
The first increment added `tb/models/managed_workload.sv`, `tb/tb_workload.sv`
and a Makefile target. `make test` then passed the baseline plus four workload
scenarios with 33 explicit checks. The second increment added
`tb/models/transaction_scoreboard.sv` and connected it to the integration test.
`make test` passed again with no compiler warnings, exit status 0:

```text
PASS: 16 scenarios, 73 explicit checks plus continuous safety monitors
PASS: scoreboard accepted=6 completed=5 reset-canceled=1 outstanding=0
PASS: workload 4 scenarios, 33 explicit checks
```

The four workload scenarios exercise:

- Acceptance on the RUN-to-DRAIN edge, completion before isolation, rejected
  offers during shutdown, sleep and restart, and admission after returning to RUN.
- Wake during busy DRAIN, preserving the pending transaction through the abort.
- Drain timeout with unfinished work, subsequent completion, and rearmed sleep
  despite the sticky fault.
- Reset with outstanding work, explicit cancellation accounting, and completion
  of a new transaction in the next reset epoch.

The scoreboard uses public signals only, with its own pending transaction ID,
latency/age, and counts. It verifies readiness, completion timing and identity,
idle consistency, counters, work-admission safety, and no isolation or clock
shutdown while work remains. Reset cancellation is modeled explicitly rather
than counted as successful completion. The workload has one outstanding slot;
latencies exercised are 1, 3 and 7 enabled cycles. Both testbenches still use
TIMEOUT_CYCLES=4.

Three temporary model corruptions were separately compiled with the normal
integration test and scoreboard. Each simulation exited nonzero with the
expected scoreboard diagnostic:

| Model substitution | Expected diagnostic observed |
|---|---|
| `done_id_o <= id_q + 1;` instead of `done_id_o <= id_q;` | completion ID mismatch |
| `done_o <= 0;` instead of the completion-path `done_o <= 1;` | missing or unexpected completion |
| `assign idle_o = 1'b1;` instead of `assign idle_o = !busy_q;` | idle disagrees with outstanding work |

Local mutant sources and logs are in `build/scoreboard_checks/` (removed by
`make clean`). These are scoreboard sanity checks, not completion of the planned
lost-wake/early-clock-stop RTL mutation milestone. Production sources were not
modified by these checks. A final normal `make test` passed and restored normal
waveforms after the negative runs.

Controller RTL remains unchanged. M2's workload and scoreboard items are now
complete for the documented single-slot contract. Randomized clock-controller
acknowledgements, systematic race coverage, seeded regressions, timeout parameter
sweeps and the planned RTL mutations remain pending. Nothing was pushed to GitHub.

## M2 completion — 2026-10-26

The baseline was rerun before implementation and remained green. Changes were
verified incrementally:

1. Added the clock-controller model and integration harness. Thirty-two seeded
   restart trials passed at timeout 8 (437 explicit checks), including late-ready
   fault lockout. Baseline and workload tests also passed.
2. Added observed race coverage, seeded workload/wake timing, and timeout sweeps.
   An initial harness assumption failed when a random wake reached RELEASE rather
   than DRAIN; the harness was corrected to allow that legal phase progression.
   No controller RTL change was needed. All twelve parameter/seed runs then passed.
3. Added temporary lost-wake and early-clock-stop RTL mutations. Both compiled and
   failed the exact expected checks; the same-seed unmodified positive control
   passed. Patches, source hashes, commands and diagnostic logs were archived.
4. Ran `make clean && make test` successfully from rebuilt artifacts. Icarus 12.0
   emitted no compiler warnings. All suites and mutation checks exited as expected;
   the top-level command exited 0.

| Suite | Final result |
|---|---|
| Baseline | 16 scenarios, 73 explicit checks plus safety monitors |
| Original workload integration | 4 scenarios, 33 checks; 6 accepted, 5 completed, 1 explicitly reset-canceled |
| M2 timeout 1, seeds 1/17/2026 | 3 passes; 17/17 required bins per run; 105 accepted and completed per run |
| M2 timeout 2, seeds 1/17/2026 | 3 passes; 24/24 required bins per run; 107 accepted and completed per run |
| M2 timeout 3, seeds 1/17/2026 | 3 passes; 25/25 required bins per run; 107 accepted and completed per run |
| M2 unoverridden default 8, seeds 1/17/2026 | 3 passes; 30/30 required bins per run; 107 accepted and completed per run |
| Deterministic replay | First parameter/seed pair produced identical stdout and raw event CSV |
| RTL mutations | 2/2 detected with specific assertions; positive control passed |

Across the twelve M2 runs, all 1,278 accepted transactions completed; none were
reset-canceled or outstanding. Each run includes 32 random clock-start episodes
and 100 random workload/wake episodes, plus directed cases. This transaction total
excludes replay and mutation positive-control runs. The earlier workload test
continues to check intentional reset cancellation separately.

Lost wake removes the SLEEP-to-START transition and fails `M2: wake enters START`.
Early clock stop disables the clock in busy DRAIN and fails
`scoreboard: unsafe clock shutdown with outstanding work`. These are expected
simulation failures; the mutation runner succeeds only when both are detected.
It also verifies that the production RTL remains unchanged.

The coverage plan, impossible-bin exclusions, exact commands and model timing
contract are in `docs/m2-verification.md`. Reviewed evidence persists across
`make clean` in `reports/m2-coverage.json` and `reports/m2_mutations/`. Fresh logs,
CSV events, compiled simulations and mutation waveforms are generated in `build/`.

M2's exit criteria are met for this finite single-slot synchronous model. This
is not formal proof, CDC validation, physical clock-gating verification or an
exhaustive mutation study. M3 has not started. Work stops here for user review;
nothing has been pushed to GitHub.

## M3 completion — CDC and reset races

Added `rtl/cdc_primitives.sv` and `rtl/power_manager_cdc.sv`, wrapping the existing
synchronous controller with held request/acknowledge crossings, wake-pulse capture,
and per-domain reset release. The wrapper waits for handshake cleanup before a
new sleep attempt and for readiness to fall before restarting the clock, preventing
reuse of stale acknowledgements. `docs/m3-cdc.md` defines the interface contract.

The asynchronous reset tests exposed a scoreboard issue: its sampling delay could
hide a reset event. Reset accounting now runs in a separate process, and delayed
output checks are skipped while reset is asserted. The existing M2 tests pass
with this correction. Historical M2 evidence records its earlier source hashes;
fresh M2 logs and mutation results are available under `build/`.

The final `make test` exited 0. The baseline passed 16 scenarios and 73 checks;
the original workload test passed four scenarios and 33 checks. All twelve M2
seed/timeout runs passed, and both intentional RTL mutations were detected.

M3 passed all 24 clock/phase/delay configurations with all 18 required scenarios
per configuration. AON period was 10 ns; source periods were 6, 10, 14 and 26 ns;
phase offsets were 0, 1 and 4 ns; startup delays were 1 and 7 source cycles.
All 24 M3 compiler logs were empty: no warnings were emitted.

| M3 accounting | Per configuration | Across 24 configurations |
|---|---:|---:|
| Work accepted | 5 | 120 |
| Work completed | 3 | 72 |
| Work explicitly canceled by reset | 2 | 48 |
| Wake events captured | 19 | 456 |
| Wake events delivered | 18 | 432 |
| Wake events explicitly canceled by reset | 1 | 24 |

No work or wake events remain unaccounted for. Scenarios include work admitted
during synchronization delay, repeated wake events, delayed quiesce acknowledgement,
abort and immediate rearm, stale clock readiness, drain/start timeout, reset in
all seven FSM states, and reset with a pending wake. Reset monitors check release
on the second local clock edge, including restart of a stopped managed clock.

The archived report is `reports/m3-coverage.json`, containing source hashes,
scenario hit counts, accounting and replay commands. Fresh logs and CSVs are in
`build/m3/`. `make m3` reruns the matrix; the replay commands and waveform option
are documented in `docs/m3-cdc.md`.

M3's documented digital simulation exit criteria are met. Metastability, MTBF,
physical clock cells, placement and CDC/RDC signoff remain outside this evidence.
Work stops at the milestone boundary for review. M4 has not started, and nothing
has been pushed to GitHub.

## M4 completion — power gating and retention

Added `rtl/power_manager_retention.sv`, a separate power-gating sequencer using
the M3 CDC primitives. It drains work, saves state, clears the save handshake,
isolates outputs, stops the clock, and removes power. Wake waits for power and
clock acknowledgements, releases local reset, restores state and clears the
restore handshake before reopening admission. Wake during shutdown is retained
until the power-off sequence completes. Global reset deliberately discards the
retention snapshot. Missing responses enter a reset-required fault.

Added behavioral supply and retention-domain models. The saved bank survives
ordinary domain reset and power loss, while the raw unpowered output becomes
unknown and isolation clamps the boundary to zero. An independent scoreboard
derives expected values only from accepted workload writes and checks completion,
save/restore responses, exposed data and shutdown ordering.

Implementation and verification were incremental:

1. A complete busy-work/save/power-off/restore test passed. It exposed an unknown
   reset output before a stopped domain's first clock edge; the controller now
   explicitly qualifies reset with the reset/power conditions.
2. The independent scoreboard and directed faults passed. Unexpected supply-loss
   handling immediately asserts isolation/reset and suppresses active status
   while the synchronized fault indication propagates.
3. Twelve clock/phase/delay configurations passed all 15 required scenarios.
   The shared behavioral clock model now accepts a reset-request parameter:
   M4 starts disabled, while M3 keeps its existing enabled default.
4. A deliberately corrupted restore exited nonzero with the exact diagnostic
   `retention scoreboard: restored data mismatch`. The same configuration without
   corruption passed; unrelated failures do not count as corruption detection.
5. Final `make test` exited 0, passing the baseline, all M2/M3 runs, both earlier
   RTL mutation checks, all M4 runs and the expected restore-corruption failure.
   All twelve M4 compiler logs were empty; no compiler warnings were emitted.

| M4 result | Evidence |
|---|---|
| Clock matrix | AON 10 ns; source/domain 6, 14 and 26 ns; phases 1 and 4 ns; response delays 1 and 5 cycles |
| Directed checks | 15 required scenarios and 145 explicit checks per configuration, plus scoreboard monitors |
| Transactions | 15 accepted and completed per configuration; 180 total, none canceled or outstanding |
| Save/restore | 13 successful saves and 8 successful restores per configuration; remaining attempts intentionally fault or reset |
| Delayed responses | Save 8 domain cycles, restore 9; wake-race delays 12 cycles |
| Missing/stuck responses | Correct fault on the 64th wait edge, with no premature timeout |
| Corruption detection | One-bit restore corruption rejected by the independent scoreboard |

Scenarios cover normal and repeated retention, delayed save/restore, wake actually
delivered during SAVE and POWER_DOWN, missing power-good/clock-ready/save/restore,
stuck save/restore acknowledgements, missing power-off acknowledgement, unexpected
supply loss, reset while off, and reset during restore. Fault scenarios verify
safe isolation/reset rather than claiming a successful recovery from bad data.

Reviewed evidence is in `reports/m4-coverage.json` (source hashes, scenario counts,
accounting and replay commands) and `reports/m4-corrupt.log`. Fresh logs, CSVs and
corruption waveforms are in `build/m4/`. `make m4` reruns the suite. M3 coverage
was refreshed after its passing regression to record the shared model's current
source hash. `docs/m4-retention.md` documents replay and the finite test scope.

M4's exit criteria are met under the behavioral model contracts. These results
are not UPF-aware simulation, analog power verification, retention-cell signoff,
physical CDC signoff, or measured power savings. M5 has not started. Work stops
at the milestone boundary for review, and nothing has been pushed to GitHub.

## M5 completion — formal and synthesis

Yosys 0.33 (2584903a060) and its built-in SAT engine were available; SymbiYosys and
external SMT solvers were not found on PATH. The new flow requires no additional
solver. `make check` exited 0 after running every earlier simulation suite and
the M5 formal/synthesis checks.

Formal verification targets the synchronous `power_manager.sv` core. Safety is
proven for arbitrary synchronous inputs after an initial sampled reset. Conditional
progress additionally assumes idle and clock-ready by their respective deadlines.
Reset cancels pending progress obligations. The asynchronous reset implementation
is converted to a sampled model for this proof; analog reset timing, CDC and
retention data are not covered by the formal claim.

| Timeout | Safety induction length | Progress induction length |
|---|---:|---:|
| 1 | 3 | 5 |
| 2 | 3 | 6 |
| 3 | 5 | 7 |
| 8 | 9 | 12 |

All eight checks completed both base and induction steps. These are inductive
proofs under the documented model and assumptions, not merely bounded searches.
Assertions check safe outputs, legal states, sticky fault and lockout, wake and
ready priority, sequencing, request rearming and bounded waits. Under timely
acknowledgements, no fault occurs and a sampled sleep wake reaches RUN within
TIMEOUT+2 steps unless reset intervenes.

The first progress induction attempt reached its configured depth without proving
the request-history property, although its base cases passed. The final harness
adds an asserted invariant connecting observed request consumption to the core's
rearm latch. A `FORMAL`-only debug port exposes that latch; normal behavior and
normal synthesized ports are unchanged. No state invariant is assumed to bypass
the proof.

Forty-eight safety-environment cover witnesses reach all seven states and five
transition/deadline scenarios across the four timeouts. Four additional witnesses
show sleep/wake round trips under the progress assumptions. A temporary RTL copy
with the SLEEP wake transition removed produces the expected assertion
counterexample. Compilation errors or unrelated failures do not count as a
successful negative control.

| Synthesized top | Default timeout | Generic cells | Flip-flops | Latches |
|---|---:|---:|---:|---:|
| power_manager | 8 | 116 | 9 | 0 |
| power_manager_cdc | 64 | 186 | 40 | 0 |
| power_manager_retention | 64 | 577 | 74 | 0 |

All hierarchy and structural checks passed, with latch rejection before and after
mapping. No synthesis warnings were emitted. Cell statistics use generic Yosys
mapping: no Liberty library, PDK, load or physical timing constraints were applied.
Simulation periods are documented stimulus settings, not validated synthesis
constraints. These counts do not establish area, frequency, power or physical
multi-domain implementation. The optional OpenROAD study is deferred.

The contract, constraints and commands are in `docs/m5-formal-synthesis.md`.
`reports/m5/formal.json` and `reports/m5/synthesis.json` contain source hashes and
results; subdirectories retain complete proof/synthesis logs and representative
cover/counterexample VCDs. `make m5` regenerates every script, trace and netlist
under `build/`. M2 mutation and M3 archived evidence was refreshed from the passing
regression because their source hashes now include the formal-only core port.

M5 is complete within this explicit scope. M6 has not started. Work stops for
milestone review; nothing has been pushed to GitHub.

## M6 local review — 2026-10-27

The earlier publication statements above describe their historical sessions.
Following the user's publication request, the complete M5 snapshot was published
to `Sean184344/power-manager` on `main` at
`d136475800f6b3f1c1e3f6cf4831973db5143e26`. The GitHub ref was read back and matched.
Publication used the GitHub API because this workspace has no usable Git metadata.

M6 adds architecture/FSM diagrams, a verification matrix, measured resume bullets,
and a review of scope and limitations. Two annotated SVG timing diagrams are
rendered from the passing baseline VCD: normal sleep/wake and clock-start timeout.
The VCD and capture/source hashes are retained in `reports/m6/`. The renderer uses
Python's standard library and can reproduce the diagrams from a fresh regression.
README now links the explanatory artifacts and records the published snapshot.
Ignore rules retain curated report VCDs and exclude Windows Zone.Identifier files.

Verification was incremental:

1. The interrupted pre-change `make check` completed with exit 0.
2. After documentation and waveform rendering changes, `make test` exited 0.
   The complete output is in `reports/m6/test.log`.
3. Added `.github/workflows/regression.yml` for Ubuntu 24.04. It installs tools,
   records their versions, runs `make check`, reproduces the SVGs, and retains
   build evidence even when a check fails. The workflow uses read-only repository
   permissions and disables checkout credential persistence.
4. After `make clean`, `make check` exited 0. The baseline passed 16 scenarios /
   73 checks and workload integration passed 4 scenarios / 33 checks. All 12 M2,
   24 M3 and 12 M4 configurations passed; expected simulation mutations and
   restore corruption were detected. Eight inductive proofs and 52 cover
   witnesses passed, including formal lost-wake detection. Synthesis again
   produced 116 / 186 / 577 generic cells with zero latches. Complete output:
   `reports/m6/check.log`.
5. Workflow YAML parsing and local configuration checks passed. Both SVGs parsed
   as XML and matched fresh simulation renders byte for byte. Capture/source
   hashes and relative Markdown file links passed. RTL and formal harness hashes
   match the archived M5 reports. No functional RTL changes were made for M6.

Local checks do not execute GitHub's runner, package installation or artifact
service. The workflow has not been published or run on GitHub. M6 also leaves
the owner's license choice pending; no LICENSE file was selected automatically.
The checklist remains open for these items, and work stops for milestone review.

## M6 publication and hosted CI — 2026-10-27

Published the reviewed M6 additions on `main` at
`dfb7fbcc5d1d2cc8a9471abb9f2bc27585df2914`. Read back the branch ref and verified
the 16 published file blob hashes against the uploaded content.

[GitHub Actions run 40442477414](https://github.com/Sean184344/power-manager/actions/runs/40442477414)
completed successfully. Tool installation, version capture, `make check`, SVG
reproduction/comparison and artifact upload all passed. The hosted runner used
Icarus 12.0, Yosys 0.33, Python 3.12.3 and Make 4.3. All simulation configurations
and negative controls passed; formal completed eight inductive proofs and 52
cover witnesses; synthesis produced 116 / 186 / 577 generic cells with zero latches.

`reports/m6/ci.json` records the tested commit and run identity;
`reports/m6/ci-summary.log` retains tool versions and PASS lines from the hosted
job log. The Actions run contains complete logs and its verification artifact.
The checklist now marks publication and hosted CI verified. The owner's license
choice is the sole remaining M6 item; no license was selected automatically.
