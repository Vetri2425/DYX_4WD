# DYX 4WD — Recorder & Evidence Contract V1

**Status:** IMPLEMENTATION BASELINE
**Authority:** DYX 4WD Production Stack Architecture V1
**Classification:** DERIVED — NOT FROM V1 SPEC
**Purpose:** Define what the production recorder captures, how a mission/run is identified, what metadata is required for reproducibility, how recording is controlled, and how field evidence is structured without becoming part of the real-time control loop.

---

## 1. Recorder Role

`dyx_recorder` is the production evidence service.

Its responsibilities are:

```text
record approved ROS/PX4/control topics
record mission events
record configuration and version metadata
record system health transitions
record geometry/estimator configuration snapshot
record start/end manifests
provide deterministic run identity
expose recorder state to backend/frontend
```

The recorder is not a controller.

It shall not:

```text
generate steering
change RPP output
change MotionSetpoint
modify estimator state
authorize autonomous motion
replace Mission Manager
```

---

## 2. Service Model

The production service is:

```text
dyx-recorder.service
```

Recommended behavior:

```text
service process = normally running
recording state = IDLE / RECORDING / FINALIZING / ERROR
```

The frontend/backend should start and stop a recording session.

They should not normally start and stop the Linux systemd service itself.

This keeps recorder process health independent of recording state.

---

## 3. Recording State

Conceptual states:

```text
IDLE
STARTING
RECORDING
FINALIZING
COMPLETE
ERROR
```

Exact enum values shall be frozen during interface implementation.

Valid example:

```text
recorder_service_healthy = true
recorder_state = IDLE
```

This means the recorder is available but not currently capturing a run.

---

## 4. Run Identity

Every recording session must have a unique run identifier.

Conceptually:

```text
run_id
```

A run ID shall not depend only on:

```text
mission name
date string
frontend row number
```

A stable unique identifier shall be generated for every recording session.

Mission identity may be linked separately:

```text
mission_id
mission_name
```

---

## 5. Run Directory

A production run should be self-contained.

Conceptual layout:

```text
run_<run_id>/
├── manifest_start.json
├── manifest_end.json
├── rosbag/
├── events/
│   └── events.jsonl
├── config/
│   ├── ros_parameters_start.yaml
│   ├── ros_parameters_end.yaml
│   ├── vehicle_geometry.yaml
│   └── px4_parameters.params
└── evidence/
    └── summary.json
```

Exact filenames may be refined during implementation.

The structural requirement is that all evidence required to reproduce and audit the run remains grouped under one run ID.

---

## 6. No Junk Files

Production runs shall not accumulate uncontrolled temporary or duplicate files.

Forbidden examples:

```text
random mission.csv copies
backup.py
*_old
*_final2
temporary debug dumps
unrelated logs
duplicate bags
editor backups
credentials
```

Only explicitly defined evidence artifacts belong in the production run directory.

---

## 7. Recording Authority

The recorder shall capture authoritative data from the source layer where possible.

Preferred:

```text
ROS/PX4/control topics directly
```

Not preferred as sole evidence:

```text
frontend rendered telemetry
backend cached values
screenshots
```

Backend/frontend telemetry may be recorded additionally for end-to-end verification, but shall not replace authoritative ROS/PX4 evidence.

---

## 8. Recording Control Path

Recording commands shall follow:

```text
Frontend
   ↓
Backend
   ↓
System Gateway
   ↓
Recorder control interface
   ↓
dyx_recorder
```

Backend must not directly manipulate rosbag subprocesses outside the recorder contract.

---

## 9. Start Recording Request

A recording start request should conceptually include:

```text
requested_by
mission_id if known
mission_name if known
operator/session information if permitted
recording_profile
reason
```

The recorder generates or confirms:

```text
run_id
start_timestamp
active profile
storage path
```

---

## 10. Recording Start Acknowledgement

The recorder must distinguish:

```text
request received
```

from:

```text
recording actually active
```

A successful start acknowledgement shall occur only after the recorder verifies that required recording resources are active.

---

## 11. Recording Stop

Stop flow:

