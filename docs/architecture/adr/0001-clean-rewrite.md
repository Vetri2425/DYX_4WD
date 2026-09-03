# ADR-0001: Clean rewrite, not incremental refactor

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 1, 27, 28

## Context

`rover_ws` works. It has marked real lines on real ground, and its behavior encodes
field knowledge that exists nowhere else — the yaw-rate dead zone, the speed
feed-forward calibration, terminal approach behavior, the asymmetric QPPS fault and its
fix. Throwing that away would be expensive and stupid.

But its structure blocks the requirement. The control ownership problem (ADR-0004) is
not a bug inside a module; it is the shape of the interface between RPP and PX4.
Python nodes in the control path are not a performance detail; they are a jitter source.
Tracked backup files, mixed ownership, and launch-file tuning values are symptoms of
having no boundary discipline at all.

You cannot incrementally refactor your way from "RPP emits an XY velocity vector" to
"RPP owns rotational intent." That is a different contract, and every consumer changes
with it.

## Decision

Build a new repository. Treat `rover_ws` as **evidence** — a record of verified
behavior, formulas, safety rules, mission flow, and failure modes — not as a source
tree to be migrated.

Every behavior crosses over only via: verify from source and bags → write an explicit
contract → implement clean → unit test → bag replay comparison → shadow test → field
test.

## Alternatives considered

### Option A — Incremental refactor in place

**Pros**
- Never loses field validity; the rover works throughout
- Small, reviewable steps
- No parallel-stack maintenance burden
- Team keeps one mental model

**Cons**
- Cannot change the RPP↔PX4 contract without a flag day anyway
- Python-to-C++ migration inside a live graph means both runtimes coexist for months
- Structural problems (ownership, config, backups) tend to survive refactors — the
  path of least resistance is always to leave them
- Every step is constrained by compatibility with code we intend to delete

### Option B — Clean rewrite, old stack as evidence *(chosen)*

**Pros**
- The contract can be right from day one
- Boundaries are enforced before code exists to violate them
- Installer, CI, and provenance can be built in rather than bolted on
- Agent-generated code has a specification to be checked against

**Cons**
- Two stacks to think about until cutover
- Real risk of never finishing — the rewrite that ships nothing is a known failure mode
- Field knowledge can be lost if the Phase 0 freeze is done carelessly
- No incremental field validation until quite late

### Option C — Rewrite from scratch, ignore the old stack

**Pros**
- Fastest to write
- No legacy thinking

**Cons**
- Discards field-earned knowledge that took months to acquire
- Guarantees rediscovering the same bugs on real hardware, at real cost
- Rejected without much debate

## Why we chose what we chose

The deciding factor is that the control ownership change is not optional and not
incremental. Once you accept that RPP must emit explicit rotational intent, most
consumers change anyway — so the incremental path's main advantage (never breaking a
working system) largely evaporates.

The rewrite's main risk — losing field knowledge — is addressable by process (Phase 0
evidence freeze, contract tests, bag replay). The refactor's main risk — carrying the
architecture forward — is not addressable by process.

## Consequences

**We accept:** a period with two stacks, and the schedule risk of a rewrite.

**We must therefore:**
- Complete Phase 0 before touching control behavior. `docs/migration/current_behavior_contract.md`
  is not optional paperwork; it is the only thing preventing Option C by accident.
- Preserve field bags with provenance, since they become the regression suite.
- Keep `rover_ws` runnable and frozen at a known commit for the whole migration.
- Ship milestones that are independently useful, so the rewrite cannot silently stall.

**Revisit if:** three months in, the new stack has not achieved a hardware-proven PX4
control path. That would mean the rewrite is not converging and the incremental path
deserves reconsideration.
