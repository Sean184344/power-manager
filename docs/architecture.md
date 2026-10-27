# Architecture

Three configurations share the sequencing rules but have different contracts.
The synchronous core supports clock sleep; the CDC wrapper adds crossings; the
retention controller is a separate sequencer for modeled power gating.

```mermaid
flowchart LR
    inputs["Synchronous sleep / wake"] --> core["power_manager<br/>always-on FSM"]
    core -->|block_work| worker["Managed workload"]
    worker -->|idle| core
    core -->|clk_en request| clock["Clock controller"]
    clock -->|clock_ready| core
    core -->|isolate request| boundary["Domain output boundary"]
    worker --> boundary
    worker -. public transactions .-> scoreboard["Independent scoreboard"]
```

In M2 the worker uses an enable on the always-on clock. M3 uses a separate,
stoppable managed clock. `power_manager_cdc` adds synchronized level handshakes,
wake capture and local reset release around the core. Its admission path blocks
new work while accepted work drains, then returns a quiesce acknowledgement.
Handshake cleanup prevents a stale acknowledgement from satisfying a new request.
See [CDC contracts](m3-cdc.md) for pulse spacing, reset cancellation and latency.

```mermaid
flowchart LR
    wake["Wake source clock domain"] -->|captured wake handshake| aon["Always-on sequencer"]
    aon <-->|synchronized requests / acknowledgements| managed["Managed clock domain<br/>work / save / restore"]
    aon -->|clock request| clock["Clock controller"]
    clock -->|ready| aon
    aon -->|power enable| supply["Behavioral supply"]
    supply -->|power good| aon
    aon -->|isolation / local reset| managed
    managed <-->|retained state| bank["Behavioral retained bank"]
```

The second diagram describes M4's separate `power_manager_retention` configuration.
It saves state before isolation and power removal, then restores it before work
admission. The retained bank survives an ordinary power cycle; global reset
discards its snapshot. The independent retention scoreboard predicts data from
accepted writes. See [retention contracts](m4-retention.md) for the full state
sequence, failure handling and behavioral model boundaries.

## Synchronous core FSM

```mermaid
stateDiagram-v2
    [*] --> START: reset
    START --> RELEASE: clock ready
    START --> FAULT: timeout
    RELEASE --> RUN: one guard cycle
    RUN --> DRAIN: armed sleep request and no wake
    DRAIN --> RUN: wake or drain timeout
    DRAIN --> ISOLATE: idle and no wake
    ISOLATE --> SLEEP: no wake
    ISOLATE --> RELEASE: wake
    SLEEP --> START: wake
    FAULT --> START: reset
```

Global reset selects START from any state. RUN admits work; DRAIN blocks new work
while the clock stays requested on. ISOLATE clamps outputs for a full cycle before
SLEEP requests clock shutdown. START waits for readiness and RELEASE holds
isolation for one extra cycle before RUN. A drain timeout returns to RUN with a
sticky fault; a start timeout locks in FAULT until reset. Wake beats idle and
timeout in DRAIN, and readiness beats timeout in START.

The physical clock gate, isolation cells, power switch and retention cells are
outside this repository's implementation. Logical requests and behavioral models
do not establish glitch freedom, analog timing, physical CDC safety or power savings.

Next: [annotated waveforms](waveforms.md), [verification matrix](verification-matrix.md).