```text
stop requested
      ↓
stop accepting new normal samples
      ↓
flush pending data
      ↓
close bag safely
      ↓
write end manifest
      ↓
verify final files
      ↓
state = COMPLETE
```

The recorder must not report COMPLETE before finalization succeeds.

---

## 12. Recorder Crash

If the recorder process crashes during a mission:

```text
recorder_healthy = false
recorder_state = ERROR
```

The control graph shall not receive steering or motion commands from recorder failure.

Operational policy determines whether loss of required evidence should block or abort a production mission.

That policy shall be explicit and shall not be silently invented by the recorder.

---

## 13. Core Topic Categories

The recorder shall capture a defined allowlist.

Categories include:

```text
PX4 state
estimator/GNSS
mission
trajectory
RPP
motion control
PX4 gateway
system health
RTK
spray/marking
critical events
```

No wildcard "record everything" policy shall be used for production by default.

---

## 14. PX4 Telemetry Topics

The production evidence profile should include approved PX4 telemetry such as:

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

Any additional PX4 topic must have a documented reason.

---

## 15. PX4 Command Evidence

For command-path verification, the recorder should capture the final companion-side intent and relevant outgoing PX4 command topics where technically practical.

Relevant command evidence includes:

```text
MotionSetpoint
ValidatedMotionSetpoint
OffboardControlMode
RoverSpeedSetpoint
RoverRateSetpoint
RoverAttitudeSetpoint
VehicleCommand
```

This allows reconstruction of:

```text
RPP requested
Motion Control accepted
Gateway transmitted
PX4 state responded
```

---

## 16. Mission Evidence

Mission evidence should include:

```text
mission identity
mission lifecycle
active target identity
target sequence
target coordinates
point reached
point completed
point failed
point skipped
mission pause/resume
mission abort
mission complete
```

Target identity shall be stable.

The recorder shall not depend only on UI row order.

---

## 17. RPP Evidence

RPP evidence should include the exact control solution it used.

Conceptually:

```text
rpp_state
target_index
target identity

vehicle state used
current_speed_mps

desired_heading_rad
heading_error_rad

cross_track_error_m
along_track_remaining_m
goal_distance_m

requested_speed_mps
requested_yaw_rate_rad_s

control_mode
pivot_state
terminal_state
solution_valid
```

The recorder shall capture the authoritative published values, not recalculate them later when avoidable.

---

## 18. Motion Control Evidence

Record:

```text
source_sequence
requested_speed_mps
requested_yaw_rate_rad_s

applied_speed_mps
applied_yaw_rate_rad_s

accepted
reason_code
command_age
```

This is required to diagnose whether a field motion problem originated in:

```text
RPP
Motion Control
Gateway
PX4
physical rover
```

---

## 19. Geometry Evidence

Every run shall preserve the active vehicle geometry configuration.

At minimum:

```text
body reference definition
IMU offsets
FCU mounting orientation
Master RTK/nozzle offset
Slave antenna offset
dual-GNSS baseline
wheel track
wheelbase
wheel radii if configured
other geometry values used by production software
```

The canonical source is the active production geometry configuration.

---

## 20. Master Antenna / Nozzle Contract

Production rule:

```text
Master RTK antenna = nozzle control point
```

The recorder shall preserve this geometry declaration with every run.

If this physical arrangement changes, the geometry configuration/version must also change.

---

## 21. Estimator Configuration Evidence

Every production run shall preserve the PX4 estimator configuration required to reproduce localization behavior.

Relevant parameter families include:

```text
EKF2_GPS_*
EKF2_IMU_POS_*
EKF2_MAG_*
SENS_BOARD_*
relevant rover/control estimator parameters
```

The exact production allowlist shall be frozen during commissioning.

---

## 22. PX4 Parameter Snapshot

At run start, capture the required PX4 parameter snapshot.

At run end, capture again where feasible.

This allows detection of:

```text
parameter changed during run
wrong tuning profile
wrong GNSS lever arm
wrong estimator configuration
wrong rover configuration
```

---

## 23. ROS Parameter Snapshot

