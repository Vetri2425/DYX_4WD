# ADR-0009: Live parameter tuning with LIVE / IDLE_ONLY / RESTART_REQUIRED

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 30–38

## Context

Controller tuning on a real rover is iterative: change a gain, drive a line, look at the
result. If each change requires editing YAML, killing the launch, and relaunching, the
cycle is minutes long and field sessions are wasted on restarts. `rover_ws` works this
way and it is the single biggest drag on tuning throughput.

But live parameter changes on a moving machine are also a way to inject an unsafe value
into a control loop.

## Decision

Every tunable parameter is classified `LIVE`, `IDLE_ONLY`, or `RESTART_REQUIRED`,
declared by exactly one owning node, validated in the parameter callback before it is
accepted, and recorded on change with timestamp, old value, new value, source, and
mission ID.

## Alternatives considered

### Option A — Restart for every change

**Pros**
- No unsafe live transition is possible
- Active configuration always equals the file on disk
- Trivial to reason about

**Cons**
- Minutes per iteration; field sessions dominated by restarts
- Encourages tuning by guesswork because trying something is expensive
- Restarting the graph mid-session has its own risks

### Option B — Everything live-tunable

**Pros**
- Fastest possible iteration

**Cons**
- Changing a DDS endpoint or a filesystem path at runtime is meaningless or harmful
- Changing vehicle geometry mid-mission invalidates in-flight state
- No structural distinction between a gain and an IP address

### Option C — Three classes with validation and audit *(chosen)*

**Pros**
- Fast iteration where it is safe, refusal where it is not
- The rejection carries a reason, so the operator learns the boundary
- Audit trail answers "what was active at this moment" without guessing — which is what
  makes field bags admissible as evidence
- Profiles separate experimentation from committed configuration

**Cons**
- Every node needs parameter-callback machinery — real implementation cost across eleven
  packages
- Atomic multi-parameter updates are genuinely hard; changing two coupled gains
  one-at-a-time passes through an invalid intermediate state
- Runtime values can diverge from the file, so "what is the configuration" has two
  answers
- Classification itself is a judgement call and will be got wrong somewhere

## Why we chose what we chose

The audit requirement decides it independently of tuning speed. Without a change record,
no field bag can be trusted as evidence, because the parameters active during the run
are unknowable. Section 36 is not a convenience feature; it is what makes the whole
validation strategy in ADR-0001 work.

Given that the audit machinery must exist, the marginal cost of live tuning is small.

## Consequences

**We accept:** callback machinery in every node, and divergence between runtime and file.

**We must therefore:**
- Classify each parameter deliberately, not by pattern-match. Safety limits and
  watchdog timeouts are `IDLE_ONLY`, not `RESTART_REQUIRED` — infrastructure means
  addresses, transports, ports, and paths
- Support atomic multi-parameter set, since coupled gains cannot be changed safely one
  at a time
- Never auto-write a live value into a profile YAML. Saving is explicit (Section 35)
- Snapshot all parameters — ROS and PX4 — at mission start and end (Section 37)
- Prove this in Milestone 5, before the RPP port, so the controller is developed with
  the tuning loop already fast

**Revisit if:** classification proves too coarse — a plausible fourth class is
"live but requires operator confirmation."
