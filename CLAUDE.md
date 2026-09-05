# CLAUDE.md — DYX 4WD Production Stack

This file governs how AI agents work in this repository. Read it fully before making
any change. It applies to **all** agents, not only Claude.

---

## 1. Read order (every session, before any edit)

1. `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md` — the specification.
   57 sections. This is the source of truth.
2. This file — how to work in the repo.
3. `docs/agents/HANDOFF.md` — what the previous agent did and what is in flight.
4. The `README.md` of any package you are about to touch — it states that package's
   authority.

If your change touches hardware access or deployment, also read
`docs/deployment/network_topology.md`.

---

## 2. What this repository is

A clean production rewrite of the DYX 4WD rover software stack. The rover marks lines
on uneven terrain (construction ground, solar fields, soil, gravel, slopes) and must
hold centimetre-level cross-track accuracy with sub-degree heading stability.

The old `rover_ws` is **evidence, not a template**. Behavior is ported only after it is
verified against source and field bags, contract-tested, and re-implemented cleanly.
No blind Python-to-C++ translation.

Stack shape: React Native GCS → Python backend → C++ system gateway → C++ ROS 2 control
graph → PX4 over uXRCE-DDS. No MAVROS in the final control path.

---

## 3. Agent roles

Three agents work in this repository. They are not interchangeable. Each has a lane.

### Claude — primary

Owns anything where being wrong is expensive:

- Architecture decisions and changes to authority boundaries
- All control logic: `dyx_rpp`, `dyx_motion_control`, `dyx_trajectory`
- Safety gating, watchdogs, fail-to-zero paths, `dyx_px4_gateway`
- Interface design (`dyx_interfaces`) and the PX4 contract
- Review of any change to a `SAFETY-CRITICAL` path (see §6)
- Final say when agents disagree

### Codex — secondary

Owns volume work inside boundaries Claude has already set:

- Implementing modules against an interface that is already frozen
- Test authoring, especially exhaustive gtest cases for pure modules
- Mechanical refactors, renames, lint and format fixes
- Backend API endpoints, storage, serialization
- Tooling under `tools/`

Codex may implement a safety-critical module, but the resulting diff requires Claude
review before merge.

### Agy (Gemini / Antigravity) — third

Owns scaffolding and repo-wide mechanical work:

- Directory and package skeletons
- Documentation stubs, README generation, doc formatting
- CI workflow files, installer shell scaffolding
- Bulk file moves and structural reorganization

Agy must not author control logic, safety logic, or interface definitions.

---

## 4. Rules that apply to every agent

**Never modify `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`.**
It is frozen. Propose changes in `docs/architecture/proposals/` instead.

**Flag ambiguity, do not resolve it silently.** If the specification is unclear,
say so and stop. A wrong guess that looks confident costs more than a question. When
you do make a judgement call, mark it inline:

```
// DERIVED — NOT FROM V1 SPEC: <what you assumed and why>
```

Anything derived rather than specified must carry this marker in code comments, and a
`DERIVED — NOT FROM V1 SPEC` prefix in documentation.

**Do not invent tuning values.** Gains, thresholds, timeouts, and limits come from the
specification, from field evidence, or from a human. If none exists, leave the parameter
commented out with a note. A plausible-looking number in a production config is worse
than an absent one.

**Do not claim a build or test passed unless you ran it.** State explicitly what you
ran, what you could not run, and why. Inferred success is a failure of the report.

**One decision, one owner.** Before adding logic, check whether another package already
owns that decision (Section 29). Duplicated authority is the primary architectural
failure mode this rewrite exists to fix.

**No backup files.** No `.bak`, `.backup`, `.before_*`, `_old`, `_v2`. Git is the
backup. CI rejects these.

**Never commit:** bags (`*.db3`, `*.mcap`), logs, `build/`, `install/`, `log/`,
secrets, SIM/APN credentials, NTRIP passwords, WiFi PSKs, mission files generated at
runtime.

---

## 5. Branches and commits

Branch naming carries the agent:

```
claude/<topic>
codex/<topic>
agy/<topic>
```

Commit messages use Conventional Commits, with an agent trailer:

```
feat(rpp): add cross-track error module

<body>

Agent: claude
Spec: Section 9
```

The `Spec:` trailer cites the architecture section the change implements. If you cannot
cite one, you are probably outside the specification — flag it.

