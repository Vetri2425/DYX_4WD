# GPT HANDOFF — DYX 4WD Production Stack

**Date:** 2026-09-04
**Author:** Vetri
**Purpose:** Close the architecture/interface-contract milestone and establish the exact starting state for the PX4 firmware, communication, localization, and hardware-commissioning phase.

---

## 1. Read This First

This handoff records the work completed after the previous:

```text
docs/agents/HANDOFF.md
```

The previous handoff described the initial architecture session and listed `px4_contract_v1.md` as the next task.

That work and the subsequent interface/safety contracts are now complete.

The project is moving from:

```text
ARCHITECTURE / CONTRACT DESIGN
```

to:

```text
PX4 FIRMWARE
→ PX4 ↔ COMPANION COMMUNICATION
→ LOCALIZATION / ESTIMATOR
→ HARDWARE COMMISSIONING
→ ROS CONTROL IMPLEMENTATION
→ RPP
```

Do not restart architecture design from zero.

Repository state is authoritative if this handoff ever conflicts with actual source.

---

# 2. Production Repositories

## DYX production stack

```text
Repository:
Vetri2425/DYX_4WD

Default working branch:
master
```

This is the clean production rewrite.

It must remain separate from the old rover workspace.

---

## PX4 production firmware

```text
Repository:
Vetri2425/PX4-Autopilot-4WD-Prod-Baseline

Production branch:
dyx-4wd-production
```

Pinned upstream PX4 baseline:

```text
PX4:
v1.17.0 stable

Base SHA:
d6f12ad1c4f70ad3230afd7d86e971421e02fef4
```

Known production branch state before the firmware implementation phase:

```text
ff5e216
```

Do not silently rebase onto PX4 `main`.

Any upstream change must be reviewed as a deliberate backport or baseline update.

---

# 3. Hardware Target

Production flight controller:

```text
Holybro Pixhawk 6X
PX4 board:
px4_fmu-v6x_default
```

Production companion target remains Jetson/Radxa class hardware until the hardware ADR is finally closed.

Production ROS:

```text
ROS 2 Humble
```

Target PX4 communication:

```text
Ethernet
+
Micro XRCE-DDS
+
native px4_msgs
```

Production architecture does not use MAVROS.

---

# 4. Architecture Milestone — CLOSED

The architecture and core contract-design milestone is complete.

The system architecture is now governed by:

```text
docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md
```

This document is frozen.

Do not edit it.

Derived implementation decisions must be documented separately and marked:

```text
DERIVED — NOT FROM V1 SPEC
```

when they are not explicitly stated by Architecture V1.

---

# 5. Core Contract Set — COMPLETE

The planned core document set is now complete.

## 1. Architecture

```text
docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md
```

Status:

```text
FROZEN
```

---

## 2. PX4 contract

```text
docs/interfaces/px4_contract_v1.md
```

Status:

```text
FROZEN
```

Defines:

```text
PX4 version
px4_msgs version
DDS topics
rover setpoints
Offboard semantics
PX4 authority
timestamp behavior
failsafe behavior
estimator/GNSS telemetry
firmware provenance
```

---

## 3. Motion setpoint contract

```text
docs/interfaces/motion_setpoint.md
```

Status:

```text
FROZEN
```

Canonical internal command:

```text
timestamp_us
sequence
control_mode
speed_mps
heading_rad
yaw_rate_rad_s
valid
```

---

## 4. Vehicle geometry / estimator physical contract

```text
docs/hardware/vehicle_geometry_estimator_contract_v1.md
```

Status:

```text
PRE-COMMISSIONING BASELINE
```

Physical measurements remain TBD.

---

## 5. PX4 ↔ companion communication contract

```text
docs/interfaces/px4_companion_communication_v1.md
```

Status:

```text
IMPLEMENTATION BASELINE
```

Defines Ethernet/uXRCE-DDS architecture, communication states, topic requirements and recovery expectations.

---

## 6. System health / safety contract

```text
docs/interfaces/system_health_safety_contract_v1.md
```

Status:

```text
IMPLEMENTATION BASELINE
```

Defines:

```text
CAN_AUTONOMY_MOVE
fail-to-zero
E-stop
PX4 failsafe
estimator readiness
DDS readiness
RPP readiness
Motion Control authority
stale-command behavior
recovery
```

---

## 7. Backend telemetry contract

```text
docs/interfaces/backend_telemetry_contract_v1.md
```

Status:

