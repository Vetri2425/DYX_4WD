# ADR-0004: RPP owns rotational intent; PX4 owns inner loops

- **Status:** ACCEPTED — with open question OQ-1
- **Date:** 2026-09-03
- **Spec:** Sections 9, 10, 11, 14

## Context

In `rover_ws`, RPP publishes a North/East velocity vector. PX4 derives the desired
bearing from that vector and decides the turning response.

This has three consequences we can observe in the field. At low speed the vector's
direction is dominated by noise, so the derived heading is unstable exactly when
precision matters most. A pivot — rotate in place, zero translation — has no
representation at all in a velocity vector; the magnitude goes to zero and the direction
becomes undefined. And the correction strategy is split across two codebases: RPP
decides where to go, PX4 decides how to rotate, and no single place owns the tracking
behavior.

Debugging a cross-track oscillation therefore means reasoning about a controller whose
two halves live in different repositories with different tuning surfaces.

## Decision

RPP emits explicit intent in a single canonical `MotionSetpoint` message carrying a
control mode: `STOP`, `SPEED_HEADING`, `SPEED_RATE`, `PIVOT_RATE`. PX4 executes the
inner physical loops — speed, yaw-rate, differential allocation — and owns estimation.
PX4 no longer infers path-level rotational strategy.

## Alternatives considered

### Option A — Keep the velocity vector

**Pros**
- Already implemented and field-proven
- Simple message; PX4 handles the rest
- Fewer decisions in RPP means less RPP code

**Cons**
- No representation for pivot
- Direction is noise-dominated at low speed
- Tracking behavior is owned by nobody in particular
- Cannot express "hold this heading while creeping forward"

### Option B — Explicit mode switching between heading and yaw-rate *(chosen in V1)*

**Pros**
- Straight-line tracking can use PX4's tuned heading loop
- Pivot is unambiguous
- Each mode is individually simple

**Cons**
- **Mode transitions are an oscillation source.** Switching between an outer heading
  loop in PX4 and a rate loop in RPP without integrator handoff is the classic
  bumpless-transfer problem
- Two tuning surfaces (RPP gains and PX4 gains) that interact
- On rough ground, cross-track error jitters — and the switching boundary is exactly
  where it jitters

### Option C — Close the heading loop inside RPP, emit yaw-rate only

**Pros**
- One control loop, one tuning surface, no handoff during marking
- No mode-transition transient at all
- All tracking behavior is in one testable C++ module
- Directly serves the sub-degree stability requirement

**Cons**
- Discards PX4's already-tuned heading controller
- More logic in RPP to write and validate
- Requires RPP to have good heading feedback at its own rate

## Why we chose what we chose

The decision to move rotational authority out of PX4 is settled and not in question —
Option A cannot express pivot, and that alone disqualifies it.

The choice **between B and C is not settled.** V1 specifies B. The concern with B is
specific: mode switching during line marking is a plausible source of the sub-degree
oscillation we are trying to eliminate, and it is difficult to diagnose after the fact
because the symptom appears in tracking data while the cause is in mode history.

Recorded as **OQ-1** rather than silently resolved.

## Consequences

**We accept:** more responsibility in RPP, and PX4 rover parameters becoming part of
our tuning surface rather than a black box.

**We must therefore:**
- Define every mode transition explicitly: entry condition, exit condition, hysteresis,
  and what happens to controller state across the boundary
- Log the active mode in every `MotionSetpoint` and record it in the bag, so mode
  history is available when analysing an oscillation
- Verify in Milestone 4 that PX4 v1.17 actually accepts a heading setpoint for a
  differential rover. If it does not, `SPEED_HEADING` is not implementable and Option C
  becomes the only path — this is a hardware question, not a design preference
- Not freeze `MotionSetpoint` until Milestone 4 answers this

**Revisit if:** field data shows tracking transients correlated with mode changes.

## Open questions

**OQ-1 — Should `SPEED_HEADING` be used during line marking at all?**

Proposed answer, pending Milestone 4 evidence: close heading inside RPP and use
`SPEED_RATE` as the single tracking mode. Reserve `SPEED_HEADING` for approach and
alignment where transients are harmless, and `PIVOT_RATE` for pivots. One loop during
the operation that has to be accurate.

Decide with data from the Milestone 4 hardware bring-up, before RPP is ported.