Every run shall preserve active ROS parameters for relevant production packages.

At minimum:

```text
dyx_trajectory
dyx_mission
dyx_rpp
dyx_motion_control
dyx_px4_gateway
dyx_rtk
dyx_spray
dyx_system_gateway
dyx_recorder
```

Exact parameter allowlist may be package-defined.

---

## 24. Git Evidence

Every run shall preserve software provenance.

At minimum:

```text
DYX_4WD Git commit SHA
branch or release identifier
dirty/clean working-tree state where relevant
```

Production release should normally run from a clean release state.

---

## 25. PX4 Firmware Evidence

Every run shall preserve PX4 identity.

At minimum:

```text
PX4 production firmware SHA
PX4 upstream/base SHA
firmware version
board target
build identity
```

Where available, release metadata should also include:

```text
toolchain/container identity
binary checksum
artifact release identifier
```

---

## 26. Companion Identity

Capture relevant companion information:

```text
device hostname
hardware platform
OS version
ROS distribution
architecture
DYX release version
```

The current architecture targets Jetson/Radxa class companion hardware.

Exact production board remains governed by the hardware ADR.

---

## 27. Time Evidence

The recorder shall preserve enough time information to align:

```text
PX4
ROS
backend
mission events
GNSS
control commands
```

The system shall not silently assume all clocks are identical.

The PX4 communication timestamp contract remains defined by:

```text
docs/interfaces/px4_contract_v1.md
docs/interfaces/px4_companion_communication_v1.md
```

---

## 28. Event Log

Important discrete transitions should be recorded separately from high-rate topic data.

Recommended format:

```text
events.jsonl
```

Each event should contain conceptually:

```text
timestamp
run_id
event_type
source
sequence
reason
mission_id
target identity if applicable
details
```

---

## 29. Mandatory Events

Record at least:

```text
recorder started
recorder stopped
recorder error

PX4 connected/disconnected
DDS healthy/unhealthy

estimator ready/lost
GNSS state change
RTK state change

mission loaded
mission started
mission paused
mission resumed
mission aborted
mission completed

target activated
target reached
target completed
target failed
target skipped

E-stop active/clear
failsafe active/clear

RPP ready/lost
RPP command stale

Motion Control rejected command
autonomy enabled/blocked

spray/marking command
spray/marking result

parameter change
```

---

## 30. Accuracy Evidence

Final marking accuracy must be reconstructable from recorded evidence.

The accuracy pipeline shall preserve enough data to calculate or verify:

```text
surveyed target truth
raw Master RTK/nozzle position
estimated body state
estimated nozzle position after geometry transform
final stop state
marking event
time alignment
```

Final accuracy shall not be based only on RPP path-tracking error.

---

## 31. Accuracy Reference Frames

The recorder must preserve frame information.

For example:

```text
raw Master GNSS/nozzle = global WGS84 point
PX4 EKF local position = estimator local frame
vehicle yaw = NED navigation yaw
geometry offsets = body FRD
```

Offline analysis must know how to transform between them.

---

## 32. Nozzle Position Reconstruction

For accuracy analysis:

```text
P_nozzle =
    P_body
    + R(yaw) * lever_arm_body_to_nozzle
```

The recorder shall preserve all inputs needed for this transformation.

Raw Master RTK/nozzle and estimated nozzle must be time-aligned before accuracy comparison.

---

## 33. Pivot Evidence

Pivot events require sufficient data to determine:

```text
pre-pivot body position
post-pivot body position
pre/post yaw
raw nozzle position
estimated nozzle position
pivot command
actual yaw rate
pivot duration
pivot translation / walk
```

This is required to characterize physical pivot walk.

---

## 34. Straight-Line Evidence

For localization commissioning and RPP validation, record enough data to evaluate:

```text
straight-line path tracking
cross-track error
heading error
speed stability
GNSS vs estimated nozzle position
body translation
yaw stability
```

---

## 35. Terminal Stop Evidence

For every point where terminal accuracy matters, record:

```text
target identity
target coordinates
terminal state entry
requested speed
requested yaw rate
actual speed
actual yaw rate
body estimate
raw Master/nozzle RTK
final marking time
final stop certificate/result
```

