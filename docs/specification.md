# v0.1 specification

This specification describes the synchronous core. The M3 wrapper adds clock
domain crossings and local reset release; its interface and timing contract are
in `docs/m3-cdc.md`. Core event priorities remain unchanged.
M4's separate power-gating sequencer has its own retention and fault contract
in `docs/m4-retention.md`; it does not replace the clock-sleep core.

## Timing contract

All inputs except asynchronous active-low reset are synchronous to `clk_i`, an always-on clock. Drive them away from its rising edge in simulation. Hardware must synchronize reset deassertion externally. Wake must be present at a sampling edge; sub-cycle or asynchronous pulses are unsupported until the CDC milestone.

`TIMEOUT_CYCLES` must be at least 1. On entering DRAIN or START, its elapsed count is zero. If no successful event occurs, the Nth rising edge spent in that state times out for N = TIMEOUT_CYCLES. A successful acknowledgement on that edge wins over the timeout.

Reset immediately selects START, requests the clock on, blocks work and asserts isolation, and clears sticky flags. On deassertion, the controller still waits for clock-ready before RUN.

## Interface

| Signal | Meaning / environment obligation |
|---|---|
| sleep_req_i | Level request. Once an entry attempt is accepted, must be sampled low before another attempt can be accepted. An abort also consumes the request. A request blocked by wake in RUN is not yet accepted. |
| wake_i | Synchronous wake event/level. In RUN suppresses entry. Outside RUN captured until normal execution resumes. Wake during global reset is discarded. |
| idle_i | Managed domain guarantees no work remains and no new work is accepted while block_work_o is high. Without this contract shutdown safety cannot be guaranteed. |
| clock_ready_i | START acknowledgement: requested clock is usable. Must reflect current readiness, not an old pulse. Clock failure after START is outside v0.1 scope. |
| block_work_o | Domain must reject new work when high but finish accepted work while clock is enabled. |
| isolate_o | Logical request to clamp managed-domain outputs. Actual clamps are not in v0.1. |
| clk_en_o | Logical enable request to an external clock controller; not a generated clock. |
| active_o / sleeping_o | RUN / SLEEP status. SLEEP means enable requested low, not measured physical clock stoppage. |
| fault_o | Sticky timeout or illegal-state fault; cleared only by reset. |
| state_o | Debug encoding: RUN=0, DRAIN=1, ISOLATE=2, SLEEP=3, START=4, RELEASE=5, FAULT=6. |

## Arbitration

1. Global reset overrides all events.
2. RUN: wake suppresses sleep entry.
3. DRAIN: wake > idle acknowledgement > timeout. Wake returns directly to RUN; idle starts isolation; timeout aborts to RUN and sets fault.
4. ISOLATE: wake selects RELEASE; otherwise select SLEEP.
5. SLEEP: wake selects START.
6. START: clock-ready > timeout. Ready selects RELEASE; timeout selects FAULT.
7. RELEASE: next cycle RUN. Work remains blocked and isolation stays high for the entire RELEASE cycle.
8. FAULT: reset is the only exit. New sleep/wake requests cannot override it.

## Safety and recovery

- Clock-disable request always implies isolation and work blocking.
- Work admission implies RUN, clock-enable request, and no isolation.
- ISOLATE precedes SLEEP; START and RELEASE precede RUN after sleeping.
- A drain timeout is recoverable: clock stayed on and the domain remains powered, so normal work can resume, with fault recorded.
- A clock-start timeout is not recoverable without reset: the clock is not proven usable, so the block stays isolated.
- Fault records status; a previous drain fault does not prevent a later rearmed sleep attempt.
- Liveness requires reset deassertion and a timely clock-ready response; waking from sleep additionally requires a sampled wake.

## Known limitations

Outputs are combinational state decodes. RTL simulation does not establish glitch-free controls or their physical implementation. No real power loss, retention, metastability, clock-stop acknowledgement, analog ramp, or isolation acknowledgement is modeled. The baseline drives busy work and clock readiness directly. M2 derives idle from a managed workload and readiness from a seeded behavioral clock-controller model. Remaining extensions are tracked tasks, not validated features.

## M2 workload verification contract

`tb/models/managed_workload.sv` is a behavioral single-slot worker on the
always-on clock, using `clk_en_o` as a progress enable rather than generating
a clock. A transaction is accepted at a rising edge when request valid and
ready are both high. Ready requires reset released, clock enabled, work
unblocked and an empty slot. Acceptance uses controls before the edge, so a
transaction may be accepted on the RUN-to-DRAIN edge. There is no same-edge
completion/replacement when the slot was occupied before the edge.

Each request supplies an ID and a positive latency L. Completion reports that
ID after L subsequent enabled rising edges. Work continues while admission is
blocked, and idle reflects an empty slot. Completion is a one-cycle pulse;
accepted/completed counters are per reset epoch. Global reset cancels pending
work without completion and clears those counters.

The independent scoreboard observes public interfaces, predicts admission and
completion timing, checks IDs, idle and counts, and rejects isolation or clock
shutdown with outstanding work. It samples handshakes before sequential updates
and checks responses afterward. Across resets, accepted transactions must equal
completed plus explicitly canceled transactions at test end. This model does
not yet cover multiple outstanding transactions, payload integrity, or separate
domain clocks. The M2 environment adds randomized clock-ready latency and permits
workload progress only when both readiness and the enable request are asserted.
See `docs/m2-verification.md` for delay semantics and the bounded coverage plan.
