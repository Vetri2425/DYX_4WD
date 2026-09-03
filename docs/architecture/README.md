# Architecture Documentation — DYX 4WD

## What lives here

| File | Purpose | Status |
|---|---|---|
| `DYX_4WD_Production_Stack_Architecture_V1.md` | The specification. 57 sections. | **FROZEN** |
| `STACK.md` | Layer-by-layer stack rationale and alternatives | Living |
| `adr/` | Architecture Decision Records — one decision each | Living |
| `proposals/` | Proposed changes to the frozen V1 document | — |

The V1 document says **what** the system is. The ADRs say **why**, and what was
rejected. When they conflict, V1 wins and the ADR is wrong — open a proposal.

## Why ADRs

Three AI agents and one engineer work in this repository. An agent reading
`dyx_rpp/README.md` six months from now needs to know not just what the module does,
but which alternatives were considered and why they lost. Without that, every agent
re-litigates settled decisions, or worse, quietly reverses one.

An ADR is immutable once accepted. You do not edit an accepted ADR to change your
mind — you write a new one that supersedes it. The record of having been wrong is
part of the value.

## Status values

| Status | Meaning |
|---|---|
| `PROPOSED` | Written, not decided. **Blocks work that depends on it.** |
| `ACCEPTED` | Decided. Implement against it. |
| `SUPERSEDED` | Replaced. Header names the replacement. |
| `DEPRECATED` | No longer applies, nothing replaced it. |

## Index

### Strategy

- [ADR-0001](adr/0001-clean-rewrite.md) — Clean rewrite, not incremental refactor — `ACCEPTED`
- [ADR-0002](adr/0002-cpp-control-python-backend.md) — C++ control graph, Python confined to backend — `ACCEPTED`

### PX4 interface and control ownership

- [ADR-0003](adr/0003-uxrce-dds-not-mavros.md) — Direct uXRCE-DDS, remove MAVROS — `ACCEPTED`
- [ADR-0004](adr/0004-rpp-owns-rotational-intent.md) — RPP owns rotational intent — `ACCEPTED` (open question)
- [ADR-0005](adr/0005-px4-sole-estimator.md) — PX4 EKF is the only estimator — `ACCEPTED`
- [ADR-0006](adr/0006-no-wheel-odometry.md) — No wheel odometry in the first stack — `ACCEPTED`

### Process and boundaries

- [ADR-0007](adr/0007-four-systemd-services.md) — Four systemd services — `ACCEPTED`
- [ADR-0008](adr/0008-single-ros-backend-boundary.md) — One ROS↔backend boundary — `ACCEPTED`
- [ADR-0009](adr/0009-runtime-parameter-classes.md) — Live parameter tuning with classes — `ACCEPTED`

### Deployment and evidence

- [ADR-0010](adr/0010-release-artifact-rollback.md) — Release artifacts and rollback — `ACCEPTED`
- [ADR-0011](adr/0011-recorder-provenance.md) — Recorder as production component — `ACCEPTED`
- [ADR-0012](adr/0012-jetson-as-access-point.md) — Jetson as access point, no router — `ACCEPTED`

### Open — these block milestones

- [ADR-0013](adr/0013-compute-platform.md) — Jetson vs Radxa — **`PROPOSED`** — blocks Milestone 3
- [ADR-0014](adr/0014-px4-link-transport.md) — Ethernet vs serial DDS — **`PROPOSED`** — blocks Milestone 4
- [ADR-0015](adr/0015-control-point-definition.md) — Nozzle as control point — **`PROPOSED`** — blocks accuracy spec

## Writing a new ADR

Copy `adr/0000-template.md`. Number sequentially. Add to the index above. Never
renumber. Never delete.

Agents may draft an ADR. Only a human moves one to `ACCEPTED`.
