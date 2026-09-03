# ADR-0003: Direct uXRCE-DDS to PX4, remove MAVROS

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 1, 13, 28 (Phase 3)

## Context

`rover_ws` talks to PX4 through MAVROS. MAVROS translates ROS messages to MAVLink,
MAVLink to uORB. Each hop adds latency, adds a place for rate limiting, and constrains
the message set to what MAVLink defines.

The rover needs setpoints MAVLink does not express well: explicit yaw-rate intent at
zero forward speed (pivot), heading hold while creeping, and a clean mode distinction
between them. Expressing these through MAVLink offboard setpoints means overloading
fields and hoping PX4 interprets them as intended.

PX4 v1.14+ exposes uORB topics directly over uXRCE-DDS. That is the native path.

## Decision

`dyx_px4_gateway` communicates with PX4 over uXRCE-DDS using `px4_msgs`. MAVROS does not
appear anywhere in the production control plane.

## Alternatives considered

### Option A — Keep MAVROS

**Pros**
- Already works; the rover flies today on this path
- Mature, widely deployed, enormous body of troubleshooting material
- Transport-agnostic — same code over serial, UDP, telemetry radio
- Protocol stability: MAVLink messages rarely break between PX4 releases
- QGroundControl and the rest of the MAVLink ecosystem interoperate for free

**Cons**
- Two translation hops (ROS↔MAVLink↔uORB), each adding latency and jitter
- Message set is aircraft-shaped; rover-specific intent is awkward to express
- Stream rates are configured per-message and easy to get subtly wrong
- Effectively in maintenance mode; new PX4 features land on the DDS path first
- Debugging spans three representations of the same data

### Option B — Direct uXRCE-DDS *(chosen)*

**Pros**
- Native access to uORB topics; no semantic translation
- Lower and more predictable latency — matters directly for cm tracking
- `px4_msgs` are typed and generated from the firmware's own definitions
- Where PX4 rover support is actively developing
- One representation of the data end to end

**Cons**
- **Hard version lock.** `px4_msgs` must match the firmware's message definitions
  exactly. A mismatch deserializes silently wrong — no error, just bad numbers.
- The XRCE agent is another process to supervise and another failure mode
- Much less community troubleshooting material; problems are solved alone
- Message definitions change between PX4 releases more freely than MAVLink does
- Loses free MAVLink-ecosystem interoperability

### Option C — Both — DDS for control, MAVROS for telemetry/GCS

**Pros**
- Keeps QGroundControl working without extra effort
- Gradual migration path

**Cons**
- Two paths to PX4 means two opinions about vehicle state
- Doubles the surface area that must be understood and supervised
- Violates single-authority (Section 29) at the transport layer
- Rejected: dual control paths to the same autopilot is how you get a fight over arming

## Why we chose what we chose

The rover control modes we need are expressible natively in uORB and awkward in
MAVLink. Given that ADR-0004 makes explicit rotational intent the central design
decision, choosing a transport that struggles to express it would undermine the whole
architecture.

The version-lock cost is real but it is *manageable by discipline* — pin, document,
test — whereas MAVLink's expressiveness ceiling is not fixable at all.

## Consequences

**We accept:** firmware/message coupling, and a smaller community to draw on.

**We must therefore:**
- Write `docs/interfaces/px4_contract_v1.md` enumerating every uORB topic, every
  `px4_msgs` commit SHA, and every PX4 parameter that forms the contract. This document
  is what makes the version lock survivable.
- Record the `px4_msgs` SHA in every bag manifest — bags recorded against a different
  message set are not comparable, and the failure is silent.
- Treat PX4 firmware upgrades as contract changes requiring re-validation, not routine
  updates.
- Supervise the XRCE agent in `dyx-platform.service`, started before `dyx-ros.service`.
- Prove the path on hardware in Milestone 4 **before** porting RPP. If DDS control does
  not work as expected, that must be discovered before the controller is built on it.

**Revisit if:** the DDS path proves unreliable on the chosen transport (see ADR-0014) in
a way that cannot be resolved. MAVROS remains a functioning fallback until we delete it,
and we should not delete it from `rover_ws` until Milestone 4 passes on hardware.
