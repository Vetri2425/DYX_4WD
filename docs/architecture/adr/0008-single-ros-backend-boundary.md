# ADR-0008: One ROS↔backend boundary via dyx_system_gateway

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 4, 18, 23

## Context

A React Native GCS needs REST and Socket.IO. That is Python's territory. The control
plane is C++ ROS 2. Something has to connect them, and the shape of that connection
determines whether the backend can become a safety authority by accident.

## Decision

`dyx_system_gateway` is the only ROS↔backend boundary. The backend reaches ROS over
local IPC (Unix domain socket, or local gRPC if the API grows). No `rclpy` anywhere in
`backend/`. No backend code subscribes to a ROS topic.

## Alternatives considered

### Option A — Backend uses rclpy directly

**Pros**
- Simplest possible; no gateway to write
- Direct access to every topic and service
- One less process, one less schema

**Cons**
- FastAPI's lifecycle and a ROS executor in one process; both want the event loop
- Makes the backend a ROS participant, and therefore a de facto part of the control
  plane — the boundary that keeps it from being a safety authority disappears
- Python back in the control graph through the side door
- A backend crash now perturbs DDS discovery

### Option B — Backend speaks DDS directly, no rclpy

**Pros**
- No gateway process
- Language-independent

**Cons**
- Backend still joins the DDS graph, with the same authority ambiguity
- Message definitions duplicated in Python by hand
- Worse than Option A with no compensating benefit

### Option C — Dedicated C++ gateway *(chosen)*

**Pros**
- One place to validate and rate-limit every backend request
- Backend can crash, restart, or be replaced without touching the control graph
- The telemetry snapshot the GCS sees is defined once, deliberately
- Testable in isolation; the backend can be developed against a fake gateway

**Cons**
- Extra hop and extra process
- Schema exists twice: ROS messages and the IPC payload
- More code to write and keep in sync

## Why we chose what we chose

Section 23 is unconditional: the backend is never a safety authority, and a GCS stop is
a request. That property has to be structural, not a coding convention. If the backend
can publish to a control topic, then whether it *does* is a review question forever.
With the gateway, it cannot.

The schema duplication is a real cost, and the honest mitigation is code generation from
the ROS message definitions rather than hand-maintained parallel types.

## Consequences

**We accept:** an extra hop, an extra process, and duplicated schema.

**We must therefore:**
- Generate IPC types from `dyx_interfaces` rather than hand-writing them, or accept
  drift as inevitable
- Define the canonical telemetry snapshot once, versioned, in `docs/interfaces/`
- Keep the boundary local to the Jetson — this is IPC, not a network API
- Ensure gateway failure is safe: control continues, the GCS goes dark, and the operator
  can tell the difference between "rover stopped" and "I lost my view of the rover"

**Revisit if:** the IPC layer becomes a bottleneck for high-rate telemetry. The answer
then is a better transport, not removing the boundary.
