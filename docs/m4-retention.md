# M4 power-gating and retention contract

`power_manager_retention.sv` is a separate power-gating configuration. It reuses
the M3 synchronizers and wake bridge; the synchronous core and M3 clock-sleep
wrapper remain available. Its timeout parameter must be at least 4 AON cycles
and must cover crossing and acknowledgement delays (default 64).

Shutdown: RUN -> DRAIN -> SAVE -> SAVE_CLEAR -> ISOLATE -> STOP_CLOCK ->
POWER_DOWN -> OFF. Startup: POWER_ON -> CLOCK_ON -> RESET_RELEASE -> RESTORE ->
RESTORE_CLEAR -> REOPEN -> RUN. Cold boot skips restore. Debug encodings are
OFF_WAIT=0, OFF=1, POWER_ON=2, CLOCK_ON=3, RESET_RELEASE=4, RESTORE=5,
RESTORE_CLEAR=6, REOPEN=7, RUN=8, DRAIN=9, SAVE=10, SAVE_CLEAR=11, ISOLATE=12,
STOP_CLOCK=13, POWER_DOWN=14, FAULT=15.

## Handshakes and ordering

- Sleep is an AON-synchronous level, consumed once per assertion. Wake suppresses
  simultaneous sleep in RUN. A sampled wake after entry is retained; shutdown
  completes through OFF, then restarts. M4 deliberately completes save and power
  sequencing rather than aborting an in-progress retention transaction.
- Wake uses M3's source pulse/ready handshake and an always-running source clock.
  Global reset cancels outstanding events and clears the retention snapshot.
- The synchronized block request stops domain admission. A domain acknowledgement
  proves both blocking and idle before SAVE. Work arriving during synchronization
  must also drain. Data remains local to the modeled domain/retention endpoint.
- Save and restore are held requests synchronized into the domain. The endpoint
  raises an acknowledgement only after copying the data, holds it until the
  request falls, then clears it. Both return-to-zero phases are bounded and
  complete before proceeding. Save must finish before isolation/reset/power loss;
  restore must finish before isolation is released or work is admitted.
- ISOLATE lasts a full AON cycle. Domain reset is then asserted and the clock
  requested off. For M4, a low clock-ready acknowledgement after disable must
  mean the clock has stopped. Only then may the power-enable request fall.
- Power-good must follow the requested supply state and remain high while the
  domain is powered. Startup waits for power-good before requesting the clock,
  then for clock-ready before releasing local reset. Reset deasserts after two
  domain clock edges. The controller also waits for the local reset/idle response.
- REOPEN releases isolation and then waits for the synchronized admission control
  and quiesce acknowledgement to return to their RUN values. `active_o` indicates
  RUN; actual admission is governed by `domain_block_work_o`.

Power-good and clock-ready are synchronized AON levels. Raw power-good also
asserts domain reset and isolation on supply loss, and suppresses active status
while the synchronized fault indication propagates; it must be a qualified, glitch-free signal
in a physical implementation. No production RTL generates or gates a clock.

## Reset and faults

Global reset isolates outputs, requests clock and power off, and clears the saved
snapshot. OFF_WAIT gives the reset-zeroed acknowledgement synchronizers time to
sample actual inputs, then waits for both off acknowledgements before cold boot.

All bounded waits give a successful acknowledgement priority on the deadline.
A missing acknowledgement, unexpected power/clock loss, or illegal state enters
sticky FAULT. FAULT keeps isolation and reset asserted, requests power on and
clock off, and requires global reset. Faults can cancel outstanding work; they
never claim a successful retained-state recovery. Global reset intentionally
discards retained state and starts from the endpoint's cold value.

## Modeling boundary

The retention endpoint and power supply are behavioral testbench models. The
retention bank remains powered while volatile state is destroyed by power loss.
Output isolation clamps to zero even when the raw domain output is unknown.
This verifies sequencing and data preservation under explicit digital model
contracts. It is not UPF-aware simulation, a retention/isolation cell model,
analog supply validation, physical CDC signoff, or a power-saving measurement.

## Verification plan and replay

The AON period is 10 ns. The matrix sweeps source/domain periods of 6, 14 and
26 ns, phases of 1 and 4 ns, and response delays of 1 and 5 source cycles.
The clock model starts disabled for M4; M3 retains its clock-on reset default.
Every configuration must pass these 15 directed scenarios:

| Group | Required scenarios |
|---|---|
| Retention | Normal busy drain/save/power cycle; three successive updated snapshots; delayed save and restore |
| Wake races | Wake delivered in SAVE; wake delivered in POWER_DOWN |
| Faults | Missing power-good; missing clock-ready; missing save ack; stuck save ack; missing restore ack; stuck restore ack; missing power-off acknowledgement; unexpected supply loss |
| Reset | Reset while powered off; reset during restore |

Delayed save/restore use 8 and 9 domain cycles. Wake races extend the relevant
response to 12 cycles and verify the actual AON wake-delivery phase. Missing/stuck
ack tests verify no premature timeout, then fault on the configured 64th wait
edge. Successful responses are exercised across clock ratios; an exhaustive
deadline-success sweep for every M4 state is outside this scenario plan.

The retention scoreboard derives expected data from accepted writes and their
completion timing. It never reads the saved bank. It checks completed data,
save/restore responses, exposed output data, output clamping, and safe power/clock
ordering. Global reset explicitly discards the expected architectural value;
ordinary domain reset during power cycling does not. A negative run flips one
bit during restore and must fail with `retention scoreboard: restored data
mismatch`; an unrelated failure or a successful simulation is rejected.

```sh
make test
make m4
python3 scripts/run_m4.py --half-periods 13 --phases 4 --delays 5 --waves
```

Fresh compile logs, simulation logs, scenario CSVs, corruption diagnostics and
replay commands are under `build/m4/`. `--waves` adds normal-run VCDs; the
corruption run always creates a VCD. Reviewed evidence is archived in
`reports/m4-coverage.json` and `reports/m4-corrupt.log` and survives `make clean`.
This is a finite directed matrix, with no claim of exhaustive fault coverage.