```text
IMPLEMENTATION BASELINE
```

Defines:

```text
ROS → System Gateway → Backend → Frontend
authoritative telemetry
online/offline semantics
freshness
rate classes
reconnection
no frontend control-value recomputation
```

---

## 8. Recorder / evidence contract

```text
docs/interfaces/recorder_evidence_contract_v1.md
```

Status:

```text
IMPLEMENTATION BASELINE
```

Defines:

```text
run identity
rosbag evidence
event evidence
configuration snapshots
Git/PX4 provenance
geometry evidence
accuracy evidence
recorder independence
```

The planned core architecture-contract set is:

```text
8 / 8 COMPLETE
```

---

# 6. Production Control Architecture

The production control chain is:

```text
Mission
   ↓
Trajectory
   ↓
DYX RPP
   ↓
MotionSetpoint
   ↓
Motion Control
   ↓
ValidatedMotionSetpoint
   ↓
PX4 Gateway
   ↓
ROS 2 / DDS
   ↓
Micro XRCE-DDS
   ↓
PX4 Rover Controllers
   ↓
Differential Allocation
   ↓
Motors
```

---

# 7. Authority — FROZEN

## Mission / Trajectory

Own:

```text
target identity
surveyed GPS targets
mission lifecycle
path geometry
```

Do not own steering corrections.

---

## RPP

Owns:

```text
cross-track error
along-track error
goal distance
desired heading
heading correction
desired yaw rate
desired speed
pivot decision
terminal approach
stop decision
```

RPP is the path-level rotational authority.

---

## Motion Control

Owns validation.

Checks:

```text
freshness
valid flag
finite values
mode
sequence/session
speed limits
yaw-rate limits
reverse prohibition
mission authorization
system safety
E-stop
```

Failure means:

```text
speed = 0
yaw_rate = 0
```

Motion Control shall not invent steering.

---

## PX4

Owns:

```text
EKF
speed inner loop
yaw-rate inner loop
physical acceleration/deceleration handling
control allocation
motor outputs
PX4 failsafe
```

PX4 shall not become the DYX path planner.

---

# 8. Production Motion Modes

Canonical enum remains:

```text
STOP
SPEED_HEADING
SPEED_RATE
PIVOT_RATE
```

Production V1 active behavior:

### STOP

```text
speed = 0
yaw_rate = 0
```

---

### SPEED_RATE

Used for:

```text
straight tracking
cross-track correction
heading correction
curves
cruise
terminal approach
```

RPP provides:

```text
speed
yaw_rate
```

PX4 executes the physical loops.

---

### PIVOT_RATE

Used for:

```text
spot/pivot turning
```

Command:

```text
speed = 0
yaw_rate != 0
```

---

### SPEED_HEADING

Retained for architecture/schema compatibility.

Production V1 Motion Control rejects receipt of this mode.

It is not used for normal DYX tracking.

---

# 9. PX4 Native Rover Interface — VERIFIED

PX4 v1.17 contains native rover messages.

## Speed

```text
RoverSpeedSetpoint
```

Important field:

```text
speed_body_x
```

Positive means forward body speed.

---

## Yaw rate

```text
RoverRateSetpoint
```

Important field:

```text
yaw_rate_setpoint
```

Unit:

```text
rad/s
```

NED yaw convention.

---

## Attitude

```text
RoverAttitudeSetpoint
```

Contains:

```text
yaw_setpoint
```

For direct DYX Speed+Rate operation, attitude yaw must not compete with the rate authority.

---

# 10. Do Not Use TrajectorySetpoint For DYX Motion

PX4 contains a rover Offboard adapter that can convert velocity vectors into speed + attitude/yaw.

This resembles the old rover architecture.

DYX deliberately does not use that architecture.

Do not send DYX motion through:

```text
TrajectorySetpoint
```

for production rover steering.

Use native rover setpoints.

---

# 11. DDS Topics

Important PX4 input topics include:

```text
/fmu/in/offboard_control_mode
/fmu/in/rover_speed_setpoint
/fmu/in/rover_rate_setpoint
/fmu/in/rover_attitude_setpoint
/fmu/in/vehicle_command
```

Required telemetry includes:

```text
/fmu/out/vehicle_status
/fmu/out/vehicle_control_mode
/fmu/out/vehicle_attitude
/fmu/out/vehicle_local_position
/fmu/out/vehicle_global_position
/fmu/out/vehicle_odometry
/fmu/out/vehicle_gps_position
/fmu/out/estimator_status_flags
/fmu/out/failsafe_flags
/fmu/out/vehicle_command_ack
/fmu/out/timesync_status
```

