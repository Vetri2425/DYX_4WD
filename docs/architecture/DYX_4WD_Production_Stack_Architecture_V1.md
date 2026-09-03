# DYX 4WD Production Stack Architecture — V1

## 1. Purpose

This repository is the clean production rewrite for the DYX 4WD rover.

The current `rover_ws` is used only as a source of verified behavior, field-tested logic, formulas, safety rules, mission flow, and telemetry requirements.

We are not copying the current workspace structure.

The new stack must have clear ownership, clean package boundaries, predictable startup, independent services, a direct ROS2-to-PX4 DDS control path, runtime-tunable parameters, and a one-command production installer.

Main goals:

- C++ for all production ROS2 control nodes
- Python only for backend/API work
- no MAVROS in the final control path
- direct PX4 DDS communication
- RPP owns path correction and rotational intent
- PX4 owns estimation and inner physical control loops
- clean systemd service separation
- reproducible bag recording and run metadata
- runtime tuning without relaunch for normal controller parameters
- one-command install, upgrade, verify, and rollback workflow
- no tracked backup files
- all runtime configuration outside source code
- every production module testable independently

---

# 2. High-Level Stack

```text
DYX GCS
   |
   | REST + Socket.IO
   v
Python Backend
   |
   | Local IPC
   v
C++ System Gateway
   |
   v
ROS2 Production Graph
   |
   +--> Mission
   +--> Trajectory
   +--> RPP
   +--> Motion Control
   +--> RTK
   +--> Spray
   +--> Recorder
   |
   v
PX4 Gateway
   |
   | ROS2 / uXRCE-DDS / Ethernet
   v
PX4
   |
   +--> EKF
   +--> Rover inner controllers
   +--> Control allocation
   +--> Motors
```

---

# 3. Repository Structure

Repository name:

```text
DYX_4WD
```

Recommended root layout:

```text
DYX_4WD/
│
├── backend/
│   ├── pyproject.toml
│   ├── src/
│   │   └── dyx_backend/
│   │       ├── api/
│   │       ├── auth/
│   │       ├── mission/
│   │       ├── telemetry/
│   │       ├── realtime/
│   │       ├── rtk/
│   │       ├── storage/
│   │       ├── config/
│   │       └── main.py
│   └── tests/
│
├── ros2_ws/
│   └── src/
│       ├── dyx_interfaces/
│       ├── dyx_trajectory/
│       ├── dyx_mission/
│       ├── dyx_rpp/
│       ├── dyx_motion_control/
│       ├── dyx_px4_gateway/
│       ├── dyx_system_gateway/
│       ├── dyx_rtk/
│       ├── dyx_spray/
│       ├── dyx_recorder/
│       └── dyx_bringup/
│
├── config/
│   ├── vehicle/
│   ├── trajectory/
│   ├── mission/
│   ├── rpp/
│   ├── motion_control/
│   ├── px4/
│   ├── rtk/
│   ├── spray/
│   └── recorder/
│
├── deployment/
│   ├── systemd/
│   ├── network/
│   ├── udev/
│   └── scripts/
│
├── installer/
│   ├── install.sh
│   ├── uninstall.sh
│   ├── upgrade.sh
│   ├── verify.sh
│   ├── lib/
│   │   ├── common.sh
│   │   ├── os_check.sh
│   │   ├── dependencies.sh
│   │   ├── ros_install.sh
│   │   ├── backend_install.sh
│   │   ├── network_install.sh
│   │   ├── systemd_install.sh
│   │   ├── permissions.sh
│   │   └── health_check.sh
│   └── manifests/
│       └── production.manifest
│
├── tools/
│   ├── analysis/
│   ├── bag/
│   ├── field/
│   ├── replay/
│   └── migration/
│
├── docs/
│   ├── architecture/
│   ├── interfaces/
│   ├── safety/
│   ├── tuning/
│   ├── validation/
│   └── migration/
│
├── .github/
│   └── workflows/
│
├── README.md
├── ARCHITECTURE.md
└── .gitignore
```

Rules:

- no `.backup`, `.bak`, `.before_*` files
- Git history is the backup
- no bag files committed
- no logs committed
- no secrets committed
- no runtime-generated mission files committed
- no Python ROS nodes inside `ros2_ws/src`
- no ROS imports inside the backend

---

# 4. Backend

Location:

```text
backend/
```

Language:

```text
Python
```

Responsibilities:

