# Project checklist

Update after each working session. Checked items require implementation or evidence; planned features must not appear as accomplished resume claims.

## M0 — Scope and contract
- [x] Choose single-domain power-manager race verification.
- [x] Define v0.1 clock-sleep scope and later power-gating extension.
- [x] Specify inputs, outputs, reset behavior, event priority, timeouts and assumptions.
- [x] Create a project tree and reproducible test command.

## M1 — First runnable RTL
- [x] Implement RUN/DRAIN/ISOLATE/SLEEP/START/RELEASE/FAULT.
- [x] Handle wake during entry and simultaneous wake/sleep.
- [x] Add request rearming and sticky fault status.
- [x] Write directed testbench with safety monitors and watchdog.
- [x] Compile and run directed regression; Icarus 12.0: 16 scenarios, 73 explicit checks passed (2026-10-26).
- [x] Revalidate baseline using system-installed HDL tools; `make test` rebuilt and passed without compiler warnings (2026-10-26; see `reports/validation.md`).

## M2 — Realistic DV environment
- [x] Build managed workload model with accepted/completed transaction counts; four integration scenarios and 33 checks pass (2026-10-26).
- [x] Build clock-controller model with randomized acknowledgement latency; 32 seeded sleep/wake trials pass, including late-ready fault lockout.
- [x] Add independent transaction scoreboard and protocol monitor for the single-slot workload; six accepted, five completed, one reset-canceled, zero outstanding. Three model corruptions detected (2026-10-26).
- [x] Cross wake arrival phase with busy/idle and deadline position; every planned reachable bin passes for each seed/timeout (see `docs/m2-verification.md`).
- [x] Add repeatable seeded random regressions and machine-readable coverage; seeds 1, 17 and 2026, CSV events and JSON coverage gate, deterministic replay checked.
- [x] Test TIMEOUT_CYCLES = 1, 2, 3 (non-power-of-two), and the unoverridden RTL default (8); all 12 runs pass.
- [x] Inject intentional lost-wake / early-clock-stop bugs and demonstrate detection; both fail their expected checks, with passing positive control and replay evidence in `reports/m2_mutations/`.
Exit: every planned race bin reached, no scoreboard loss, archived reproducible failures for mutations.

M2 exit met (2026-10-26): clean `make test` passes; all required bins reached in each of 12 seed/timeout runs; 1,278 accepted transactions completed with zero loss; two RTL mutations detected. Coverage scope and exclusions are defined in `docs/m2-verification.md`; archived hit counts are in `reports/m2-coverage.json`.

## M3 — CDC and reset races
- [x] Separate always-on and managed-domain clocks; a stopped managed clock and always-running wake source are exercised in `tb_m3.sv`.
- [x] Specify level handshake and pulse-capture contracts, reset cancellation and latency budgets in `docs/m3-cdc.md`.
- [x] Implement two-flop synchronizers, local reset release and full request/acknowledge cleanup in `power_manager_cdc.sv` and `cdc_primitives.sv`.
- [x] Test clock ratios, phase offsets, delayed acknowledgements, resets in every phase; all 24 configurations pass all 18 required scenarios, including reset in FAULT and pending wake cancellation.
Exit: documented CDC structure plus simulation evidence; do not claim metastability signoff from simulation.

M3 exit met: `make test` passes the baseline, M2 and M3 suites. The crossing and
reset contract is documented in `docs/m3-cdc.md`; archived scenario counts,
accounting totals, replay commands and source hashes are in
`reports/m3-coverage.json`. This is digital protocol verification, not physical
CDC/RDC or metastability signoff.

## M4 — Power gating and retention
- [x] Add power-enable / power-good handshake and domain reset sequencing; initial cold boot and complete power-cycle test passes.
- [x] Add behavioral power-loss and output-clamping models; the test observes unknown raw output while off and zero at the isolated boundary.
- [x] Add retention save/restore protocol and independent data-integrity checks; repeated snapshots survive modeled power loss and a corrupted restore is rejected.
- [x] Inject missing power-good, delayed save/restore and wake-during-poweroff cases; all 12 configurations pass all 15 scenarios, including missing/stuck acknowledgements, unexpected supply loss and reset during restore.
Exit: scoreboard proves intended retention behavior under modeled faults; identify difference from UPF-aware simulation.

M4 exit met: `make test` passes through M4. Each M4 configuration completes all
15 accepted writes; across 12 configurations, 180 writes complete with no loss.
Restore-corruption detection passes its expected-failure check. Contracts and
model limitations are in `docs/m4-retention.md`; replay evidence is archived in
`reports/m4-coverage.json` and `reports/m4-corrupt.log`. This is behavioral digital
verification, not UPF-aware or physical power-domain validation.

## M5 — Formal and synthesis
- [x] Add formal harness, safety properties and bounded progress properties; eight core proofs pass by temporal induction at timeout values 1, 2, 3 and 8.
- [x] Record environment assumptions and cover reachable scenarios; 48 safety-environment covers plus four progress-environment round trips, with a formal lost-wake negative control.
- [x] Run Yosys synthesis and record latch checks, cell statistics, and constraints; all three configurations pass structural checks with zero latches. See `docs/m5-formal-synthesis.md` for the absence of physical timing/library constraints.
- [ ] Optional OpenROAD controller implementation study: deferred; no PDK/library has been selected. Not required for the M5 exit.
Exit: reproducible reports; distinguish controller PPA from a physically implemented multi-power-domain system.

M5 exit met: `make check` passes all simulation suites, eight inductive proofs,
52 cover witnesses, the formal lost-wake negative control, and synthesis of all
three controllers. Archived summaries and logs are in `reports/m5/`. Generic
cell counts are 116 / 186 / 577 for the core / CDC / retention configurations,
with zero inferred latches. No physical area, timing or power result is claimed.

## M6 — Portfolio and GitHub
- [ ] Add architecture diagram, useful annotated waveforms and verification matrix.
- [ ] Review code, limitations, license choice and README.
- [ ] Add CI for regression and publish tested source/results to GitHub when requested.
- [ ] Write resume bullets based only on measured results.

Current session: completed M5 with explicit proof assumptions, inductive safety
and progress checks, reachability evidence, negative control and generic synthesis.
All earlier simulation suites still pass. Stopped at the M5 boundary for user
review; M6 remains pending. GitHub publication remains deferred.

Next step: user review of M5. M6 adds portfolio diagrams, annotated waveforms,
verification matrix, documentation/license review and CI. GitHub publication
still requires an explicit request; begin M6 only after continuation is requested.