Always verify against the pinned PX4 `dds_topics.yaml`.

Do not assume a topic exists because it exists on newer PX4 `main`.

---

# 12. px4_msgs Version Lock

Production `px4_msgs` must be pinned.

Known audited pin:

```text
repository:
PX4/px4_msgs

release family:
release/1.17

SHA:
86d8239e962f6939e05c3737784f60c02fa884db
```

Do not use floating `main`.

Firmware and `px4_msgs` schemas must remain compatible.

---

# 13. Critical PX4 Finding — Stale Rover Commands

This is a confirmed source-level safety issue for our architecture.

PX4 differential speed/rate controllers retain their latest finite rover setpoint.

No individual command-age watchdog was found inside:

```text
DifferentialSpeedControl
DifferentialRateControl
```

Therefore this failure is possible:

```text
RPP stops producing commands

Gateway remains alive

OffboardControlMode heartbeat continues

PX4 remains in Offboard

last speed/yaw-rate setpoint remains active
```

PX4 Offboard heartbeat alone is not enough to detect this condition.

---

# 14. Mandatory Two-Layer Watchdog

## Layer A — Companion

Motion Control / Gateway shall monitor command freshness.

If the RPP/control command becomes stale:

```text
speed = 0
yaw_rate = 0
```

A new valid command is required before movement resumes.

Exact timeout:

```text
TBD FROM MEASURED RATE/JITTER
```

Do not invent a production value.

---

## Layer B — PX4

If Gateway/DDS itself dies:

```text
OffboardControlMode heartbeat stops
```

PX4 Offboard-loss behavior then provides the second safety layer.

Relevant policy includes:

```text
COM_OF_LOSS_T
COM_OBL_RC_ACT
```

Exact production values require hardware commissioning.

---

# 15. Critical PX4 Finding — RO_YAW_RATE_TH

PX4 documentation describes:

```text
RO_YAW_RATE_TH
```

primarily as a measured-yaw-rate noise threshold.

Exact v1.17 source also applies the threshold to the requested yaw-rate setpoint.

Conceptually:

```text
abs(requested_yaw_rate) <= threshold
    → requested yaw rate becomes zero
```

This matters significantly for DYX.

Small RPP corrections may disappear inside PX4.

Do not blindly use a default value for precision operation.

This parameter must be commissioned from:

```text
actual yaw-rate noise
actual minimum useful rover rotation
straight-line correction tests
```

---

# 16. Important PX4 Finding — RO_SPEED_TH

PX4 also applies:

```text
RO_SPEED_TH
```

to measured rover speed.

Measured speed below the threshold may be treated as zero.

This matters for:

```text
terminal stop
very-low-speed control
settling
precision marking
```

Commission it from actual estimator/body-speed noise.

---

# 17. Differential Allocation Behavior

PX4 differential control may reduce achievable forward speed when requested speed + yaw demand cannot simultaneously fit within wheel/actuator limits.

Therefore:

```text
requested_speed
```

is not guaranteed to equal:

```text
achieved_speed
```

Record both.

This behavior is expected and must be considered when tuning RPP.

---

# 18. PX4 Mission / Position Rover Bug

An upstream PX4 v1.17 report exists where differential rover Mission/Position behavior fails to turn correctly on real hardware while direct rover speed/steering works.

This does not currently block DYX.

Reason:

```text
DYX does not delegate path navigation to PX4 Mission/Position control.
```

DYX RPP remains the path authority and sends native speed/rate intent.

Do not switch architecture because of PX4 Mission behavior.

---

# 19. uXRCE-DDS Reconnection — OPEN INVESTIGATION

Current upstream/user evidence indicates possible uXRCE-DDS recovery problems around:

```text
Agent starts after PX4
Agent restart
transport interruption
client Running/disconnected state
```

A relevant upstream issue is:

```text
PX4-Autopilot #27860
```

This must be checked against our exact pinned PX4 SHA.

Do not assume automatic reconnect works until hardware evidence proves it.

---

# 20. DDS Recovery Test Matrix

Before communication is considered production-ready test:

```text
PX4 boots before Agent
Agent boots before PX4

Agent killed
Agent restarted

Ethernet unplugged
Ethernet reconnected

companion reboot

PX4 reboot

XRCE process restart

long idle/reconnect
```

For each case verify:

```text
connection recovery
topic recovery
command recovery
telemetry recovery
system health transition
no stale movement
```

---

# 21. Firmware Flash Margin — OPEN

Previous FMUv6X build evidence showed approximately:

```text
99.7% flash usage
```

with only a very small remaining margin.

Do not add arbitrary firmware code to:

```text
px4_fmu-v6x_default
```

Production direction:

```text
create a DYX-specific FMUv6X product configuration
```

Remove only modules proven unnecessary.

Do not modify the stock default target simply to make the image fit.

---

# 22. Firmware Provenance

Previous CI/build investigation showed shallow/no-tag builds can produce incorrect firmware identity such as:

```text
PX4_GIT_TAG = v0.0.0
```

Production firmware artifacts must preserve:

```text
exact Git SHA
PX4 upstream/base SHA
PX4 version
Git tags/history required for identity
board target
ELF
PX4 firmware image
linker map
memory/size report
toolchain/container identity
```

A firmware binary without reliable provenance is not a production release.

---

# 23. Localization Is The First Precision Milestone

Do not implement/tune RPP first.

Required sequence:

```text
physical geometry
      ↓
PX4 estimator configuration
      ↓
GNSS / dual-heading validation
      ↓
estimated nozzle validation
      ↓
precision truth established
      ↓
RPP
```

If localization is wrong, RPP tuning against it is misleading.

---

# 24. Physical Coordinate Contract

Canonical vehicle body frame:

```text
X = Forward
Y = Right
Z = Down
```

Physical measurements are still required.

Do not invent them.

Required measurements include:

```text
body reference / CoG definition

FCU position
FCU orientation

IMU position

Master GNSS position
Slave GNSS position

Master→Slave baseline vector
baseline length
baseline orientation

wheel track
wheelbase
wheel radius where relevant
vehicle length/width

nozzle/control-point position
```

---

# 25. Master RTK Antenna = Nozzle

Production physical rule:

```text
MASTER RTK ANTENNA = NOZZLE CONTROL POINT
```

Therefore raw RTK-fixed Master GNSS position is the direct external measurement of the nozzle/control point.

This is extremely important for accuracy validation.

---

# 26. EKF Reference Versus Nozzle Truth

PX4 EKF state may represent a body/IMU/reference point after lever-arm correction.

Do not directly compare:

```text
raw Master antenna/nozzle position
```

against:

```text
EKF body position
```

during rotation.

They represent different physical points.

Correct conceptual comparison:

```text
P_nozzle_estimated
    =
P_body_estimated
    +
R(yaw) × body_to_nozzle_lever_arm
```

Then compare:

```text
P_nozzle_estimated
```

against:

```text
P_master_raw_RTK
```

with proper time alignment.

---

# 27. Important PX4 Geometry Parameters

Candidate production parameters include:

```text
EKF2_IMU_POS_X
EKF2_IMU_POS_Y
EKF2_IMU_POS_Z

EKF2_GPS_POS_X
EKF2_GPS_POS_Y
EKF2_GPS_POS_Z

SENS_BOARD_ROT
SENS_BOARD_X_OFF
SENS_BOARD_Y_OFF
SENS_BOARD_Z_OFF

RD_WHEEL_TRACK
```

Do not assign values until measured.

---

# 28. Dual GNSS Heading

PX4 GNSS yaw fusion uses the receiver-provided heading.

Relevant configuration includes:

```text
EKF2_GPS_CTRL
EKF2_GPS_YAW_OFF
```

The Master/Slave baseline geometry must be physically measured.

Do not assume:

```text
baseline points forward
```

unless verified.

Receiver model/configuration also matters.

---

# 29. Estimator Telemetry

Production estimator health uses available v1.17 DDS outputs including:

```text
/fmu/out/estimator_status_flags
/fmu/out/vehicle_gps_position
/fmu/out/vehicle_local_position
/fmu/out/vehicle_global_position
/fmu/out/vehicle_attitude
```

Do not assume stock v1.17 exposes:

```text
/fmu/out/estimator_status
/fmu/out/estimator_innovations
```

through DDS.

If numeric innovations later become necessary, prove the requirement before modifying firmware DDS exposure.

---

# 30. RTK Does Not Replace EKF

Production authority:

```text
PX4 EKF
```

remains the control-state estimator.

Raw Master RTK is used as:

```text
GNSS input
RTK/nozzle truth
commissioning evidence
accuracy validation
```

Do not directly drive RPP from raw GNSS merely because RTK FIX is available.

