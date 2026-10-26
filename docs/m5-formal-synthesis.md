# M5 formal and synthesis scope

Formal proofs target the single-clock `power_manager.sv` core, using
`formal/power_manager_formal.sv`. Multi-clock CDC and retention configurations
retain their M3/M4 digital simulation evidence; this milestone does not claim a
formal proof of metastability, asynchronous clock interactions, or retention data.
All three production configurations are included in generic Yosys synthesis.

## Formal assumptions and properties

The formal model advances one AON sampling edge per step. Reset is asserted for
the first sample; later reset and all synchronous inputs are otherwise arbitrary.
Yosys `async2sync` converts asynchronous reset flops to a sampled reset model.
This is a two-state digital proof, not a proof of analog reset recovery/removal
timing or sub-cycle pulses. A reset cancels a pending progress obligation.

The safety configuration (`FAIR=0`) assumes no acknowledgement deadlines. It
checks legal states and output decoding, isolated/blocked clock shutdown, safe
admission, sticky fault, FAULT lockout, isolation before sleep, wake arbitration,
ready priority, RELEASE sequencing, sleep-request rearming, and bounded residence
in DRAIN/START. A `FORMAL`-only output exposes the rearm latch to connect observed
request history to implementation state. That connection is an asserted invariant,
not an assumption. The output is absent from normal simulation and synthesis.
Without environment cooperation, a bounded wait is allowed to terminate by the
specified abort or fault rather than successful sleep/wake.

The progress configuration (`FAIR=1`) additionally assumes idle is asserted by
the final DRAIN edge and clock-ready by the final START edge. Under those
assumptions the core never faults, and a sampled wake in SLEEP reaches RUN within
TIMEOUT+2 subsequent sampling steps, unless reset cancels the request. There is
no assumption that wake eventually arrives in SLEEP, and no unconditional claim
that the system must leave sleep without one.

Properties are checked with temporal induction, including both base and induction
steps. Timeout values 1, 2, 3 and 8 are separate proof instances, not a proof for
every possible integer parameter. Cover witnesses demonstrate reachability of
each of the seven states, a sleep/wake round trip, drain timeout returning to RUN,
ready on the START deadline, wake on the DRAIN deadline, and reset recovery after
fault. Covers use the unconstrained safety environment so fault states remain
reachable. Counterexample-to-unreachability SAT queries provide concrete traces.
An additional round-trip witness per timeout uses the progress assumptions,
showing that those assumptions permit actual sleep/wake execution.

The installed Yosys built-in SAT engine is used directly; SymbiYosys and external
SMT solvers are not required. No unknown cells are ignored and no initial register
values are forced beyond the harness initialization and actual reset assumption.

## Synthesis, constraints and interpretation

Yosys 0.33 synthesizes the default configuration of each top independently, using
generic gate mapping. The flow checks hierarchy and structural consistency,
rejects inferred latches before mapping, flattens the design, and rejects latches
and structural errors after mapping. It writes cell-type statistics and netlists.

| Top | Timeout | Generic cells | Inferred latches |
|---|---:|---:|---:|
| `power_manager` | 8 | 116 | 0 |
| `power_manager_cdc` | 64 | 186 | 0 |
| `power_manager_retention` | 64 | 577 | 0 |

Constraint status is deliberately explicit:

- No Liberty library, PDK, floorplan, load, input/output delay, voltage corner or
  physical timing constraints are applied. The generic ABC mapping is not a
  timing-closure result. No cell area, clock frequency, power, or physical PPA is
  claimed from these cell counts.
- The simulation reference has a 10 ns AON period and independently swept source
  clocks, including 26 ns. These are verification stimulus settings, not synthesis
  timing constraints. Each wrapper exposes separate AON, domain and wake clocks.
- A physical implementation needs an explicit technology, clock definitions,
  synchronizer-aware CDC timing exceptions, reset constraints, and real clock,
  isolation, power and retention cells. Those constraints cannot be validated by
  this generic flow. `ASYNC_REG` marks structure but is not placement signoff.
- The optional OpenROAD study is deferred because no PDK/library is selected.

The two wrapper counts include control logic and synchronizers, not the behavioral
workload, power supply, saved data bank, or clock-controller models. Synthesis
does not turn the testbench into a physically implemented power-domain system.

## Replay and evidence

```sh
make formal      # proofs, covers and formal negative control
make synthesis   # all three production tops
make m5          # both M5 flows
make test        # existing simulation regressions
make check       # simulations plus all M5 checks
```

`YOSYS` can override the executable. Only Yosys, its bundled ABC, and Python's
standard library are required for M5. Generated Yosys scripts and complete logs
are under `build/formal/` and `build/synthesis/`. Formal covers and the lost-wake
negative control produce VCD traces. The negative control edits a temporary RTL
copy only and must produce an assertion counterexample, not merely a tool error.

Reviewed summaries, source hashes and representative traces are archived under
`reports/m5/`. Archived log markers distinguish actual induction success from a
bounded run or a failed induction attempt. Full artifacts can be regenerated with
`make m5` after `make clean`.
