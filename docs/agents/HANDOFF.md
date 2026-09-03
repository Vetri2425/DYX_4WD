# HANDOFF

Append-only. Newest entry at the top. Read the whole file before starting work.

---

## 2026-09-03 — Architecture and documentation session

**Participants:** Vetri (engineer) with Claude as design collaborator, in a chat
session. Agy (Antigravity/Gemini) executing repository writes.

**Important context for the next agent:** Claude did not have repository access in this
session. It acted as a design collaborator — reviewing the architecture, arguing
decisions, and drafting documents — while Agy performed all repository operations. Every
file described below reached the repo through Agy. If something in the repo contradicts
what is written here, the repo is the fact and this note is the intent.

### Repository state

| Commit | What |
|---|---|
| `3be3e08` | Milestone 1 architecture skeleton — 159 files, 11 `ament_cmake` packages |
| `174d515` | Architecture decision records and stack rationale — 20 files under `docs/architecture/` |
| (later) | `CLAUDE.md` and `docs/deployment/network_topology.md` |

Working tree clean. **Not yet pushed to a remote at the time of writing** — CI has
therefore never run.

### What was produced

**`CLAUDE.md`** (repo root) — governs how all three agents work here. Read it before
anything else. Defines role boundaries (Claude: control logic, safety, interfaces;
Codex: implementation volume and tests; Agy: scaffolding, docs, CI), the path ownership
and review table, branch and commit conventions including the `Spec:` trailer, and the
`DERIVED — NOT FROM V1 SPEC` marker required on anything inferred rather than specified.

**`docs/architecture/`** — 15 ADRs plus index, template, and `STACK.md`. Twelve accepted
decisions with alternatives argued on their merits. Three PROPOSED ADRs that block
milestones. `STACK.md` is the layer-by-layer map.

**`docs/deployment/network_topology.md`** — Jetson as access point, no router. Three
separated planes: PX4 control `192.168.10.0/24` never bridged to clients, AP
`192.168.20.0/24`, 4G carrying the only default route. BLE for provisioning, WiFi for
telemetry.

### Decisions that are settled

Recorded in ADRs 0001–0012, ACCEPTED. Do not re-litigate these; if you disagree, write a
superseding ADR rather than changing behavior.

Clean rewrite with `rover_ws` as evidence (0001). C++ control graph, Python confined to
backend (0002). Direct uXRCE-DDS, MAVROS removed (0003). RPP owns rotational intent
(0004). PX4 EKF as sole estimator (0005). No wheel odometry (0006). Four systemd
services (0007). Single ROS↔backend boundary (0008). Three parameter classes with
validation and audit (0009). Release artifacts with rollback (0010). Recorder as
production component (0011). Jetson as access point (0012).

### Open — these block milestones

| ID | Question | Blocks | Notes |
|---|---|---|---|
| ADR-0013 | Jetson vs Radxa | Milestone 3 | No GPU workload exists in the architecture. Decide on roadmap, not habit. |
| ADR-0014 | Ethernet vs serial to PX4 | Milestone 4 | **Check the carrier board.** CubeOrange+ standard/ADS-B carriers have no Ethernet. Changes the timing budget. |
| ADR-0015 | Nozzle as control point | accuracy spec | Not in V1 at all. Without it "±2 cm" is not testable. |
| OQ-1 (in ADR-0004) | `SPEED_HEADING` during marking? | RPP port | Mode switching is a plausible oscillation source. Recommendation: close heading in RPP, use `SPEED_RATE` as the single tracking mode. Decide with Milestone 4 data. |

All four are answered by the Milestone 4 hardware session plus one mechanical
measurement session. Cheap now, expensive after the controller is built on them.

### Outstanding work items

1. **Push and let CI run.** `colcon build` has never actually executed — Agy correctly
   flagged that it verified `package.xml` and `CMakeLists.txt` structurally but could not
   run the build (no ROS, no colcon, no Docker on the Mac). This is the single
   unverified claim in Milestone 1.
2. **Switch the CI runner to `ubuntu-24.04-arm`.** Currently x86_64. Fine for empty
   packages; misleading once real C++ lands, since the target is arm64.
3. **Fix parameter classification** in `config/motion_control/production.yaml`. Agy
   classified `command_timeout` and `telemetry_timeout` as `RESTART_REQUIRED`. They are
   safety limits, which Section 32 places under `IDLE_ONLY`. `RESTART_REQUIRED` is for
   infrastructure — addresses, transports, ports, paths. As classified, a watchdog cannot
   be adjusted between missions without a full relaunch.
4. **Add `DERIVED — NOT FROM V1 SPEC` markers** to the "must not own" sections Agy wrote
   into package READMEs for `dyx_rpp`, `dyx_px4_gateway`, `dyx_rtk`, `dyx_spray`, and
   `dyx_recorder`. V1 has no "must not" statement for these; the content is inferred and
   currently reads as specification.
5. **Verify where `PX4-Firmware/` actually lives.** Agy reported it nested inside
   `PX4-Autopilot-4WD-Prod-Baseline/`; an earlier `tree -L 2` showed it as a top-level
   sibling with two commit-prefixed subdirectories resembling worktrees. Both cannot be
   right, and the PX4 contract will be frozen against one of these trees.
6. **Set up Tailscale on the companion computer.** Development happens on a MacBook at
   home; the rover hardware is at the office. Tailscale over the 4G link gives remote
   access without joining the rover hotspot and without losing internet on the Mac.

### Recommended next task

`docs/interfaces/px4_contract_v1.md`. It is referenced by `dyx-version` and by ADR-0003
but does not exist. It must enumerate every uORB topic, the `px4_msgs` commit SHA, and
the PX4 parameters forming the contract — including the EKF2 and GNSS-heading parameters
that ADR-0005 pulls into the audit system.

It is what makes the DDS version lock survivable: a `px4_msgs` mismatch deserializes
silently wrong rather than erroring. It is also the document Milestone 4 fills in, so
drafting its skeleton now makes that session productive.

### Environment notes

- Development machine is macOS (Apple Silicon). No Docker installed as of this session.
- micromamba is available. RoboStack ships ROS 2 Humble for `osx-arm64` — usable for a
  fast local `colcon build` loop.
- Authoritative build is CI on arm64. macOS builds are for iteration, not verification.
- Never report timing, DDS transport, systemd, installer, or network behavior as
  verified from a laptop. Those are target-hardware-only.
- Keep `rclcpp` out of `dyx_rpp` algorithm modules. This is what makes laptop testing
  possible and it will erode without active enforcement.

### Judgement calls made this session

Flagged rather than silently resolved, per `CLAUDE.md`:

- **`DYX_4WD` placed as a sibling of the PX4 trees**, with its own Git repository, rather
  than nested or sharing history. Not specified in V1.
- **No `.msg` files authored** despite V1 Section 6 listing filenames. Interface freeze
  is Milestone 2 and should follow Milestone 4 hardware evidence, not precede it.
- **Config YAML values left commented out.** Inventing plausible tuning numbers into a
  production config is worse than an absent value.
- **Three validation documents added that are not in V1** — `control_point_definition`,
  `timing_contract`, `performance_contract` — as stubs. These address gaps in the cm
  accuracy requirement, not anything V1 asked for.
- **ADR-0004 accepted with an open question rather than fully.** V1 specifies mode
  switching between `SPEED_HEADING` and `SPEED_RATE`. That is recorded as the decision,
  with the oscillation concern documented as OQ-1 rather than quietly overridden.