---

# 31. Pivot Is Not Yet Physically Proven

Source inspection shows PX4 can mathematically generate differential wheel action for:

```text
speed = 0
yaw_rate != 0
```

But production pivot still depends on:

```text
ESC reverse support
motor mapping
right/left direction
neutral/deadband
traction
friction
wheel track
vehicle mass
surface
```

Physical pivot tests are mandatory.

---

# 32. Pivot Walk

A differential rover may translate physically during pivot.

Estimator must report that real translation.

RPP must not assume pivot is perfectly stationary.

Future RPP behavior:

```text
pivot completes
      ↓
fresh post-pivot estimator state
      ↓
re-anchor/recompute tracking geometry
      ↓
resume translation
```

Do not continue from a stale pre-pivot origin.

---

# 33. Backend Independence

Backend is pure Python and contains no `rclpy`.

Backend can remain online while:

```text
PX4 offline
DDS offline
estimator unavailable
RPP waiting
```

These are separate health states.

Do not collapse them into one generic:

```text
ROVER OFFLINE
```

state.

---

# 34. System Gateway

`dyx_system_gateway` is the sole ROS↔backend boundary.

Backend shall not directly subscribe to ROS topics.

Frontend shall not directly communicate with ROS/PX4.

Control and telemetry remain separated.

---

# 35. Frontend Authority Rule

Frontend displays authoritative values.

It does not independently recalculate:

```text
cross-track error
along-track error
heading error
goal distance
final marking accuracy
autonomy safety state
```

If RPP says a value, frontend displays the RPP value.

If System Health says autonomy is blocked, frontend displays that result.

---

# 36. Recorder

Recorder is an independent production service.

Expected process model:

```text
dyx-recorder.service running

IDLE
↕
RECORDING
```

Frontend controls recording state, not the systemd process itself.

Recorder captures authoritative ROS/PX4/control evidence.

---

# 37. Accuracy Evidence

Final marking accuracy is not simply:

```text
RPP cross-track error
```

It must ultimately use surveyed truth and nozzle truth.

Required evidence includes:

```text
surveyed target
raw Master RTK/nozzle
estimated body
estimated nozzle
geometry
yaw
terminal stop
marking timestamp
time alignment
```

---

# 38. Old Rover Workspace Is Reference Only

Old/current 4WD prototype workspace:

```text
rover_ws
```

may be used as evidence.

It is not the architecture authority.

Do not blindly port its implementation.

The old stack used:

```text
Python ROS
MAVROS
velocity-vector Offboard
PX4-derived vector bearing
```

The new production architecture intentionally changes these areas.

---

# 39. Old Proven Behavior Can Still Be Evidence

The old rover may provide useful evidence for:

```text
field tuning
GNSS behavior
mission behavior
RPP formulas
terminal accuracy
pivot behavior
failure modes
```

Use it as evidence, not as source-of-truth architecture.

---

# 40. Agent Workflow

Primary engineering collaboration:

```text
Vetri
+
GPT
+
Claude Sonnet / Opus
```

Claude Sonnet/Opus are primary coding/review agents for:

```text
PX4 firmware
ROS2 C++
backend
frontend
```

Codex may be used for:

```text
source tracing
targeted implementation
tests
independent review
```

Agy is an instruction-following execution assistant.

Use Agy for:

```text
repository inspection
exact snippets
file operations
CI/status
controlled mechanical changes
```

Do not ask Agy to independently redesign safety/control architecture.

---

# 41. Commit Governance

Commit author:

```text
Vetri / Vetrivelan Velmurugan
```

Do not add:

```text
Agent:
AI:
ChatGPT:
Claude:
Codex:
Gemini:
```

attribution trailers.

Use normal conventional commit messages.

Example:

```text
docs(handoff): close architecture milestone and start firmware phase
```

---

# 42. Evidence-First Rule

Before changing PX4 source:

```text
1. identify exact behavior
2. inspect pinned source
3. inspect official PX4 docs
4. inspect relevant upstream issue/PR
5. reproduce or prove relevance
6. prepare minimal change
7. independent review
8. test
```

Do not patch PX4 because a forum comment suggests it.

---

# 43. No Unnecessary PX4 Forking

Prefer:

```text
PX4 configuration
PX4 parameters
existing native rover interface
companion-side implementation
```

before changing PX4 core source.

Firmware changes require evidence that the existing PX4 behavior cannot satisfy the production contract.

---

# 44. First Firmware Investigation