- REST API
- Socket.IO
- authentication
- mission upload
- mission reporting
- telemetry delivery
- settings
- RTK configuration
- storage
- frontend communication

The backend must not:

- run `rclpy`
- own ROS executors
- command PX4 directly
- contain motor safety logic
- calculate steering
- calculate RPP corrections

Communication with ROS must happen only through:

```text
dyx_system_gateway
```

Preferred backend-to-gateway transport:

```text
Unix domain socket
```

or local gRPC if the API becomes large.

This boundary must stay local to the Jetson.

---

# 5. ROS2 Workspace

Location:

```text
ros2_ws/src/
```

All production ROS packages are C++ and built using:

```bash
colcon build
```

All packages must use:

```text
ament_cmake
```

No `ament_python` packages in the production ROS graph.

---

# 6. dyx_interfaces

Purpose:

Define shared ROS messages, services, and actions.

No control logic is allowed here.

Example structure:

```text
dyx_interfaces/
├── msg/
│   ├── MotionSetpoint.msg
│   ├── VehicleState.msg
│   ├── RppStatus.msg
│   ├── MissionState.msg
│   ├── PointResult.msg
│   ├── RtkStatus.msg
│   └── RecorderStatus.msg
│
├── srv/
│   ├── StartMission.srv
│   ├── PauseMission.srv
│   ├── ResumeMission.srv
│   ├── AbortMission.srv
│   ├── SkipPoint.srv
│   └── SetEmergencyStop.srv
│
└── action/
    └── ExecuteMission.action
```

---

# 7. dyx_trajectory

Authority:

```text
What path must the rover follow?
```

Responsibilities:

- surveyed target ingestion
- global-to-local conversion
- segment construction
- path generation
- approach geometry
- path validation
- path signature/version
- path metadata

Outputs:

```text
Path
Segment
Target geometry
```

Trajectory must not:

- command speed
- command yaw
- command yaw rate
- arm PX4
- decide mission state

---

# 8. dyx_mission

Authority:

```text
What target or segment is active now?
```

Responsibilities:

- mission lifecycle
- mission generation ID
- current target
- current segment
- start
- pause
- resume
- continue
- skip
- abort
- completion
- point status
- point journal
- marking lifecycle
- transition rules

Mission states should be explicit.

Example:

```text
IDLE
READY
STARTING
RUNNING
PAUSED
STOPPING
COMPLETED
ABORTED
FAILED
```

Per-point state:

```text
PENDING
ACTIVE
REACHED
MARKED
SKIPPED
FAILED
```

Mission Manager must not calculate steering or PX4 control commands.

---

# 9. dyx_rpp

Authority:

```text
How should the rover move to follow the active path?
```

This package owns the actual path-following intelligence.

Suggested internal structure:

```text
dyx_rpp/
├── include/dyx_rpp/
│   ├── geometry.hpp
│   ├── guidance.hpp
│   ├── tracking_error.hpp
│   ├── heading_controller.hpp
│   ├── yaw_rate_controller.hpp
│   ├── speed_controller.hpp
│   ├── pivot_controller.hpp
│   ├── terminal_controller.hpp
│   ├── stop_certificate.hpp
│   ├── motion_state_machine.hpp
│   └── rpp_node.hpp
│
├── src/
│   ├── geometry.cpp
│   ├── guidance.cpp
│   ├── tracking_error.cpp
│   ├── heading_controller.cpp
│   ├── yaw_rate_controller.cpp
│   ├── speed_controller.cpp
│   ├── pivot_controller.cpp
│   ├── terminal_controller.cpp
│   ├── stop_certificate.cpp
│   ├── motion_state_machine.cpp
│   └── rpp_node.cpp
│
└── test/
```

RPP owns:

- cross-track error
- along-track error
- goal distance
- desired path heading
- corrected heading
- heading error
- yaw correction
- desired yaw rate
- desired speed
- acceleration/deceleration request
- pivot entry
- pivot control
- pivot release
- terminal approach
- final stop decision
- stop certificate

RPP must produce one canonical command:

```text
MotionSetpoint
```

Example fields:

```text
timestamp
sequence
control_mode
speed_mps
heading_rad
yaw_rate_rad_s
valid
```

Control modes:

```text
STOP
SPEED_HEADING
SPEED_RATE
PIVOT_RATE
```

---

# 10. Control Ownership

The new 4WD stack must not use the current architecture where RPP publishes only an XY velocity vector and PX4 derives the desired rotation.

