# ADR-0007: Four systemd services

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 21, 28 (Phase 12), 44

## Context

The rover must reach READY after power-on with no SSH session. Different parts of the
stack have different failure consequences: a backend crash should not stop the rover, a
recorder crash should not stop the rover, and a control-graph crash must stop it safely.

## Decision

Four units: `dyx-platform` (network, DDS agent, devices, permissions) →
`dyx-ros` (the whole control graph) → `dyx-backend` and `dyx-recorder` in parallel.

## Alternatives considered

### Option A — One service for everything

**Pros**
- Trivial startup ordering
- One thing to enable, one thing to check

**Cons**
- A backend crash restarts the control graph — unacceptable
- Recorder cannot outlive a backend failure, losing evidence exactly when it matters
- No way to restart one concern without disturbing the others

### Option B — One service per ROS node (11+ units)

**Pros**
- Maximum isolation; a single node can be restarted alone
- Precise resource and restart policy per node

**Cons**
- Startup ordering across eleven units is fragile and hard to reason about
- DDS discovery churn on every individual restart
- Restarting one control node mid-mission produces a partially-initialised graph, which
  is more dangerous than a clean stop
- Operationally worse: eleven things to check instead of four

### Option C — Four services by failure domain *(chosen)*

**Pros**
- Boundaries match consequences: platform, control, UI, evidence
- Recorder keeps recording through a backend failure
- Control survives backend and recorder failures
- Four units is a number a person can hold in their head at 6 a.m. on a site

**Cons**
- The ROS graph remains a single failure domain — one node crash takes the whole
  control graph down
- Coarser than per-node control when debugging

## Why we chose what we chose

The ROS graph being one failure domain is a feature, not a compromise. A control graph
with a missing node is in an undefined state; stopping it cleanly and failing to zero is
the correct behavior. Partial recovery of a control system is how rovers do
unpredictable things.

## Consequences

**We accept:** any control node crash stops the whole graph.

**We must therefore:**
- Ensure graph death fails to zero at PX4, not just in ROS. PX4 must stop on loss of
  offboard heartbeat — verified on hardware, not assumed
- Set `Restart=` policy deliberately per unit. Auto-restarting the control graph while
  the rover is on a line is a decision, not a default
- Verify the Phase 12 matrix explicitly: restart, power loss, backend crash, node crash,
  PX4 disconnect, network reconnect, storage failure
- Keep the recorder's failure independent — including its disk filling up

**Revisit if:** a specific node proves worth isolating, e.g. `dyx_rtk`, whose failure is
genuinely non-fatal and whose restart is genuinely safe mid-mission.