The first firmware-focused investigation is:

```text
uXRCE-DDS reconnect/recovery behavior
```

against the exact pinned SHA:

```text
d6f12ad1c4f70ad3230afd7d86e971421e02fef4
```

Trace:

```text
initial connection
Agent unavailable at PX4 startup
Agent appears later
Agent restart
transport disconnect
Ethernet reconnect
client state machine
automatic retry
```

Compare with relevant upstream issue:

```text
PX4-Autopilot #27860
```

Do not patch until exact applicability is proven.

---

# 45. First Hardware Communication Milestone

After source audit:

```text
Pixhawk 6X
   ↕ Ethernet
companion
   ↕
Micro XRCE-DDS Agent
   ↕
ROS 2
```

Test:

```text
PX4 first boot
Agent first boot
Agent kill/restart
Ethernet unplug/replug
PX4 reboot
companion reboot
DDS recovery
topic recovery
latency
jitter
message rates
```

This must be proven before calling communication production-ready.

---

# 46. Localization Milestone After Communication

Once DDS/Ethernet is stable:

```text
measure physical geometry
configure board/IMU/GPS offsets
configure dual-GNSS heading
validate RTK
validate EKF
transform EKF body → estimated nozzle
compare estimated nozzle → raw Master/nozzle
measure stationary/pivot/straight-line accuracy
```

Only after this can we establish the actual localization error budget.

---

# 47. RPP Comes Later

Do not begin production RPP implementation until:

```text
communication stable
estimator reliable
geometry measured
nozzle truth validated
yaw behavior characterized
speed behavior characterized
pivot behavior measured
```

Otherwise RPP will be tuned against unknown estimator/vehicle errors.

---

# 48. Known Open Items

The following remain intentionally open:

```text
Jetson vs Radxa final production selection

exact Ethernet carrier/hardware proof

vehicle body reference definition

IMU offset measurement

Master/Slave GNSS offsets

dual-GNSS baseline

wheel track measurement

wheelbase measurement

physical pivot behavior

RO_YAW_RATE_TH production value

RO_SPEED_TH production value

RPP tuning parameters

Motion Control command timeout

PX4 Offboard-loss timeout

telemetry freshness thresholds

DDS reconnect behavior

DYX-specific FMUv6X product target

final production firmware flash margin

recorder storage thresholds

final production accuracy acceptance thresholds
```

Do not invent these values.

---

# 49. Current Milestone State

```text
M1 — Repository / architecture skeleton          COMPLETE
M2 — Architecture decisions                     COMPLETE
M3 — Core interface contracts                   COMPLETE
M4 — System safety/health contract               COMPLETE
M5 — Backend telemetry contract                  COMPLETE
M6 — Recorder/evidence contract                  COMPLETE

Architecture/documentation phase                CLOSED

PX4 firmware source audit                        ACTIVE
PX4 Ethernet/uXRCE-DDS commissioning             NEXT
Vehicle geometry measurement                     PENDING
Estimator/localization commissioning             PENDING
ROS production implementation                    PENDING
RPP production implementation                    PENDING
Full rover field validation                      PENDING
```

---

# 50. Starting Point For Next Agent

Read in this order:

```text
1. docs/agents/Handoff_GPT.MD

2. docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md

3. docs/interfaces/px4_contract_v1.md

4. docs/interfaces/motion_setpoint.md

5. docs/hardware/vehicle_geometry_estimator_contract_v1.md

6. docs/interfaces/px4_companion_communication_v1.md

7. docs/interfaces/system_health_safety_contract_v1.md

8. docs/interfaces/backend_telemetry_contract_v1.md

9. docs/interfaces/recorder_evidence_contract_v1.md

10. CLAUDE.md
```

Then inspect the exact PX4 production repository and pinned source before proposing firmware changes.

---

# 51. Final Handoff Rule

Architecture planning is closed.

Do not reopen settled architecture unless:

```text
hardware evidence
source-code evidence
official PX4 behavior
or measured field evidence
```

demonstrates that a contract cannot be satisfied.

The next phase is evidence-driven implementation.

Immediate order:

```text
PX4 firmware source
      ↓
uXRCE-DDS / Ethernet
      ↓
hardware communication proof
      ↓
vehicle geometry
      ↓
PX4 estimator/localization
      ↓
nozzle truth validation
      ↓
ROS production control graph
      ↓
RPP
      ↓
full field commissioning
```

**END OF GPT HANDOFF**
