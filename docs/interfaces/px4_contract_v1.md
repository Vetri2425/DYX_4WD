# DYX 4WD — PX4 v1.17 Production Control Contract V1

**Document status:** Production baseline contract  
**Scope:** DYX 4WD ROS 2 control stack ↔ PX4 differential-rover firmware  
**Firmware repository:** `Vetri2425/PX4-Autopilot-4WD-Prod-Baseline`  
**Production branch:** `dyx-4wd-production`  
**DYX firmware HEAD reviewed:** `ff5e216378465c10f6598dc5708e4480f70e9e90`  
**Pinned upstream PX4 baseline:** `v1.17.0`  
**Pinned upstream PX4 commit:** `d6f12ad1c4f70ad3230afd7d86e971421e02fef4`  
**Target board:** Holybro Pixhawk 6X / `px4_fmu-v6x_default`  
**Primary companion interface:** ROS 2 over uXRCE-DDS  
**Primary DYX control mode:** `SPEED_RATE`

---

## 1. Purpose

This document freezes the production-facing contract between the DYX 4WD ROS 2 stack and PX4 v1.17 differential-rover firmware before any rover-control firmware modification begins.

The primary design rule is:

> **DYX RPP owns where the rover should go and how it should correct. PX4 owns estimation, speed/yaw-rate inner-loop control, differential motor mixing, actuator execution, and firmware-level failsafe behavior.**

The contract intentionally avoids the legacy velocity-vector architecture in which PX4 derives a heading from an XY velocity vector.

No PX4 rover controller modification is authorized merely to reproduce behavior already supported by the native PX4 v1.17 rover interface.

---

## 2. Source-of-Truth Revisions

### 2.1 PX4 firmware

Pinned baseline:

```text
PX4 tag:       v1.17.0
PX4 commit:    d6f12ad1c4f70ad3230afd7d86e971421e02fef4
DYX branch:    dyx-4wd-production
DYX HEAD:      ff5e216378465c10f6598dc5708e4480f70e9e90
```

The DYX branch is exactly three commits ahead of the pinned v1.17.0 baseline and, at the time of this contract, contains CI/documentation changes only. No differential-rover controller, EKF, DDS topic mapping, board behavior, or actuator-control logic has been changed.

### 2.2 `px4_msgs`

Pin the ROS 2 workspace to:

```text
Repository: PX4/px4_msgs
Branch family: release/1.17
Commit: 86d8239e962f6939e05c3737784f60c02fa884db
```

The following required schemas were individually compared against the pinned PX4 v1.17.0 firmware source and are identical:

- `RoverSpeedSetpoint.msg`
- `RoverRateSetpoint.msg`
- `RoverAttitudeSetpoint.msg`
- `OffboardControlMode.msg`

Do not track floating `main` for production.

Any future `px4_msgs` update requires explicit schema-compatibility review against the pinned firmware before deployment.

---

## 3. Control Authority

| Responsibility | Authority |
|---|---|
| Surveyed target coordinates | Mission / Trajectory |
| Path geometry | `dyx_trajectory` |
| Cross-track error | `dyx_rpp` |
| Along-track error | `dyx_rpp` |
| Goal-distance logic | `dyx_rpp` |
| Desired heading | `dyx_rpp` |
| Heading error | `dyx_rpp` |
| Heading-to-yaw-rate correction | `dyx_rpp` |
| Desired yaw rate | `dyx_rpp` |
| Desired forward speed | `dyx_rpp` |
| Pivot enter/release decision | `dyx_rpp` |
| Terminal deceleration | `dyx_rpp` |
| Stop certificate | `dyx_rpp` / mission safety policy |
| Setpoint validation/freshness | `dyx_motion_control` + `dyx_px4_gateway` |
| Speed inner loop | PX4 |
| Yaw-rate inner loop | PX4 |
| Vehicle state estimation | PX4 EKF |
| Differential inverse kinematics | PX4 |
| Motor output generation | PX4 |
| Offboard connection-loss failsafe | PX4 |

### Prohibited authority duplication

PX4 must not independently re-plan the DYX path or generate RPP-style cross-track corrections.

DYX must not directly control wheel PWM or replace PX4's speed/yaw-rate feedback loops during normal production operation.

---

## 4. Primary Motion Contract: `SPEED_RATE`

The production RPP output is conceptually:

```cpp
struct DyxMotionSetpoint {
    uint64_t timestamp_us;
    float speed_mps;
    float yaw_rate_rad_s;
};
```

The gateway maps this semantic command to native PX4 rover messages.

### 4.1 Offboard control mode

For `SPEED_RATE`:

```text
OffboardControlMode.position          = false
OffboardControlMode.velocity          = true
OffboardControlMode.acceleration      = false
OffboardControlMode.attitude          = false
OffboardControlMode.body_rate         = false
OffboardControlMode.thrust_and_torque = false
OffboardControlMode.direct_actuator   = false
```

