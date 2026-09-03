# ADR-0006: No wheel odometry in the first production stack

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Section 15

## Context

Wheel encoders are the reflexive answer to "we need better low-speed velocity." The
rover operates on construction ground, loose soil, solar fields, gravel, mud, and
slopes — surfaces where a skid-steer platform slips constantly and its instantaneous
centre of rotation moves with the surface.

## Decision

The first production stack estimates from RTK GNSS + IMU + PX4 EKF only. Wheel encoders
are not a navigation dependency. They may be evaluated later as an optional velocity
aid, gated on field evidence.

## Alternatives considered

### Option A — RTK + IMU + EKF only *(chosen)*

**Pros**
- No slip-corrupted measurement entering the filter
- Fewer hardware failure modes: no encoders, wiring, or ICR calibration
- Matches the terrain the product actually targets
- Simpler bring-up, fewer parameters, less to get wrong

**Cons**
- No independent velocity source during GNSS outage or float
- Low-speed velocity estimate rests on IMU integration and GNSS
- No direct slip detection

### Option B — Wheel odometry fused as a velocity aid

**Pros**
- Velocity through short GNSS dropouts
- Better low-speed resolution on good surfaces
- Slip becomes observable by comparing wheel and GNSS velocity

**Cons**
- On loose soil a skid-steer's wheel odometry is not merely noisy, it is *biased* —
  systematically wrong in the direction of travel during a turn
- A confidently wrong velocity source degrades an EKF more than no source at all
- Requires ICR calibration that varies with surface, and there is no surface sensor
- Hardware, wiring, and a new failure mode on a machine that goes into mud

### Option C — Encoders for diagnostics only, not fused

**Pros**
- Slip observability with no estimator risk
- Useful for motor health and stall detection

**Cons**
- Hardware cost with no navigation benefit
- Tempting to fuse later without re-validating

## Why we chose what we chose

The asymmetry decides it: bad velocity data is worse than absent velocity data. On the
terrain this product targets, wheel odometry's error is correlated with exactly the
manoeuvres where accuracy matters — turns and slopes — which is the worst possible error
profile for a filter that assumes roughly independent noise.

If GNSS outage during marking becomes a real observed problem, the answer is more likely
better RTK availability than a slip-corrupted velocity source.

## Consequences

**We accept:** no independent velocity source; RTK availability becomes critical.

**We must therefore:**
- Treat RTK degradation as a first-class control input. `dyx_motion_control` must gate
  on fix quality, and mission behavior on losing FIXED must be defined — not discovered
- Make RTK status structured, recorded, and visible to the operator (Section 16)
- Not let this decision quietly reverse. If encoders are added later they enter as an
  *optional* aid, behind a field-evidence gate, never as a required navigation source

**Revisit if:** field data shows GNSS-only velocity is the limiting factor in the error
budget — and only with paired data showing wheel odometry would actually have helped on
that surface.