Old behavior:

```text
RPP
 |
 | N/E velocity vector
 v
PX4
 |
 +--> derive bearing
 +--> derive heading behavior
 +--> decide turning response
```

New behavior:

```text
RPP
 |
 +--> speed
 +--> heading intent
 +--> yaw-rate intent
 +--> control mode
 |
 v
PX4
 |
 +--> close speed loop
 +--> close yaw-rate/heading inner loop
 +--> differential motor allocation
```

RPP owns the path-level rotational decision.

PX4 owns the physical inner-loop execution.

---

# 11. Control Modes

## Normal straight/path tracking

```text
SPEED_HEADING
```

RPP commands:

```text
speed
heading
```

PX4 tracks the requested heading and speed.

## Curve or active steering correction

```text
SPEED_RATE
```

RPP commands:

```text
speed
yaw_rate
```

RPP owns the correction directly.

## Pivot

```text
PIVOT_RATE
```

RPP commands:

```text
speed = 0
yaw_rate = requested pivot rate
```

Desired final heading remains visible to RPP for taper and release.

## Stop

```text
STOP
```

Command:

```text
speed = 0
yaw_rate = 0
```

No ambiguity.

---

# 12. dyx_motion_control

Authority:

```text
Is the RPP command safe, current, valid, and inside limits?
```

This replaces names such as:

```text
cmd_vel_bridge
twist_to_setpoint
```

Those names describe message conversion, not responsibility.

Responsibilities:

- input validation
- command freshness
- finite-value checks
- mission-state gating
- emergency-stop gating
- speed limits
- yaw-rate limits
- acceleration limits
- command sequence validation
- stale-command watchdog
- fail-to-zero logic

Input:

```text
MotionSetpoint
```

Output:

```text
ValidatedMotionSetpoint
```

If any safety condition fails:

```text
speed = 0
yaw_rate = 0
mode = STOP
```

Motion Control must never create its own steering correction.

---

# 13. dyx_px4_gateway

Authority:

```text
Translate approved rover motion into PX4 DDS commands and return PX4 state.
```

This package replaces the MAVROS control path.

Responsibilities:

- PX4 DDS connectivity
- px4_msgs compatibility
- Offboard enable
- arm/disarm transport
- rover speed setpoints
- rover yaw-rate setpoints
- rover heading setpoints
- PX4 heartbeat
- timesync
- command acknowledgment
- failsafe state
- estimator state
- vehicle attitude
- local position
- global position
- raw GNSS
- vehicle status
- actuator status if needed

The package should expose a clean rover-level interface to the rest of ROS.

Other packages should not directly publish PX4 DDS topics unless explicitly approved.

---

# 14. PX4 Relationship

PX4 owns:

- IMU processing
- GNSS processing
- EKF
- attitude estimation
- local/global position estimation
- yaw-rate inner control
- heading inner control where used
- speed inner control
- differential-drive allocation
- actuator output
- hardware failsafes

PX4 must not independently decide:

- active waypoint
- path shape
- cross-track correction
- pivot strategy
- terminal strategy
- mission completion

Those belong above PX4.

---

# 15. Wheel Encoder Position

Wheel encoders are not a dependency for the first 4WD production stack.

The rover is expected to operate on:

- construction ground
- loose soil
- solar fields
- uneven terrain
- slopes
- mud
- gravel
- wheel-slip conditions

Primary estimation stack:

```text
RTK GNSS
+
IMU
+
PX4 EKF
```

Wheel encoder support may be evaluated later as an optional secondary velocity aid.

It must not become a required navigation source without field evidence.

---

# 16. dyx_rtk

Responsibilities:

```text
NTRIP
GGA
RTCM
RTCM validation
correction health
PX4 RTCM injection
RTK status
```

Suggested internal split:

```text
dyx_rtk/
├── ntrip_client
├── gga_provider
├── rtcm_parser
├── rtcm_transport
├── correction_health
└── rtk_node
```

RTK status must be structured and bag-recordable.

---

# 17. dyx_spray

Spray control stays independent from RPP.

Responsibilities:

- actuator command
- state
- command acknowledgment
- spray timing
- marking result
- hardware watchdog
- safe-off on fault

Mission Manager requests marking.

Spray Controller owns actuator execution.

---

# 18. dyx_system_gateway

This is the single ROS-to-backend boundary.

Responsibilities:

```text
Backend command
    ↓
validate
    ↓
ROS service/action

ROS telemetry
    ↓
canonical snapshot
    ↓
local IPC
    ↓
Backend
```

No backend code may subscribe directly to ROS.

No ROS control node may depend on FastAPI.

---

# 19. dyx_recorder

The recorder is a production component.

It must not remain a developer script.

Responsibilities:

- start automatically for field mission
- create run ID
- record required topics
- write mission metadata
- write software version
- write ROS Git SHA
- write PX4 Git SHA
- write parameter/config snapshot
- write timestamps
- write vehicle identity
- stop cleanly on mission end
- preserve evidence on crash where possible

Suggested output:

```text
runs/
└── 2026-09-03_143200_mission_001/
    ├── rosbag2/
    ├── manifest.json
    ├── config/
    ├── git_versions.json
    ├── mission.json
    └── summary.json
```

---

# 20. dyx_bringup

`dyx_bringup` is the only production ROS launch authority.

Recommended launch files:

```text
launch/
├── production.launch.xml
├── control.launch.xml
├── px4.launch.xml
├── rtk.launch.xml
├── recorder.launch.xml
└── simulation.launch.xml
```

Prefer XML launch files unless Python launch logic is genuinely required.

Runtime parameters belong in YAML files.

Do not hard-code tuning values in launch files.

---

# 21. Systemd Services

Production runs with four main services.

## Service 1 — `dyx-platform.service`

Purpose:

- network setup
- PX4 Ethernet readiness
- XRCE-DDS Agent startup if needed
- runtime folders
- permissions
- device preparation
- basic platform health

This starts first.

## Service 2 — `dyx-ros.service`

Starts:

```text
dyx_bringup production.launch.xml
```

Contains the complete production ROS graph:

```text
Trajectory
Mission
RPP
Motion Control
PX4 Gateway
System Gateway
RTK
Spray
```

This is the real rover control service.

## Service 3 — `dyx-backend.service`

Runs:

```text
FastAPI + Socket.IO
```

Depends on platform and ROS availability, but the ROS control system must remain safe even if the backend crashes.

## Service 4 — `dyx-recorder.service`

Runs independently from backend and control logic.

It should continue recording evidence even if the backend fails.

Dependency structure:

```text
dyx-platform
      |
      v
dyx-ros
   /     \
  v       v
backend  recorder
```

---

# 22. Network Layout

Target production topology:

```text
Jetson
├── PX4 Ethernet network
├── Tablet hotspot network
└── Optional 4G/WAN
```

These networks should remain separated.

PX4 DDS traffic should not be exposed to tablet or WAN networks.

Example:

```text
PX4 Ethernet:
192.168.10.x

Jetson hotspot:
192.168.20.x
```

Tablet communicates only with backend.

PX4 communicates only with Jetson.

---

# 23. Safety Authority

Safety must exist below the backend.

Backend emergency stop is only a request.

Final motion authority lives in the C++ ROS control plane and PX4.

Safety chain:

```text
Backend/GCS request
      ↓
System Gateway
      ↓
Mission state
      ↓
Motion Control
      ↓
PX4 Gateway
      ↓
PX4
```

Independent stop conditions include:

- stale RPP command
- stale estimator data
- PX4 disconnected
- Offboard lost
- mission disabled
- E-stop
- invalid command
- NaN/Inf
- command timeout
- gateway timeout
- control process failure

Fail state:

```text
speed = 0
yaw_rate = 0
```

---

# 24. Configuration Rules

Runtime settings must live under:

```text
config/
```

Example:

```text
config/rpp/production.yaml
config/motion_control/production.yaml
config/px4/production.yaml
config/rtk/production.yaml
```

Configuration must be grouped by ownership.

RPP parameters stay in RPP config.

PX4 gateway transport parameters stay in PX4 gateway config.

No duplicated parameter authority.

---

# 25. Testing Structure

Each C++ package gets its own:

```text
test/
```

Use:

```text
ament_cmake_gtest
```

Important unit-test areas:

```text
trajectory geometry
coordinate conversion
cross-track sign
along-track calculation
heading normalization
yaw-rate controller
pivot FSM
terminal controller
stop certificate
command timeout
safety gating
mission FSM
DDS mapping
RTCM parser
```

Separate integration tests:

```text
tests/integration/
```

Separate bag replay:

```text
tools/replay/
```

Field test results must never be mixed with source.

