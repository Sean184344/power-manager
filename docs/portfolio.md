# Portfolio notes and release review

## Evidence-based resume bullets

- Designed SystemVerilog clock-sleep and modeled power-gating controllers with
  explicit wake priority, request rearming, bounded waits and fault handling.
- Built independent transaction and retention scoreboards; verified 12 seeded
  race configurations, 24 CDC configurations and 12 retention configurations,
  with intentional lost-wake, early-clock-stop and restore-corruption detection.
- Proved synchronous-core safety and conditional progress with eight Yosys
  induction runs across four timeout settings; generated 52 reachability
  witnesses and synthesized three controller configurations with zero latches.

Use the [verification matrix](verification-matrix.md) to substantiate these
claims. Do not claim silicon validation, UVM, UPF-aware simulation, physical CDC
signoff, timing closure, or measured power savings.

## Review record

The M6 review checked core state transitions against the specification, model
boundaries against the M3/M4 contracts, and proof/synthesis claims against the M5
reports. It adds explanatory artifacts and a CI workflow; controller RTL is
unchanged. This review and the regression are not a new exhaustive code audit.

The M5 snapshot was published to
[Sean184344/power-manager](https://github.com/Sean184344/power-manager) at
[`d136475`](https://github.com/Sean184344/power-manager/commit/d136475800f6b3f1c1e3f6cf4831973db5143e26).
The M6 additions include the documentation and CI workflow described here.
See the milestone checklist for publication and hosted CI evidence. The local workspace has no
usable Git metadata; the M5 publication used the GitHub API.

## License status

No license has been selected and no LICENSE file has been added. The repository
owner's license choice remains an explicit M6 checklist item. Public availability
should not be described as a grant of an open-source license.

## CI

The published workflow installs Icarus Verilog and Yosys on Ubuntu 24.04, records
tool versions, and runs `make check` from a clean checkout. It retains build logs,
coverage, waveforms and generated formal/synthesis artifacts even on failure.
Its package versions may differ from the archived local Icarus 12.0 / Yosys 0.33
results. A successful local run does not establish a successful hosted Actions run.
The workflow uses the documented [checkout v4](https://github.com/actions/checkout/blob/v4/README.md)
and [artifact upload v4](https://github.com/actions/upload-artifact/blob/v4/README.md)
interfaces. It also reproduces the annotated diagrams and compares them with
the reviewed SVGs.

The first hosted run passed on M6 commit `dfb7fbc`:
[run 40442477414](https://github.com/Sean184344/power-manager/actions/runs/40442477414).
Tool versions, commit identity and the result are recorded in
[`reports/m6/ci.json`](../reports/m6/ci.json). All verification, diagram reproduction
and evidence upload steps succeeded. The license decision remains pending.