---

## 36. Spray / Marking Evidence

For marking missions, record:

```text
spray requested
spray allowed
spray active
spray completed
spray failure
target identity
timestamps
```

Marking evidence must be correlatable with vehicle/nozzle position.

---

## 37. Topic Rate Preservation

The recorder must not artificially downsample critical control evidence without explicit policy.

If source is:

```text
50 Hz
```

and that signal is required for control/latency analysis, recording should preserve adequate rate.

Exact storage/profile decisions shall be evidence-driven.

---

## 38. Storage Limits

Production recording must be bounded by storage policy.

The recorder shall monitor:

```text
free storage
current run size
recording write errors
filesystem availability
```

Exact minimum free-space thresholds are TBD until hardware/storage selection is frozen.

---

## 39. Low Storage

Low-storage behavior shall be explicit.

The recorder must not silently continue until filesystem failure.

Required behavior includes:

```text
publish warning/error
expose storage health
record event
prevent unsafe corruption of existing evidence
```

Whether low storage blocks mission start is an operational policy.

---

## 40. File Integrity

At finalization, the recorder should verify expected files exist and are readable.

Where appropriate, generate checksums.

Conceptually:

```text
filename
size
checksum
```

This allows later evidence-integrity verification.

---

## 41. Start Manifest

`manifest_start.json` should conceptually include:

```text
run_id
start time
mission identity
DYX Git SHA
PX4 firmware identity
ROS distribution
companion identity
recording profile
geometry config hash/version
ROS parameter snapshot identity
PX4 parameter snapshot identity
schema versions
```

---

## 42. End Manifest

`manifest_end.json` should conceptually include:

```text
run_id
end time
duration
final recorder state
mission final state
file inventory
bag size
event count
errors
parameter-change summary
software/config identity
checksums where used
```

---

## 43. Summary Evidence

A lightweight summary may contain:

```text
run_id
mission result
points completed
points failed
points skipped
max/mean relevant tracking metrics
recorder health
PX4 disconnect count
estimator loss count
RTK degradation count
safety events
```

This summary is for navigation.

It shall not replace raw authoritative evidence.

---

## 44. Recording Profiles

The recorder may support explicit profiles.

Examples:

```text
PRODUCTION
COMMISSIONING
DEBUG
```

Profiles must use an explicit allowlist.

`PRODUCTION` should contain only evidence required for safe production audit.

`COMMISSIONING` may include additional estimator/GNSS/control signals.

`DEBUG` may include temporary diagnostic topics but shall not become the production default.

---

## 45. Profile Selection

Recording profile selection shall be visible in run metadata.

The frontend shall not silently switch profiles.

Any profile change during operation should be audited or require a new run.

---

## 46. Frontend Controls

Frontend may expose:

```text
Recorder: ON / OFF
Profile
Run ID
Recording duration
Storage health
Recorder state
```

The frontend shall not directly manage rosbag files.

---

## 47. Backend Projection

Backend should expose recorder state such as:

```text
recorder_healthy
recorder_state
run_id
recording_profile
recording_started_at
duration
storage_free
last_error
```

Backend transports this state.

Recorder remains its authority.

---

## 48. Auto Recording Policy

Whether production missions automatically start recording is an operational decision.

Permitted future policy:

```text
mission start
      ↓
verify recorder available
      ↓
start recording
      ↓
mission active
```

This document does not force auto-start until operational policy is frozen.

---

## 49. Recorder and Safety

Recorder is not a real-time safety controller.

However:

```text
recorder failure
```

may affect whether a mission is permitted if production policy requires evidence recording.

That decision belongs to system safety/operational policy.

The recorder itself must not command movement.

---

## 50. Reconnection

If the recorder control client disconnects:

```text
backend/frontend disconnect
```

an active recording shall not automatically stop unless explicitly required by policy.

Recording ownership shall be held locally by the recorder process.

---

## 51. Backend Restart

Backend restart must not destroy an active recording.

Expected behavior:

```text
recorder continues
backend restarts
backend reconnects
backend receives current recorder state/run_id
frontend receives reconstructed state
```

---

## 52. System Gateway Restart

If recorder topic subscriptions depend on ROS and ROS/system gateway restarts:

```text
recorder must detect source loss
mark evidence gap
publish error/degraded state
```

It shall not fabricate missing data.

---

## 53. PX4 Disconnect

PX4 disconnect shall become recorded evidence.

The bag/event log shall preserve:

```text
disconnect time
reconnect time
affected telemetry
system health transition
mission reaction
```

---

## 54. Companion Reboot

After unexpected companion reboot, incomplete prior runs shall be detectable.

The recorder should support identifying:

```text
unclean shutdown
incomplete manifest
partial bag
```

Recovery tooling may finalize or mark such runs as incomplete.

It shall never silently label incomplete data as a complete production run.

---

## 55. Data Retention

Retention policy shall be explicit.

Conceptually:

```text
production runs
commissioning runs
debug runs
```

may have different retention requirements.

The recorder shall not automatically delete production evidence without an approved retention policy.

---

## 56. Export

Future tooling may support exporting a complete run.

Export shall preserve:

```text
manifest
bag
events
configuration
version identity
checksums
```

Partial export must be clearly labeled.

---

## 57. Privacy and Credentials

Recorder output shall not include:

```text
passwords
API tokens
SSH keys
NTRIP credentials
authentication secrets
private certificates
```

Configuration snapshots must redact or exclude secrets.

---

## 58. Repository Hygiene

Rosbags and field evidence shall not be committed to the DYX_4WD source repository.

Production source repo shall exclude:

```text
bags
runtime logs
run directories
mission runtime artifacts
temporary recordings
credentials
```

---

## 59. Performance Isolation

Recording must not materially block the control graph.

Required design principles:

```text
bounded queues
non-blocking control publishers
separate recorder process
disk I/O isolation where practical
monitor write latency
monitor dropped messages
```

The RPP/Motion Control/PX4 Gateway path shall not wait on frontend or recorder disk writes.

---

## 60. Dropped Data

Recorder shall expose evidence when data loss occurs.

Conceptually:

```text
dropped_messages
queue_overruns
write_errors
disk_stall
```

A production run with significant evidence loss must be identifiable.

---

## 61. Required Commissioning Tests

Before production release test:

```text
start recording
stop recording
restart recording

backend restart during recording
frontend disconnect during recording
System Gateway restart
PX4 disconnect/reconnect

recorder process crash
disk near full
disk write failure
power loss / companion reboot

high-rate topic load
mission complete finalization
mission abort finalization

configuration snapshot correctness
Git SHA capture
PX4 firmware identity capture

parameter change detection
event ordering
time alignment
bag replay
run export/integrity
```

---

## 62. Evidence Acceptance

For every test, verify:

```text
run_id created
required files present
bag opens
required topics present
event file readable
manifest start/end consistent
Git SHA correct
PX4 identity correct
configuration snapshot correct
timestamps usable
no secret leakage
no unrelated junk files
```

---

## 63. Production Readiness Gate

Recorder/evidence remains:

```text
NOT COMMISSIONED
```

until:

```text
topic allowlist is frozen
recording profiles are frozen
run directory format is implemented
metadata capture is implemented
PX4/ROS parameter snapshots are verified
version provenance is verified
storage failure handling is tested
restart/crash handling is tested
bag replay is verified
accuracy evidence can be reconstructed
```

---

# Current Status

```text
Architecture authority            FROZEN
PX4 contract                      FROZEN
MotionSetpoint contract           FROZEN
Geometry/estimator contract       DEFINED
PX4 communication contract        DEFINED
System health/safety contract     DEFINED
Backend telemetry contract        DEFINED

Recorder/evidence contract        DEFINED BY THIS DOCUMENT

Recorder implementation           NOT STARTED
Topic allowlist                    NOT FROZEN
Profiles                           NOT FROZEN
Hardware storage testing           NOT STARTED
Replay/accuracy validation         NOT STARTED
```

This closes the planned core architecture-contract documentation set.
