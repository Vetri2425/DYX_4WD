# ADR-0002: C++ for the ROS 2 control graph, Python confined to the backend

- **Status:** ACCEPTED
- **Date:** 2026-09-03
- **Spec:** Sections 1, 4, 5

## Context

The accuracy target is centimetre cross-track with sub-degree heading stability on
uneven terrain. At 0.8 m/s, 25 ms of control latency is 2 cm of lag. Jitter matters as
much as mean latency, because a controller whose period varies is a controller whose
effective gain varies.

`rover_ws` runs Python ROS nodes in the control path. Python's garbage collector and
the GIL introduce pauses that are small on average and occasionally large — precisely
the distribution that ruins a tracking controller and is nearly impossible to debug
from field symptoms.

Separately: three AI agents write code here. Language choice affects how reviewable
generated code is.

## Decision

All production ROS 2 nodes are C++ (`ament_cmake`, C++17). Python is permitted only in
`backend/` and `tools/`. No `ament_python` packages in the production graph, no `rclpy`
in the backend.

## Alternatives considered

### Option A — Python throughout (rclpy)

**Pros**
- Fastest iteration; no compile step
- Existing `rover_ws` code is already Python — direct port possible
- numpy/scipy available for geometry
- Easiest for a single engineer to hold in their head
- Agents write correct Python more reliably than correct C++

**Cons**
- GC pauses and GIL contention produce control-loop jitter
- No meaningful real-time behavior
- Cannot use intra-process zero-copy composition
- Deployment is heavier (interpreter, venv, dependency drift on the rover)
- Timing is not reproducible enough to validate a timing contract against

### Option B — C++ control, Python backend *(chosen)*

**Pros**
- `rclcpp` is the first-class ROS 2 API; composable nodes and intra-process comms are
  available if the timing budget demands them
- Deterministic memory behavior; no GC pause
- `px4_msgs` and the DDS path are C++-native
- Compiler catches an entire class of agent-generated errors before review
- Python stays where it is genuinely better: HTTP, serialization, storage, analysis

**Cons**
- Slower iteration; build times matter
- More code for the same logic
- Agent-generated C++ needs stricter review — memory and lifetime errors are subtle
- Two toolchains to maintain in CI

### Option C — Rust

**Pros**
- Memory safety without GC; excellent for safety-critical control
- Strong compile-time guarantees on a stack where failures are physical

**Cons**
- ROS 2 bindings (`r2r`, `ros2_rust`) are not first-class and lag releases
- `px4_msgs` code generation is immature
- Smallest ecosystem for rover/PX4 work — every problem is solved alone
- Weakest agent support of the three; generated Rust would need the most human rework
- Single-engineer project; the learning curve is the schedule

## Why we chose what we chose

Jitter is the tie-breaker. Everything else on the Python side is a productivity
argument, and productivity arguments lose to a requirement that cannot be met.

Rust is the technically superior answer for safety-critical control and the wrong answer
for this project — the ROS 2 and PX4 ecosystems are C++ ecosystems, and a one-engineer
team with three code-generating agents cannot afford to be the ones porting bindings.

## Consequences

**We accept:** slower iteration, more code, more review burden on generated C++.

**We must therefore:**
- Keep `rclcpp` out of algorithm modules. `geometry`, `guidance`, `tracking_error`,
  `pivot_controller`, `terminal_controller` are pure C++ on plain structs, compiled and
  tested with plain CMake. This preserves most of Python's iteration speed for the code
  that changes most.
- Enforce this in review — one `#include <rclcpp/rclcpp.hpp>` in a geometry header
  destroys the property.
- Require Claude review on generated C++ in safety-critical paths (CLAUDE.md §6).

**Revisit if:** intra-process composition and pure-module testing still leave iteration
so slow that controller development stalls. The answer then is better tooling, not
Python in the control loop.