PX4 v1.17 explicitly documents `Speed + Rate` as a valid rover setpoint combination using the `velocity` control flag.

### 4.2 Required setpoints

Publish:

```text
RoverSpeedSetpoint.speed_body_x
RoverRateSetpoint.yaw_rate_setpoint
RoverAttitudeSetpoint.yaw_setpoint = NaN
```

The `NaN` attitude setpoint is mandatory for this contract because PX4's rover hierarchy allows a higher-level attitude controller to generate its own rate setpoint. Publishing `NaN` prevents the attitude path from overriding the DYX yaw-rate command.

### 4.3 Differential-rover speed message

Pinned schema:

```text
uint64 timestamp
float32 speed_body_x
float32 speed_body_y
```

For DYX differential rover:

```text
speed_body_x = requested longitudinal speed [m/s]
speed_body_y = NaN
```

`speed_body_x` is positive forward and negative backward.

Normal autonomous DYX operation shall not command reverse unless a future reviewed mission/control contract explicitly enables it.

### 4.4 Differential-rover rate message

Pinned schema:

```text
uint64 timestamp
float32 yaw_rate_setpoint
```

Units:

```text
rad/s
```

The DYX RPP command must use the PX4/NED yaw-rate sign convention consistently.

A hardware sign-verification test is mandatory before production driving.

---

> **Architecture V1 compatibility note:** The frozen architecture originally
> defined `STOP`, `SPEED_HEADING`, `SPEED_RATE`, and `PIVOT_RATE`.
> After the pinned PX4 v1.17 source audit, production V1 resolves ADR-0004 OQ-1
> by using `SPEED_RATE` as the single active driving transport/control mode.
> `SPEED_HEADING` remains reserved at the DYX interface level but is not used
> for production V1 rover execution. RPP retains heading intent internally and
> emits `(speed, yaw_rate)` commands.

## 5. PX4 Differential Control Chain

The pinned PX4 source shows the control chain:

```text
RoverSpeedSetpoint
        ↓
DifferentialSpeedControl
        ↓
RoverThrottleSetpoint
        ↓
DifferentialActControl
        ↓
actuator_motors

RoverRateSetpoint
        ↓
DifferentialRateControl
        ↓
RoverSteeringSetpoint
        ↓
DifferentialActControl
        ↓
actuator_motors
```

The main `RoverDifferential` module is scheduled at:

```text
100 Hz
```

and conditionally runs the enabled controller layers from `VehicleControlMode`.

### 5.1 Speed loop

`DifferentialSpeedControl`:

- consumes `RoverSpeedSetpoint.speed_body_x`;
- estimates body-frame vehicle speed from PX4 attitude and local velocity;
- applies PX4 speed feedback/feed-forward logic;
- publishes `RoverThrottleSetpoint`.

Relevant parameters include:

```text
RO_SPEED_P
RO_SPEED_I
RO_SPEED_TH
RO_SPEED_LIM
RO_MAX_THR_SPEED
RO_ACCEL_LIM
RO_DECEL_LIM
RO_JERK_LIM
```

Parameter values are not frozen by this interface contract. Tuning requires hardware evidence.

### 5.2 Yaw-rate loop

`DifferentialRateControl`:

- consumes `RoverRateSetpoint.yaw_rate_setpoint`;
- measures yaw rate from `vehicle_angular_velocity.xyz[2]`;
- applies deadband, slew limiting, feed-forward and PID control;
- publishes normalized steering / wheel-speed-difference intent.

Relevant parameters include:

```text
RO_YAW_RATE_P
RO_YAW_RATE_I
RO_YAW_RATE_TH
RO_YAW_RATE_CORR
RO_YAW_ACCEL_LIM
RO_YAW_DECEL_LIM
RD_WHEEL_TRACK
RO_MAX_THR_SPEED
```

Again, this contract freezes ownership and message semantics, not tune values.

---

## 6. Differential Inverse Kinematics

PX4 differential actuator control uses the equivalent relationship:

```text
left  = throttle - speed_difference
right = throttle + speed_difference
```

If combined demand exceeds normalized actuator limits, PX4 prioritizes yaw-rate authority by reducing throttle.

This is desirable for DYX precision guidance because steering/yaw correction is not silently sacrificed to maintain requested forward speed.

---

## 7. True Pivot Contract

DYX pivot command:

```text
speed_mps       = 0.0
yaw_rate_rad_s != 0.0
```

The PX4 control chain produces zero longitudinal throttle with opposite left/right wheel demand.

Idealized result:

```text
throttle = 0
steering = D

left  = -D
right = +D
```

This is true differential spot-turn kinematics.

### 7.1 Reversibility prerequisite

PX4 differential-rover defaults set:

```text
CA_AIRFRAME = 6
CA_R_REV    = 3
```

which marks the left and right rover motors reversible.

### 7.2 Hardware acceptance requirement

Source-level support is **not** sufficient to certify the physical rover.

Before production acceptance, verify:

```text
Positive yaw-rate command:
  one side reverses
  opposite side drives forward
  rover rotates with negligible commanded translation

Negative yaw-rate command:
  wheel directions swap
  rover rotates opposite direction
```

Also verify ESC/driver reverse support, neutral/deadband behavior, PWM or DShot configuration, drivetrain friction, and minimum controllable yaw rate.

Until this test passes, "true pivot" is architecturally supported but not hardware-certified.

---

## 8. Stop Contract

Normal commanded stop:

```text
speed_mps      = 0.0
yaw_rate_rad_s = 0.0
```

This must map to:

```text
RoverSpeedSetpoint.speed_body_x       = 0.0
RoverRateSetpoint.yaw_rate_setpoint   = 0.0
RoverAttitudeSetpoint.yaw_setpoint    = NaN
```

DYX stop certification may require additional conditions such as measured speed, measured yaw rate, position error and settle time. Those conditions belong to DYX RPP/mission policy and are not replaced by PX4 simply accepting zero setpoints.

---

## 9. Deprecated Trajectory-Vector Path — PROHIBITED

Do not use `TrajectorySetpoint` as the production DYX rover motion interface.

PX4 v1.17 marks the rover `TrajectorySetpoint` path deprecated in favor of native rover setpoints.

Its compatibility adapter can convert XY velocity into:

```text
speed = norm(velocity_ned)
yaw   = atan2(East, North)
```

That gives PX4 directional authority from a velocity vector, which violates the DYX architecture.

Production DYX control must therefore not use `/fmu/in/trajectory_setpoint` for rover movement.

---

## 10. DDS Topics

The pinned PX4 v1.17 `dds_topics.yaml` exposes these native rover input topics:

```text
/fmu/in/rover_position_setpoint
/fmu/in/rover_speed_setpoint
/fmu/in/rover_attitude_setpoint
/fmu/in/rover_rate_setpoint
/fmu/in/rover_throttle_setpoint
/fmu/in/rover_steering_setpoint
```

The production gateway primarily uses:

```text
/fmu/in/offboard_control_mode
/fmu/in/rover_speed_setpoint
/fmu/in/rover_rate_setpoint
/fmu/in/rover_attitude_setpoint
/fmu/in/vehicle_command
```

Do not add custom DDS rover motion messages unless a verified native-interface limitation is found that cannot be solved safely within the existing contract.

---

## 11. Telemetry Required by `dyx_px4_gateway`

At minimum the production gateway should consume/expose:

```text
/fmu/out/vehicle_status
/fmu/out/vehicle_control_mode
/fmu/out/vehicle_attitude
/fmu/out/vehicle_local_position
/fmu/out/vehicle_global_position
/fmu/out/vehicle_gps_position
/fmu/out/vehicle_odometry
/fmu/out/vehicle_command_ack
/fmu/out/failsafe_flags
/fmu/out/estimator_status_flags
/fmu/out/timesync_status
```

### Estimator / GNSS health authority

The pinned PX4 v1.17 DDS topic set exposes:

```text
/fmu/out/estimator_status_flags
```

but does not expose `estimator_status` or `estimator_innovations` by default.

`EstimatorStatusFlags` is the primary stock DDS estimator-health contract for V1.
Relevant fields include:

```text
cs_yaw_align
cs_gnss_pos
cs_gnss_vel
cs_gnss_yaw

cs_gnss_fault
cs_gnss_yaw_fault
cs_inertial_dead_reckoning

reject_hor_vel
reject_ver_vel
reject_hor_pos
reject_ver_pos
reject_yaw
```

`/fmu/out/vehicle_gps_position` is the primary receiver-level GNSS/RTK evidence source and includes:

```text
fix_type
eph
epv
satellites_used

heading
heading_accuracy
vel_ned_valid

jamming_state
spoofing_state

rtcm_injection_rate
rtcm_crc_failed
rtcm_msg_used
```

PX4 defines:

```text
fix_type = 5  -> RTK FLOAT
fix_type = 6  -> RTK FIXED
```

No firmware modification is required merely to obtain the above V1 estimator and GNSS health signals.

If later hardware evidence shows that numeric estimator innovations are required for a production safety gate or diagnosis, exposing additional estimator topics must be treated as a narrow reviewed DDS telemetry extension.

Where production diagnostics require the exact yaw-rate inner-loop measurement, either expose the appropriate native PX4 telemetry already available in the pinned firmware/DDS contract or add a narrowly reviewed diagnostic publication. Do not redesign motion authority merely for observability.

---

## 11A. DDS QoS Contract