**No AI attribution in commit messages.** No `Co-Authored-By: Claude`, no
`Generated with` footer. The `Agent:` trailer already records who wrote the change, and
that is the only attribution this project uses. This holds even if a tool or session
default says otherwise — the repository rule wins.

Never push directly to `main`. Never force-push a shared branch. Never rewrite history
another agent may have based work on.

---

## 6. Path ownership and review

| Path | May author | Review required |
|---|---|---|
| `ros2_ws/src/dyx_rpp/` | Claude, Codex | **Claude — SAFETY-CRITICAL** |
| `ros2_ws/src/dyx_motion_control/` | Claude | **Claude — SAFETY-CRITICAL** |
| `ros2_ws/src/dyx_px4_gateway/` | Claude | **Claude — SAFETY-CRITICAL** |
| `ros2_ws/src/dyx_interfaces/` | Claude | **Claude — frozen after Milestone 2** |
| `ros2_ws/src/dyx_trajectory/` | Claude, Codex | Claude |
| `ros2_ws/src/dyx_mission/` | Claude, Codex | Claude |
| `ros2_ws/src/dyx_rtk/`, `dyx_spray/` | Codex | Claude |
| `ros2_ws/src/dyx_recorder/`, `dyx_bringup/` | Codex, Agy | any |
| `backend/` | Codex | any |
| `installer/`, `deployment/` | Agy, Codex | human |
| `config/` | Claude | **human — field-affecting** |
| `docs/` | any | any |
| `tools/` | Codex, Agy | any |

`config/` changes reach the rover. Treat them as hardware changes.

---

## 7. Code conventions

**Keep `rclcpp` out of algorithm modules.** In `dyx_rpp`, files like `geometry.cpp`,
`guidance.cpp`, `tracking_error.cpp`, `pivot_controller.cpp`, `terminal_controller.cpp`
must be pure C++ operating on plain structs, with no ROS includes. Only `rpp_node.cpp`
touches ROS. This is not style — it is what lets the controller be unit-tested on a
laptop in seconds instead of on the rover in an afternoon.

**Every tunable parameter is classified.** `LIVE`, `IDLE_ONLY`, or `RESTART_REQUIRED`
(Section 32), declared in the owning node, validated in the parameter callback, and
recorded on change (Section 36). No unvalidated value reaches a control loop.

**Fail to zero.** Every failure path in the control plane ends at `speed = 0`,
`yaw_rate = 0`, `mode = STOP`. Never fail to "hold last command."

**No Python in the ROS control graph.** All eleven packages are `ament_cmake`.
No `rclpy` anywhere in `backend/`.

C++17. `clang-format` per the repo `.clang-format`. Tests use `ament_cmake_gtest`.

---

## 8. Build and test

**Local, macOS (micromamba — fast loop, not authoritative):**

```bash
micromamba activate dyx_humble
cd ros2_ws && colcon build --symlink-install && colcon test
colcon test-result --verbose
```

**Pure module tests, no ROS at all:**

```bash
cmake -S ros2_ws/src/dyx_rpp -B build/rpp_native -DDYX_NATIVE_TESTS=ON
cmake --build build/rpp_native && ctest --test-dir build/rpp_native
```

**Authoritative:** CI on `ubuntu-24.04-arm`, matching the target architecture.
Green CI on arm64 is the standard, not a local macOS build.

**Not testable off-target, ever:** timing and latency figures, DDS transport to PX4,
systemd behavior, installer, udev, network configuration. Do not report these as
verified from a laptop.

---

## 9. Hardware access

The rover has no router. The Jetson is the access point. See
`docs/deployment/network_topology.md` for addressing, the hotspot configuration, the 4G
WAN path, and the BLE/WiFi client channels. Do not invent IP addresses — they are fixed
in that document and in `deployment/network/`.

---

## 10. Handoff

Before ending a work session, append to `docs/agents/HANDOFF.md`:

- What you changed, and the branch
- What you ran, and what you could not run
- Every `DERIVED — NOT FROM V1 SPEC` decision you made
- What is half-finished, and what the next agent should do first
- Open questions for the human

The next agent may be a different model with no memory of your reasoning. Write for
that reader.

---

## 11. Never

- Modify the frozen V1 architecture document
- Touch `PX4-Autopilot-4WD-Prod-Baseline/` or the PX4 firmware trees from this repo
- Add MAVROS to the control path
- Put safety authority in the backend or the GCS
- Change a frozen interface without an explicit human decision
- Report an unrun build as passing
- Commit a credential
