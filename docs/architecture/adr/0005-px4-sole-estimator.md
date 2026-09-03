# ADR-0005: PX4 EKF is the only estimator

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 14, 15

## Context

Something must fuse RTK GNSS, dual-antenna heading, and IMU into position and attitude.
PX4's EKF2 already does this, and PX4 needs the result regardless because its inner
loops run on it. The question is whether ROS should also estimate.

On uneven terrain the lever arm dominates: an antenna 1.2 m above the wheels at 5° roll
displaces the reported position by roughly 10 cm laterally. Compensating this requires
attitude and accurate antenna offsets — which is EKF2's job via `EKF2_GPS_POS_*`.

## Decision

PX4 EKF2 is the sole estimator. No ROS-side state estimation, no `robot_localization`,
no second filter. `dyx_px4_gateway` consumes PX4's state and republishes it as
`VehicleState`.

## Alternatives considered

### Option A — PX4 EKF only *(chosen)*

**Pros**
- One source of truth; controller and autopilot cannot disagree about where the rover is
- PX4 needs a good estimate anyway — a second filter is duplicated work
- Lever-arm and antenna-offset compensation already implemented and flight-proven
- Fewer moving parts, less to supervise, less to get out of sync

**Cons**
- Estimator tuning lives in PX4 parameters, **outside** the ROS parameter system, and
  therefore outside our live-tuning, validation, and audit architecture (Sections 30–36)
- Limited introspection — EKF2 innovations are harder to reason about than a filter we
  wrote
- Coupled to PX4 release cadence

### Option B — ROS-side EKF (`robot_localization`) alongside PX4

**Pros**
- Full visibility and control over fusion
- Could add sources PX4 does not support
- Tuning inside the ROS parameter system

**Cons**
- Two estimates of the same state that will diverge. When they disagree the rover has
  no principled way to decide which is right
- PX4 still runs its own EKF for inner loops, so this is a *third* opinion, not a
  replacement
- Substantially more code to validate for no requirement we currently have
- Directly violates single-authority (Section 29)

### Option C — Replace PX4's estimate by feeding external vision/odometry

**Pros**
- Single estimator, ours, fully controlled

**Cons**
- We would be reimplementing a mature, well-tested filter
- Latency of the ROS→PX4 path enters the estimation loop
- Failure modes become ours to discover in the field
- No requirement justifies it

## Why we chose what we chose

PX4 runs an EKF whether we like it or not, because its inner loops need one. Given
that, any ROS-side estimator is an *additional* opinion rather than a substitute — and
two estimators is worse than either alone.

## Consequences

**We accept:** a meaningful gap — estimator tuning happens outside the parameter
architecture we designed for exactly this kind of tuning.

**We must therefore:**
- Bring PX4 parameters into the audit system. Section 37 already requires snapshotting
  them at mission start and end; extend that to log changes with the same
  timestamp/old/new/source record as ROS parameters (Section 36)
- Enumerate estimator-relevant PX4 parameters in `px4_contract_v1.md`, especially
  `EKF2_GPS_POS_*`, GNSS heading noise, and the dual-antenna configuration
- Measure antenna offsets to centimetre accuracy — this is a mechanical task with direct
  accuracy consequences, and no amount of software fixes a wrong number here
- Publish estimator health (innovation ratios, fix type, heading validity) in
  `VehicleState` so `dyx_motion_control` can gate on estimate quality, not just on
  command validity

**Revisit if:** field evidence shows EKF2 cannot meet the accuracy budget with correct
offsets and tuning. That is an estimator-quality finding, and the response is to
investigate PX4 tuning first — not to add a second filter.