The pinned PX4 v1.17 uXRCE-DDS implementation configures QoS by bridge direction rather than by individual rover topic.

### PX4 -> ROS 2 data writers

Pinned source configures:

```text
durability  = TRANSIENT_LOCAL
reliability = BEST_EFFORT
history     = KEEP_LAST
```

### ROS 2 -> PX4 data readers

Pinned source configures:

```text
durability  = VOLATILE
reliability = BEST_EFFORT
history     = KEEP_LAST
depth       = PX4 uORB queue-derived depth
```

There is no source-supported special production exception in this pinned v1.17 bridge that makes `VehicleCommand` Reliable + Transient Local.

Therefore `dyx_px4_gateway` must explicitly use QoS compatible with the pinned PX4 bridge rather than relying on generic ROS 2 defaults.

For ROS 2 publishers to `/fmu/in/*`, including:

```text
/fmu/in/offboard_control_mode
/fmu/in/rover_speed_setpoint
/fmu/in/rover_rate_setpoint
/fmu/in/rover_attitude_setpoint
/fmu/in/vehicle_command
```

the ROS-side publisher shall be compatible with:

```text
BEST_EFFORT
VOLATILE
KEEP_LAST
```

Motion command history shall remain small and latest-value oriented.
The gateway must not intentionally create a backlog of obsolete rover setpoints.

For ROS 2 subscribers to `/fmu/out/*`, the subscriber QoS must be compatible with PX4's Best Effort publications.

Exact ROS-side history depth is an implementation parameter and must be tested, but QoS choices must never silently prevent endpoint matching.

---

## 12. Offboard Heartbeat Contract

PX4 ROS 2 Offboard requires a continuous `OffboardControlMode` proof-of-life stream.

PX4 requirements include:

- heartbeat must be greater than 2 Hz;
- the stream must be active before entering Offboard/arming in Offboard;
- loss of heartbeat causes PX4 to exit Offboard after `COM_OF_LOSS_T`;
- resulting failsafe action depends on PX4 failsafe configuration, including `COM_OBL_RC_ACT`.

DYX shall publish `OffboardControlMode` at a deterministic rate substantially above 2 Hz.

The exact production publish rate belongs to the gateway timing specification, not this message-semantic contract.

---

## 13. Critical Setpoint-Freshness Rule

PX4's Offboard watchdog primarily monitors the Offboard proof-of-life stream.

The rover speed and rate controllers retain their latest finite setpoints until updated or reset.

Therefore the following condition is unsafe:

```text
RPP stops updating
+
PX4 gateway continues OffboardControlMode heartbeat
=
PX4 can continue using the previous motion command
```

### Mandatory DYX safety design

Use two independent protection layers.

#### Layer A — fast DYX command watchdog

`dyx_motion_control` and/or `dyx_px4_gateway` must validate:

- finite values;
- allowed magnitude;
- allowed control state;
- command timestamp/age;
- mission-enabled state;
- safety/estop state.

On stale or invalid command:

```text
speed = 0
yaw_rate = 0
```

Publish literal zero immediately according to the gateway's deterministic safety loop.

The exact timeout value must be separately reviewed and hardware-validated; this document intentionally does not invent one.

#### Layer B — PX4 Offboard connection-loss failsafe

If the companion/gateway itself is unhealthy or DDS connectivity is lost, stop satisfying the Offboard proof-of-life contract and allow PX4's `COM_OF_LOSS_T` failsafe to take authority.

This gives:

```text
RPP stale
    ↓
DYX fast fail-to-zero

Gateway/DDS lost
    ↓
PX4 Offboard-loss failsafe
```

---

## 14. ROS 2 Interface Library Decision

PX4 v1.17 documentation recommends the PX4 ROS 2 Interface Library as a convenience layer for rover setpoints.

However, the same v1.17 documentation marks that library **Experimental** and describes compatibility around corresponding moving branches.

For the DYX production baseline:

> **Do not make `px4_ros2_interface_lib` a required control-path dependency.**

Use:

```text
dyx_px4_gateway (C++)
        ↓
pinned px4_msgs
        ↓
native ROS 2 DDS topics
        ↓
uXRCE-DDS
        ↓
pinned PX4 firmware
```

This minimizes dependencies, keeps the interface auditable, and preserves deterministic versioning.

The interface library can be evaluated separately for tooling or non-critical capabilities, but inclusion in the production motion path requires a new ADR/review.

---

## 15. Ethernet / uXRCE-DDS Contract

The production architecture intends a dedicated Ethernet connection between companion computer and Pixhawk.

The firmware target already includes PX4 Ethernet and uXRCE-DDS support according to the baseline audit.

Before Milestone 4 hardware sign-off, verify on the exact Pixhawk 6X carrier/hardware combination:

- physical Ethernet interface availability;
- interface startup;
- IP addressing;
- uXRCE-DDS client transport;
- agent reachability;
- reconnect behavior;
- packet loss behavior;
- link-loss behavior;
- boot-order behavior;
- timestamp/timesync behavior;
- no fallback to an unintended serial control path.

Do not claim Ethernet production-ready solely because firmware config symbols are compiled.

---

## 16. Arm / Disarm / Offboard Sequencing

`dyx_px4_gateway` owns the narrow PX4 command interface.

Required high-level sequence:

```text
1. DDS link healthy
2. Required estimator/control health verified
3. Start valid OffboardControlMode heartbeat
4. Maintain heartbeat for PX4-required pre-entry interval
5. Request Offboard
6. Confirm PX4 vehicle state reports Offboard
7. Request arm when mission/safety policy permits
8. Confirm arm acknowledgement/state
9. Only then permit non-zero motion setpoints
```

Disarm, abort, estop, control-mode loss, stale command, invalid command, or failed mission authority must force the DYX command path toward zero before any higher-level recovery behavior.

Exact `VehicleCommand` constants and acknowledgement policy should be implemented from the pinned `px4_msgs` message definitions, not hard-coded undocumented integers.

---

## 17. NaN Rules

For the primary `SPEED_RATE` contract:

```text
RoverSpeedSetpoint.speed_body_x      = finite
RoverSpeedSetpoint.speed_body_y      = NaN
RoverRateSetpoint.yaw_rate_setpoint  = finite
RoverAttitudeSetpoint.yaw_setpoint   = NaN
```

Do not publish an old finite attitude setpoint while commanding rate control.

Do not rely on default-initialized zero where PX4 semantically requires `NaN` to disable a higher controller.

The gateway must explicitly initialize all message fields.

---

## 18. Finite-Value and Range Validation

Before publishing any motion command:

```text
isfinite(speed_mps) == true
isfinite(yaw_rate_rad_s) == true
```

Then enforce DYX-configured production limits.

Reject, clamp only where explicitly designed, or fail-to-zero according to `dyx_motion_control` policy.

NaN/Inf from upstream control code must never propagate as an accidental motor command.

The only intentional `NaN` in the primary control contract is the disabled higher-level setpoint field(s), such as `RoverAttitudeSetpoint.yaw_setpoint`.

---

## 19. Timing, Timestamp and Rate Ownership

### uXRCE-DDS timestamp synchronization

The pinned PX4 v1.17 configuration defines:

```text
UXRCE_DDS_SYNCT = 1
```

by default.

With timestamp synchronization enabled, `uxrce_dds_client` measures the offset between Agent OS time and PX4 time and applies that offset during DDS serialization/deserialization.

For production V1, `dyx_px4_gateway` shall therefore populate outgoing PX4 message timestamps from the ROS node clock in microseconds:

```cpp
msg.timestamp = node_clock_now_nanoseconds / 1000;
```

The gateway shall **not** maintain a second manual PX4 time-offset conversion based on `TimesyncStatus` while `UXRCE_DDS_SYNCT=1`.

`/fmu/out/timesync_status` remains useful for diagnostics and validation of bridge timing, but it is not the V1 per-setpoint timestamp conversion authority.

If `UXRCE_DDS_SYNCT` is ever disabled, timestamp handling becomes a contract change and must be explicitly redesigned and reviewed.

### Control rates

PX4 `RoverDifferential` runs its internal controller chain at 100 Hz.

This does **not** require RPP to run at 100 Hz, but the gateway/control pipeline must publish deterministically at a rate sufficient for smooth closed-loop operation and safety monitoring.

Production rate decisions must be benchmarked end-to-end over the actual Ethernet/uXRCE-DDS link.

Record at least:

- RPP calculation rate;
- motion-control validation rate;
- gateway setpoint publication rate;
- DDS transport delay;
- PX4 setpoint reception timing;
- PX4 measured speed/yaw-rate response;
- command-to-actuator latency;
- jitter;
- packet loss;
- timeout response.

Do not use old MAVROS 50 Hz constraints as the design limit for the new architecture.

---

## 20. Parameters Relevant to This Contract

### Differential geometry / reversibility

```text
RD_WHEEL_TRACK
CA_AIRFRAME
CA_R_REV
```

### Speed loop

```text
RO_SPEED_P
RO_SPEED_I
RO_SPEED_TH
RO_SPEED_LIM
RO_MAX_THR_SPEED
RO_ACCEL_LIM
RO_DECEL_LIM
RO_JERK_LIM
```

### Yaw / yaw-rate loop

```text
RO_YAW_P
RO_YAW_RATE_LIM
RO_YAW_RATE_P
RO_YAW_RATE_I
RO_YAW_RATE_TH
RO_YAW_RATE_CORR
RO_YAW_ACCEL_LIM
RO_YAW_DECEL_LIM
```

### PX4 Offboard failsafe