---

# 26. CI

Every pull request should run:

```text
colcon build
colcon test
clang-format check
clang-tidy where practical
backend unit tests
interface compatibility checks
```

CI must also reject:

```text
backup files
large bag files
secrets
generated build folders
runtime logs
```

---

# 27. Migration Rules

The current `rover_ws` is not migrated file-by-file.

Every component must pass through:

```text
Existing behavior
      ↓
Verify from source + bags
      ↓
Write explicit contract
      ↓
Implement clean C++ module
      ↓
Unit test
      ↓
Bag replay comparison
      ↓
Shadow test
      ↓
Field test
```

No blind Python-to-C++ translation.

---

# 28. Migration Order

## Phase 0 — Freeze Existing Evidence

Before changing control behavior:

- freeze current commit
- preserve best field bags
- preserve current PX4 version
- export active parameters
- document topic rates
- document mission flow
- document safety gates
- document RPP formulas
- document current terminal behavior

Output:

```text
docs/migration/current_behavior_contract.md
```

## Phase 1 — Create Clean Repository

Create only:

```text
directory structure
README
ARCHITECTURE.md
package skeletons
CI
.gitignore
systemd skeletons
installer skeleton
```

No old source copied yet.

## Phase 2 — Interfaces

Build `dyx_interfaces` first.

Freeze:

```text
MotionSetpoint
VehicleState
MissionState
RppStatus
PointResult
RTK status
services/actions
```

Everything else depends on these contracts.

## Phase 3 — PX4 Gateway Prototype

Verify direct PX4 v1.17 DDS control first.

Prove on hardware:

```text
speed + rate
speed + heading
zero-speed pivot
stop
arm/disarm
Offboard
telemetry
watchdog
```

Do this before porting the full RPP.

## Phase 4 — Motion Control

Implement:

```text
freshness
limits
zero fallback
mission gate
E-stop
command validation
```

Test independently.

## Phase 5 — Trajectory

Port only verified geometry.

Do not port old historical/unused paths.

Compare against known mission geometry.

## Phase 6 — RPP

Port in small modules:

```text
geometry
guidance
heading
yaw-rate
speed
pivot
terminal
stop
```

RPP is ported last among the control algorithms because its contract must target the new motion interface from day one.

## Phase 7 — Mission Manager

Move mission sequencing into clean C++ FSM.

Keep mission state independent from controller implementation.

## Phase 8 — RTK

Build new correction pipeline for the DDS-era PX4 interface.

Do not preserve MAVROS dependency.

## Phase 9 — Spray

Move spray command and result handling into clean independent package.

## Phase 10 — Backend Separation

Create new backend with no `rclpy`.

Connect through `dyx_system_gateway`.

Keep existing frontend API compatibility where useful, but do not preserve bad backend internals.

## Phase 11 — Recorder

Create production recorder and manifest system.

A field run without provenance should be treated as incomplete evidence.

## Phase 12 — Systemd / Production Startup

Install and validate all four services:

```text
dyx-platform
dyx-ros
dyx-backend
dyx-recorder
```

Verify:

```text
restart
power loss
backend crash
ROS node crash
PX4 disconnect
network reconnect
storage failure
```

---

# 29. Production Authority Summary

```text
Trajectory
    owns path geometry

Mission
    owns active target and mission state

RPP
    owns path-following decision

Motion Control
    owns command validity and software safety gating

PX4 Gateway
    owns ROS/PX4 transport

PX4
    owns estimation and inner physical control

RTK
    owns correction delivery

Spray
    owns marking actuator execution

System Gateway
    owns Backend ↔ ROS boundary

Backend
    owns external API and UI-facing state

Recorder
    owns field evidence
```

No two modules should own the same decision.

---

# 30. Runtime Parameter Architecture

The new 4WD stack must support live runtime tuning for all control parameters that are safe to modify while the rover is running.

The old pattern:

```text
edit launch/config
    ↓
restart ROS
    ↓
test again
```

is not acceptable for normal tuning.

Target behavior:

```text
change parameter
    ↓
node receives update
    ↓
validate value
    ↓
apply immediately
    ↓
publish new active value
    ↓
record change in bag/manifest
```

No relaunch should be required for normal controller tuning.

---

# 31. ROS2 Parameter Ownership

Every ROS2 production package owns its own parameters.

Example:

```text
dyx_rpp
├── lookahead
├── cross_track_gain
├── heading_gain
├── yaw_rate_gain
├── yaw_rate_limit
├── pivot_rate
├── pivot_release_angle
├── terminal_speed
├── terminal_radius
├── deceleration
└── stop_settle_time
```

```text
dyx_motion_control
├── max_speed
├── max_yaw_rate
├── max_acceleration
├── max_deceleration
├── command_timeout
└── telemetry_timeout
```

```text
dyx_rtk
├── ntrip_timeout
├── reconnect_interval
├── gga_rate
└── correction_timeout
```

Parameters must not be duplicated between packages.

There must always be one clear parameter authority.

---

# 32. Parameter Classes

Parameters should be divided into three classes.

## LIVE

Safe to modify while the rover is operating.

Example:

```text
RPP gains
lookahead
speed limits
yaw-rate limits
terminal thresholds
pivot tuning
```

These update immediately.

## IDLE_ONLY

Can be changed without restarting ROS, but only while the rover is not executing a mission.

Example:

```text
vehicle geometry
antenna offsets
wheelbase
control-mode defaults
some safety limits
```

If a change is requested during a mission:

```text
reject parameter update
+
return reason
```

## RESTART_REQUIRED

Infrastructure parameters that should not be changed dynamically.

Example:

```text
PX4 IP address
DDS transport configuration
network interface
ROS domain ID
backend port
filesystem locations
```

These are clearly marked as restart-required.

---

# 33. Parameter Validation

Every parameter callback must validate the requested value before accepting it.

Example:

```text
requested:
yaw_rate_limit = 5.0 rad/s

validator:
allowed = 0.0 ... 1.0

result:
REJECT
```

No unsafe parameter should silently enter the control loop.

Validation includes:

```text
range
finite value
cross-parameter consistency
mission-state restrictions
vehicle limits
```

---

# 34. Runtime Parameter API

The GCS should eventually be able to tune approved parameters through:

```text
GCS
 ↓
Backend
 ↓
System Gateway
 ↓
ROS2 parameter service
 ↓
Owning node
```

Backend does not store its own control copy as the runtime authority.

The active ROS node remains authoritative.

The API should support:

```text
GET active parameters
SET parameter
SET multiple parameters atomically
RESET parameter
LOAD profile
SAVE profile
```

---

# 35. Parameter Profiles

Production tuning should use named profiles.

Example:

```text
config/rpp/
├── production.yaml
├── rugged_field.yaml
├── precision_test.yaml
└── development.yaml
```

The active runtime values may differ temporarily from the file while tuning.

When tuning is approved:

```text
runtime values
     ↓
explicit SAVE
     ↓
profile YAML
```

Never automatically overwrite production configuration because somebody changed a live value.

---

# 36. Parameter Change Audit

Every runtime parameter change must be observable.

Record:

```text
timestamp
node
parameter
old value
new value
source
mission ID
accepted/rejected
```

Example:

```text
14:22:31.281
dyx_rpp
yaw_rate_limit
0.35 → 0.30
source=GCS
mission=mission_0042
accepted=true
```

This must be available in the bag or run manifest.

After a field test we must be able to answer:

```text
What exact parameters were active at this moment?
```

without guessing.

---

# 37. Runtime Snapshot

At the beginning of every mission the recorder captures:

```text
all ROS2 parameters
PX4 parameters
software Git SHA
firmware Git SHA
configuration profile
network/runtime version
```

At mission end it captures the final state again.

This is mandatory for field evidence.

---

# 38. No-Restart Tuning Rule

For normal RPP/controller development, this workflow should work:

```bash
ros2 param set /dyx_rpp yaw_rate_limit 0.30
```

and the new value becomes active immediately if valid.

The GCS will later provide the same ability through the backend.

We should not need:

```text
edit YAML
kill launch
relaunch rover
```

for ordinary controller tuning.

---

# 39. Production Installer

The complete rover software must have a one-command installer.

Production setup must not depend on an engineer manually installing packages, copying service files, creating directories, setting permissions, or enabling systemd units.

Target experience:

```bash
sudo ./install.sh --production
```

A released build may later support an equivalent package/bootstrap command, but the source-of-truth installer remains auditable in the repository.

---

# 40. Installer Responsibilities

One installer owns the full machine setup.

It must:

```text
detect supported OS
detect architecture
verify Jetson compatibility
install apt dependencies
install ROS2 dependencies
install backend Python environment
install required DDS/XRCE components
build or install ROS2 workspace
install backend
install config files
create runtime directories
install systemd units
install udev rules
install network configuration
set permissions
create service user/group if required
enable services
run health checks
report installed version
```

No manual post-installation commands should be required for a standard production rover.

---

# 41. Production Filesystem

The Git repository should not itself be the production runtime location.

Installer creates a controlled filesystem such as:

```text
/opt/dyx/
├── current/
├── releases/
├── config/
└── bin/

/var/lib/dyx/
├── missions/
├── runs/
├── bags/
├── reports/
└── state/

/var/log/dyx/

/run/dyx/
```

Example:

```text
/opt/dyx/current
```

points to the currently active release.

This makes upgrade and rollback much cleaner.

---

# 42. Configuration Location

Production configuration should be separate from application binaries.

Example:

```text
/etc/dyx/
├── vehicle.yaml
├── rpp.yaml
├── motion_control.yaml
├── px4.yaml
├── rtk.yaml
├── recorder.yaml
└── backend.env
```

Secrets belong in protected configuration, not Git.

Example permissions:

```text
root:dyx
0640
```

---

# 43. Systemd Installation

Installer automatically installs:

```text
/etc/systemd/system/dyx-platform.service
/etc/systemd/system/dyx-ros.service
/etc/systemd/system/dyx-backend.service
/etc/systemd/system/dyx-recorder.service
```

Then automatically performs:

```bash
systemctl daemon-reload
systemctl enable dyx-platform
systemctl enable dyx-ros
systemctl enable dyx-backend
systemctl enable dyx-recorder
```

No engineer manually copies `.service` files.

---

# 44. Service Startup

After installation and reboot:

```text
Linux boots
   ↓
dyx-platform
   ↓
network / DDS / hardware ready
   ↓
dyx-ros
   ↓
control graph healthy
   ├─────────────┐
   ↓             ↓
dyx-backend   dyx-recorder
```

The rover should reach its normal READY state automatically.

No SSH session should be necessary just to start the rover.

---

# 45. Installation Verification

The installer must finish by running a real health check.

Example output:

```text
DYX 4WD Installation

Platform       PASS
ROS2           PASS
PX4 DDS        PASS
Backend        PASS
Recorder       PASS
RTK            READY
Systemd        PASS
Permissions    PASS

Version:
DYX Stack      1.0.0
Git SHA        abc1234
PX4 Contract   v1
```

If something fails, installation must return a non-zero exit code.

No false installation-success message when a required service is dead.

---

# 46. Installer Must Be Idempotent

Running:

```bash
sudo ./install.sh --production
```

twice must not corrupt the rover.

The installer checks existing state and updates only what is necessary.

It must safely handle:

```text
already-installed dependencies
existing service files
existing config
existing user
existing runtime directories
existing previous release
```

---

# 47. Upgrade Command

Production upgrade should eventually be:

```bash
sudo ./upgrade.sh <release>
```

or:

```bash
sudo dyx-update
```

Upgrade process:

```text
download/locate release
       ↓
verify checksum/version
       ↓
stop required services safely
       ↓
install new release
       ↓
verify
       ↓
switch current symlink
       ↓
start services
       ↓
health check
```

---

# 48. Rollback

Every upgrade must keep the previous known-good release.

Example:

```text
/opt/dyx/releases/
├── 1.0.0/
├── 1.1.0/
└── 1.2.0/

/opt/dyx/current -> 1.2.0
```

If 1.2.0 fails:

```bash
sudo dyx-rollback
```

switches back to:

```text
1.1.0
```

and restarts the services.

Production rover updates must always have a rollback path.

---

# 49. Release Artifact

CI should eventually produce one release package:

```text
dyx-4wd-1.0.0-arm64.tar.zst
```

containing:

```text
ROS2 install tree
backend package
installer
systemd files
default configuration
migration metadata
version manifest
checksums
```

Production machines should ideally install a tested release artifact rather than compile arbitrary source on the rover.

Development machines can still build from source.

---

# 50. Install Modes

Installer should support two clear modes.

## Development

```bash
sudo ./install.sh --dev
```

May:

```text
install compilers
install test dependencies
keep source tree
enable developer tools
```

## Production

```bash
sudo ./install.sh --production
```

Installs only what the rover needs to run.

No unnecessary compiler/debug packages where they are not required.

---

# 51. Version Command

Every production rover should support:

```bash
dyx-version
```

