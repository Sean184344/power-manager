# Verification matrix

`make test` runs simulation and simulation negative controls. `make check` also
runs formal and generic synthesis. Required bins are finite planned coverage;
their completion is not an exhaustive proof of every input sequence.

| Contract / risk | Verification and pass condition | Replay | Archived evidence |
|---|---|---|---|
| Core ordering, event priority, reset and fault behavior | 16 directed scenarios; 73 explicit checks and continuous safety monitors | `make test` | [Validation](../reports/validation.md), [waveforms](waveforms.md) |
| Accepted work survives sleep entry | Independent single-slot scoreboard; 6 accepted = 5 completed + 1 reset-canceled | `make test` | [Workload contract](specification.md#m2-workload-verification-contract) |
| Race phase, deadline and seeded delay coverage | 12 seed/timeout runs; every required bin hit per run; 1,278 accepted and completed | `make m2` | [Coverage JSON](../reports/m2-coverage.json), [scope](m2-verification.md) |
| Tests detect broken shutdown / wake behavior | Passing control; lost-wake and early-clock-stop mutations fail their expected assertions | `make mutations` | [Mutation manifest](../reports/m2_mutations/manifest.json) |
| CDC handshakes, stopped clock and reset races | 24 configurations, 18 required scenarios each; work and captured wakes accounted for including reset cancellation | `make m3` | [Coverage JSON](../reports/m3-coverage.json), [contracts](m3-cdc.md) |
| Power loss, retention integrity and fault responses | 12 configurations, 15 scenarios each; 180 completed transactions; corrupted restore detected | `make m4` | [Coverage JSON](../reports/m4-coverage.json), [negative control](../reports/m4-corrupt.log) |
| Core safety and conditional progress | Eight inductive proofs at timeouts 1/2/3/8; 52 cover witnesses; lost-wake negative control | `make formal` | [Formal report](../reports/m5/formal.json), [assumptions](m5-formal-synthesis.md) |
| Synthesizability and unintended latches | Hierarchy / structural checks for three tops; zero latches before and after mapping | `make synthesis` | [Synthesis report](../reports/m5/synthesis.json) |

Formal proofs cover the synchronous core after sampled reset. Progress assumes
timely idle and clock-ready acknowledgements; reset cancels pending obligations.
M3 and M4 have digital simulation evidence, not equivalent formal coverage.
Generic cell counts of 116 / 186 / 577 are tool-dependent synthesis results without
a technology library or timing constraints. They are not physical area, frequency
or measured power results.

Archived JSON files record the source hashes and commands for their individual
runs. Fresh results are written under `build/`; historical reports are not silently
overwritten. A hosted CI pass must be checked on GitHub after the workflow is published.