```text
COM_OF_LOSS_T
COM_OBL_RC_ACT
```

### GNSS / EKF2 contract-relevant parameters

The pinned PX4 v1.17 source defines the following estimator parameters that materially affect DYX GNSS position, RTK acceptance and heading behavior:

```text
EKF2_GPS_CTRL
EKF2_GPS_MODE
EKF2_GPS_DELAY

EKF2_GPS_P_NOISE
EKF2_GPS_P_GATE
EKF2_GPS_V_NOISE
EKF2_GPS_V_GATE

EKF2_GPS_YAW_OFF

EKF2_GPS_POS_X
EKF2_GPS_POS_Y
EKF2_GPS_POS_Z

EKF2_GPS_CHECK
EKF2_REQ_EPH
EKF2_REQ_EPV
EKF2_REQ_SACC
EKF2_REQ_NSATS
EKF2_REQ_PDOP
EKF2_REQ_HDRIFT
EKF2_REQ_VDRIFT
EKF2_REQ_FIX
EKF2_REQ_GPS_H

EKF2_GSF_TAS
```

`EKF2_GPS_CTRL` is a bitmask. In the pinned v1.17 source:

```text
bit 0 -> longitude/latitude fusion
bit 1 -> altitude fusion
bit 2 -> 3D velocity fusion
bit 3 -> dual-antenna heading fusion
```

For dual-antenna GNSS heading, the contract-relevant parameter is:

```text
EKF2_GPS_YAW_OFF
```

The pinned v1.17 source does **not** define:

```text
EKF2_GPS_POS_X_2
EKF2_GPS_POS_Y_2
EKF2_GPS_POS_Z_2
EKF2_GSF_TAS_DFLT
```

Those names must not be introduced into DYX production configuration unless a future PX4 baseline actually defines them.

### Magnetometer / yaw fallback parameters

If the production estimator configuration uses magnetometer heading or magnetometer-assisted yaw initialization, record and review at minimum:

```text
EKF2_MAG_TYPE
EKF2_MAG_GATE
EKF2_MAG_NOISE
EKF2_MAG_CHECK
EKF2_MAG_CHK_STR
EKF2_MAG_CHK_INC
EKF2_MAG_ACCLIM
```

The exact production values are configuration/tuning decisions and are not invented by this interface contract.

This document does not invent production tuning values.

Parameter tuning must be tied to test evidence and stored with run manifests.

---

## 21. Firmware Changes Allowed After This Contract

A PX4 firmware modification is justified only if hardware/source testing demonstrates that the native contract cannot satisfy a production requirement.

Examples of valid evidence:

- confirmed controller bug;
- unsafe stale-state behavior not safely containable in gateway/PX4 configuration;
- insufficient observability required for safety certification;
- proven pivot/motor-output defect;
- Ethernet/uXRCE-DDS platform defect;
- deterministic timing deficiency;
- missing rover-specific firmware health signal.

Do not customize firmware simply to move DYX guidance logic into PX4.

---

## 22. Firmware Changes Explicitly Out of Scope

Do not move the following into PX4:

```text
surveyed path construction
RPP lookahead logic
cross-track correction policy
along-track mission policy
marking-point sequencing
terminal stop certificate logic
mission journal
frontend/backend authority
spray/marking workflow
```

PX4 remains the vehicle-control and estimation layer, not the DYX mission/path planner.

---

## 23. Firmware Build Baseline Issues That Must Be Closed

### 23.1 Flash headroom

Current successful FMUv6X baseline build was reported at approximately:

```text
1,960,224 B / 1,920 KB
≈ 99.70%
```

This leaves insufficient production headroom for future firmware changes.

Create a DYX-specific FMUv6X product configuration rather than modifying the upstream default target.

Remove only modules verified unnecessary for this rover.

Retain enough margin for:

- safety fixes;
- DDS changes;
- diagnostics;
- future PX4 patch backports.

Exact minimum acceptable flash margin should be a reviewed release criterion.

### 23.2 Firmware provenance

Production builds must retain enough Git history/tags for firmware metadata to identify the true baseline.

A field ULog must not report ambiguous `v0.0.0` firmware identity.

Each production artifact set shall record:

```text
DYX firmware SHA
PX4 base SHA
PX4 tag
px4_msgs SHA
board target
toolchain/container identity
build timestamp
configuration identity
```

### 23.3 Retained build artifacts

Production CI should retain at least:

```text
.px4
.elf
linker .map
size/memory report
build_info / manifest
exact Git revisions
toolchain/container identity
```

---

## 24. Hardware Verification Matrix

Before freezing firmware behavior as production-qualified, execute at minimum:

### Test A — zero motion

```text
speed = 0
yaw_rate = 0
```

Expected: no commanded wheel motion.

### Test B — straight forward

```text
speed > 0
yaw_rate = 0
```