Example:

```text
DYX 4WD Stack: 1.0.0
Stack SHA:      3ab48fe
Build:          2026-09-03
ROS:            Humble
PX4 Firmware:   DYX-4WD-1.0.0
PX4 SHA:        93ab221
DDS Contract:   v1
Config Profile: production
```

This avoids ambiguity in field debugging.

---

# 52. Health Command

Also provide:

```bash
dyx-health
```

It should report:

```text
platform
ROS graph
RPP
motion control
PX4 gateway
DDS
PX4 connection
RTK
backend
recorder
disk space
network
```

This becomes the first command used during field troubleshooting.

---

# 53. Parameter Command

A small production utility should eventually provide:

```bash
dyx-param list rpp
dyx-param get rpp yaw_rate_limit
dyx-param set rpp yaw_rate_limit 0.30
dyx-param save rpp production
```

Internally this still uses the proper ROS2 parameter authority.

It is only a clean operator interface.

---

# 54. Production Deployment Principle

The new stack must satisfy both:

```text
Easy to tune
+
Easy to deploy
```

A controller that requires relaunch for every gain change is not production-friendly.

A stack that requires a developer to manually configure a new Jetson for several hours is not production-ready.

Expected production experience:

```text
Fresh supported Jetson
        ↓
install DYX release
        ↓
one command
        ↓
dependencies installed
ROS installed/configured
backend installed
DDS configured
services installed
network configured
permissions configured
        ↓
reboot
        ↓
rover comes READY automatically
```

This should feel like installing a product, not assembling a development workspace.

---

# 55. Updated First Milestones

## Milestone 1 — Architecture Skeleton

Create:

```text
repository structure
ARCHITECTURE.md
runtime parameter rules
installer skeleton
systemd skeleton
CI
package skeletons
```

## Milestone 2 — Interfaces and Parameter Contracts

Freeze:

```text
ROS interfaces
MotionSetpoint
VehicleState
parameter ownership
LIVE / IDLE_ONLY / RESTART_REQUIRED classifications
```

## Milestone 3 — Installer V0

Before major application development, prove:

```bash
sudo ./install.sh --dev
```

can install a clean test machine and create all four systemd services.

## Milestone 4 — PX4 DDS Gateway

Prove direct:

```text
speed
heading
yaw-rate
pivot
stop
arm/disarm
telemetry
```

## Milestone 5 — Live Parameter Tuning

Before RPP migration, prove a simple controller parameter can be changed live and:

```text
validated
applied
reported
recorded
```

without restarting the ROS graph.

Only then begin the full production RPP migration.

---

# 56. Final Build Order

The full engineering order should remain:

```text
1. Freeze current rover_ws evidence and field behavior
2. Create clean DYX_4WD repository
3. Freeze architecture and authority boundaries
4. Create package skeletons
5. Create installer and CI skeletons
6. Define dyx_interfaces
7. Define runtime parameter contracts
8. Build PX4 v1.17 DDS gateway proof
9. Prove speed + rate / speed + heading / pivot / stop
10. Build motion-control validation and watchdog layer
11. Port trajectory geometry
12. Port RPP as modular C++
13. Port mission FSM
14. Build RTK DDS-era pipeline
15. Build spray package
16. Build system gateway
17. Build pure Python backend
18. Build recorder + run manifest
19. Install four systemd services
20. Add one-command production release installer
21. Bag replay validation
22. Shadow validation
23. Hardware field validation
24. Freeze first production release
```

---

# 57. Non-Negotiable Rules

- RPP owns path-level speed and rotational intent.
- PX4 does not derive the full rover steering strategy from an XY velocity vector.
- PX4 owns estimator and inner-loop physical control.
- Backend never becomes safety authority.
- Backend never embeds ROS executors.
- No production Python ROS control nodes.
- Every tunable control parameter has one owner.
- Safe control parameters are live-tunable.
- Runtime changes are validated and recorded.
- No ordinary tuning change should require relaunch.
- Every mission captures exact software, firmware, config, and parameter state.
- No field bag without provenance is treated as authoritative evidence.
- Production startup is automatic after boot.
- Production installation is one command.
- Production upgrade has verification and rollback.
- No tracked backup copies.
- No MAVROS in the final control plane.
- Current `rover_ws` is evidence, not the architecture template.
- No blind Python-to-C++ translation.
- Every migrated behavior must be contract-tested against known evidence.
