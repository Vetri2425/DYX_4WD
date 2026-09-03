# ADR-0011: Recorder is a production component with mandatory provenance

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 19, 36, 37

## Context

The migration strategy in ADR-0001 rests entirely on field bags being trustworthy
evidence. Bag replay comparison and shadow validation are only meaningful if we know
exactly which software, firmware, configuration, and parameter values produced the bag.

In `rover_ws` the recorder is a developer script started by hand. Bags therefore exist
without knowing which commit produced them — and a bag whose provenance is unknown
cannot settle an argument.

## Decision

`dyx_recorder` is a production package with its own systemd service. It starts
automatically, creates a run ID, and writes a run directory containing the bag plus
`manifest.json`, `git_versions.json`, a config snapshot, `mission.json`, and
`summary.json`. A run without provenance is incomplete evidence.

## Alternatives considered

### Option A — Developer script, started manually

**Pros**
- Zero infrastructure
- Records only when someone wants it, saving disk

**Cons**
- Forgotten exactly when something interesting happens
- No provenance, so bags cannot be compared across time
- Cannot be used as a regression suite, which removes the foundation of the migration plan

### Option B — Recording inside the control graph

**Pros**
- One less service
- Direct access to intra-process data

**Cons**
- Disk I/O and serialization inside the control process — a full disk or slow write
  becomes a control-loop problem
- Recorder crash takes down control
- Cannot outlive a graph restart, losing the record of the failure

### Option C — Independent production service with manifest *(chosen)*

**Pros**
- Records regardless of operator memory
- Survives backend failure and is isolated from the control graph
- Provenance makes bags comparable across months and across releases
- Directly enables replay-based validation

**Cons**
- Disk consumption becomes an operational concern
- Write bandwidth on a Jetson shared with control
- Retention, offload, and disk-full behavior all need designing
- Snapshotting PX4 parameters at mission start adds startup latency

## Why we chose what we chose

Every validation step in the migration plan consumes recorded evidence. Making the
recorder optional makes the validation strategy optional.

## Consequences

**We accept:** disk pressure and I/O contention as real operational concerns.

**We must therefore:**
- Define disk-full behavior explicitly. The rover must keep operating safely when
  recording fails — recording is evidence, not a control dependency
- Isolate I/O: separate storage if possible, and I/O scheduling that cannot starve the
  control graph
- Record `px4_msgs` SHA and PX4 firmware SHA (ADR-0003), without which a bag cannot be
  deserialised correctly later
- Include the parameter-change audit stream (Section 36) in the bag
- Define retention and offload — a Jetson disk is not an archive

**Revisit if:** measured I/O contention affects control timing. The answer is to move
storage, not to weaken provenance.