Verify requested vs measured speed, left/right output symmetry, overshoot and settle.

### Test C — positive constant yaw rate

```text
speed > 0
yaw_rate > 0
```

Verify measured yaw-rate tracking and motor differential.

### Test D — negative constant yaw rate

Same as Test C with opposite sign.

### Test E — positive pivot

```text
speed = 0
yaw_rate > 0
```

Verify true counter-rotation.

### Test F — negative pivot

```text
speed = 0
yaw_rate < 0
```

Verify opposite counter-rotation.

### Test G — tapered pivot

RPP reduces requested yaw rate as heading error approaches zero.

Verify no PX4-generated direction conflict, overshoot, deadband stall or uncontrolled integral carryover.

### Test H — terminal heading hold

Low positive speed + small RPP yaw-rate correction.

Verify heading control remains owned by RPP.

### Test I — RPP command stale while gateway remains alive

Expected: DYX watchdog sends literal zero quickly; PX4 does not continue old non-zero motion.

### Test J — DDS/agent/Ethernet loss

Expected: PX4 Offboard-loss behavior occurs according to configured failsafe.

### Test K — gateway process death

Verify physical stop/failsafe outcome.

### Test L — reboot/order recovery

Power-cycle PX4/companion in different sequences and verify no uncontrolled motion.

---

## 25. Required Logging for Every Control Test

Record:

```text
RPP desired speed
RPP desired yaw rate
RPP heading target
RPP heading error
RPP cross-track error
RPP along-track / remaining distance
gateway command timestamp
gateway command age
gateway safety state
PX4 vehicle status
PX4 control mode
PX4 local/global position
PX4 attitude
PX4 measured yaw rate
PX4 measured body speed
PX4 speed-controller status where available
PX4 rate-controller status where available
actuator motor outputs
DDS/link health
estop state
mission state
firmware SHA
ROS stack SHA
px4_msgs SHA
parameter snapshot
```

The production recorder should make these values attributable to one run ID.

---

## 26. Acceptance Rules

The native PX4 interface is accepted only when all of the following are true:

- direct pinned `px4_msgs` build succeeds;
- exact DDS topic mapping is verified on hardware;
- Offboard entry/exit is deterministic;
- speed command tracks correctly;
- yaw-rate command tracks correctly;
- zero-speed pivot physically counter-rotates;
- command sign conventions are verified;
- stale RPP command produces fast zero;
- gateway/DDS loss triggers safe PX4 behavior;
- no hidden attitude controller overrides RPP rate control;
- stop command produces physical stop;
- firmware and ROS revisions are logged;
- flash headroom meets release criterion.

Only after this test matrix should PX4 controller source modifications be considered.

---

## 27. Production Decision Summary

The frozen architectural decision is:

```text
DYX Mission / Trajectory
          ↓
      DYX RPP C++
  path + heading authority
  speed + yaw-rate command
          ↓
  DYX Motion Control C++
 validation + stale watchdog
          ↓
   DYX PX4 Gateway C++
 direct pinned px4_msgs
          ↓
       ROS 2 DDS
          ↓
      uXRCE-DDS
          ↓
     PX4 v1.17.0
 speed loop + yaw-rate loop
 differential inverse kinematics
 actuator execution + EKF
```

Primary operational command:

```text
SPEED_RATE
```

Normal tracking:

```text
speed = RPP speed command
yaw_rate = RPP correction command
```

Pivot:

```text
speed = 0
yaw_rate = RPP pivot command
```

Stop:

```text
speed = 0
yaw_rate = 0
```

Attitude setpoint during `SPEED_RATE`:

```text
yaw_setpoint = NaN
```

This keeps one clear steering authority throughout the motion lifecycle and avoids mode-switch oscillation between RPP and PX4 heading control.

---

## 28. Authoritative Source Index

All production implementation/review must refer to the pinned revisions above.

### PX4 source — pinned `d6f12ad1c4f70ad3230afd7d86e971421e02fef4`

1. `msg/RoverSpeedSetpoint.msg`
2. `msg/RoverRateSetpoint.msg`
3. `msg/RoverAttitudeSetpoint.msg`
4. `msg/OffboardControlMode.msg`
5. `src/modules/uxrce_dds_client/dds_topics.yaml`
6. `src/modules/rover_differential/RoverDifferential.cpp`
7. `src/modules/rover_differential/RoverDifferential.hpp`
8. `src/modules/rover_differential/DifferentialSpeedControl/DifferentialSpeedControl.cpp`
9. `src/modules/rover_differential/DifferentialSpeedControl/DifferentialSpeedControl.hpp`
10. `src/modules/rover_differential/DifferentialRateControl/DifferentialRateControl.cpp`
11. `src/modules/rover_differential/DifferentialRateControl/DifferentialRateControl.hpp`
12. `src/modules/rover_differential/DifferentialAttControl/DifferentialAttControl.cpp`
13. `src/modules/rover_differential/DifferentialActControl/DifferentialActControl.cpp`
14. `src/modules/rover_differential/DifferentialActControl/DifferentialActControl.hpp`
15. `src/modules/rover_differential/DifferentialDriveModes/DifferentialOffboardMode/DifferentialOffboardMode.cpp`
16. `src/modules/rover_differential/module.yaml`
17. `ROMFS/px4fmu_common/init.d/rc.rover_differential_defaults`
18. `src/modules/commander/commander_params.yaml`
19. `docs/en/flight_modes/offboard.md`
20. `docs/en/ros2/px4_ros2_interface_lib.md`
21. `docs/en/flight_modes_rover/api.md`
22. `docs/en/middleware/uxrce_dds.md`

