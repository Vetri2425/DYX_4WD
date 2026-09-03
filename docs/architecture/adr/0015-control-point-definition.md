# ADR-0015: The control point is the nozzle, not the antenna

- **Status:** **PROPOSED**
- **Date:** 2026-09-03
- **Spec:** not in V1 — a gap
- **Blocks:** the performance contract, and the definition of cross-track error in RPP.

## Context

The rover is judged on where paint lands. But the estimator reports the position of the
GNSS antenna phase centre, and the vehicle rotates about an instantaneous centre of
rotation that, on a skid-steer, moves with surface and slip.

These are three different points. Cross-track error measured at the antenna is not
cross-track error at the nozzle, and on uneven terrain the difference is not small:
an antenna 1.2 m up at 5° roll is displaced roughly 10 cm laterally. Nothing in V1
defines which point the controller is regulating. Section 24 mentions antenna offsets
once, as an `IDLE_ONLY` parameter — an accuracy-critical geometric fact filed as a
configuration detail.

## Proposal

Define the nozzle as the control point. RPP computes cross-track and along-track error
at the **nozzle position**, derived from the estimated antenna position via an explicit
chain of transforms. Every transform is a named, measured, version-controlled quantity,
not an implicit assumption inside a controller.

Required transforms:

```
antenna phase centre  →  body frame origin      (measured mechanically, cm accuracy)
body frame origin     →  nozzle                 (measured mechanically)
body frame origin     →  instantaneous centre   (surface-dependent, characterised)
```

## Alternatives considered

### Option A — Regulate at the antenna (implicit status quo)

**Pros**
- Simplest; the estimator's output is used directly
- No transform chain to maintain or measure

**Cons**
- Optimises the wrong point — the antenna can track perfectly while the paint is off
- Error grows with terrain roughness, exactly where the requirement is hardest
- Makes the accuracy spec untestable, because the spec is about paint

### Option B — Regulate at the nozzle *(proposed)*

**Pros**
- Optimises what the customer measures
- Makes lever-arm error explicit and therefore budgetable
- Gives the performance contract a well-defined measurement point

**Cons**
- Requires accurate mechanical measurement; a wrong offset is a systematic bias no
  software can remove
- Transform chain must be maintained as a first-class artifact
- Nozzle-referenced control interacts with ICR: on a skid-steer, rotating to correct the
  nozzle moves the nozzle in a way that depends on where the ICR currently is

### Option C — Regulate at the ICR

**Pros**
- Kinematically natural for the vehicle
- Cleanest control formulation

**Cons**
- The ICR moves with surface, load, and slip, and is not directly observable
- Optimises a point nobody cares about

## Why this matters more than it looks

Without this decision, "±2 cm cross-track" is not a testable claim, because the sentence
does not say what is 2 cm from what. Two engineers can both believe the rover meets spec
and be measuring different things.

## Consequences if accepted

**We must:**
- Write `docs/validation/control_point_definition.md` with the transform chain, how each
  quantity is measured, and its uncertainty
- Measure and record antenna and nozzle offsets per rover; treat them as calibration
  data, not configuration
- Characterise ICR behavior across the target surfaces — at minimum, know how much it
  moves
- Express the performance contract at the nozzle, with an error budget separating RTK
  error, heading error, lever arm, latency × speed, controller tracking, and mount
  compliance
- Have RPP compute tracking error at the nozzle, with the transform explicit and tested

**Revisit if:** field measurement shows the nozzle-to-antenna transform is stable enough
that the distinction is inside the noise floor. Unlikely on the target terrain, but it
should be measured rather than assumed.