### `px4_msgs` — pinned `86d8239e962f6939e05c3737784f60c02fa884db`

1. `msg/RoverSpeedSetpoint.msg`
2. `msg/RoverRateSetpoint.msg`
3. `msg/RoverAttitudeSetpoint.msg`
4. `msg/OffboardControlMode.msg`
5. `msg/VehicleCommand.msg`
6. `msg/VehicleCommandAck.msg`
7. `msg/VehicleStatus.msg`
8. `msg/VehicleControlMode.msg`
9. `msg/VehicleAttitude.msg`
10. `msg/VehicleLocalPosition.msg`
11. `msg/VehicleGlobalPosition.msg`
12. `msg/SensorGps.msg`
13. `msg/VehicleOdometry.msg`
14. `msg/FailsafeFlags.msg`
15. `msg/TimesyncStatus.msg`

---

## 29. Change-Control Rule

This document is a production contract.

Changes to any of the following require explicit review by Vetri + ChatGPT + Claude/Opus before implementation:

- PX4 baseline SHA;
- `px4_msgs` SHA;
- primary motion mode;
- control authority;
- DDS topic contract;
- NaN behavior;
- watchdog ownership;
- stop behavior;
- pivot semantics;
- direct actuator access;
- Offboard/failsafe sequence;
- PX4 ROS 2 Interface Library adoption;
- custom rover DDS messages;
- PX4 rover controller modifications.

Agy may collect evidence, run exact commands, build, test, scaffold, or apply explicitly reviewed mechanical edits. Agy must not independently redefine this contract.

Codex is secondary implementation/research support.

Claude Sonnet/Opus remain primary coding agents; Claude Opus is the preferred final independent production review for safety-critical control changes.

---

## 30. Current Status

**PX4 native rover-control contract:** source-verified  
**Primary command:** `SPEED_RATE`  
**Custom rover DDS message required:** no evidence of need  
**PX4 controller modification required:** no evidence yet  
**True pivot:** source-supported, hardware proof pending  
**Fast stale-command safety:** must be implemented in DYX gateway/control path  
**PX4 Offboard failsafe:** secondary independent safety layer  
**ROS 2 Interface Library:** not selected for production control path  
**Direct pinned `px4_msgs`:** selected  
**Ethernet/uXRCE-DDS:** firmware foundation present; hardware proof pending  
**Flash headroom:** unresolved release blocker  
**Firmware provenance:** unresolved release blocker  
**Next milestone:** build lean DYX FMUv6X target, correct firmware provenance, then execute native DDS rover-control hardware proof.

---

## 31. Evidence Notes

The following findings were verified directly against the pinned source during contract preparation:

- PX4 v1.17 native rover DDS inputs include speed, attitude, rate, throttle, steering and position setpoints.
- `RoverDifferential` is scheduled at 100 Hz.
- `DifferentialRateControl` consumes rover yaw-rate setpoint and measured `vehicle_angular_velocity.xyz[2]`.
- `DifferentialSpeedControl` consumes body-x speed and estimates body-frame speed from PX4 attitude/local velocity.
- `DifferentialActControl` computes left/right demand from throttle ± normalized speed difference and prioritizes yaw when saturated.
- `rc.rover_differential_defaults` sets `CA_R_REV=3` for reversible left/right motors.
- PX4 rover Offboard documentation explicitly supports `Speed + Rate` with `velocity=true` and requires a `NaN` attitude setpoint to prevent hierarchy override.
- PX4 Offboard proof-of-life is based on `OffboardControlMode`; the rover controllers themselves retain the last finite setpoint until updated/reset, requiring a DYX command-age watchdog.
- PX4's rover `TrajectorySetpoint` interface is deprecated and must not be the DYX production motion interface.
- PX4 ROS 2 Interface Library is documented as experimental in v1.17 and is not selected as a required production dependency.
- `px4_msgs` release/1.17 commit `86d8239e962f6939e05c3737784f60c02fa884db` matches the pinned firmware schemas for the four required control messages checked above.

---

# End of Contract
