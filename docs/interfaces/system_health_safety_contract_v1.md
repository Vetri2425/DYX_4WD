# DYX 4WD — System Health & Safety Contract V1

**Status:** IMPLEMENTATION BASELINE
**Authority:** DYX 4WD Production Stack Architecture V1
**Classification:** DERIVED — NOT FROM V1 SPEC
**Purpose:** Define how the production stack determines whether autonomous motion is permitted, how faults propagate, and how every invalid/stale condition fails toward zero motion.

---

## 1. Core Safety Question

The production stack shall always be able to answer:

```text
CAN_AUTONOMY_MOVE = true / false
```

No individual package may independently assume that the rover is safe to move.

The final motion boundary shall require all mandatory authorities to be valid.

---

## 2. Safety Principle

The fundamental rule is:

```text
UNKNOWN != SAFE
STALE   != SAFE
INVALID != SAFE

invalid / stale / unavailable
            ↓
          STOP
            ↓
speed_mps    = 0
yaw_rate     = 0
```

Loss of information shall never preserve an old movement command indefinitely.

---

## 3. Authority Separation

Health information originates from the component that owns the underlying truth.

```text
PX4
 └── vehicle / estimator / failsafe state

dyx_px4_gateway
 └── PX4/DDS communication health

dyx_rtk
 └── RTK transport/correction health

dyx_mission
 └── mission lifecycle and active-target validity

dyx_rpp
 └── guidance/control solution validity

dyx_motion_control
 └── final companion-side motion acceptance

hardware safety input
 └── E-stop / physical safety state

dyx_system_gateway
 └── projects authoritative states outward

backend
 └── transports state to frontend
```

Backend does not decide whether motion is safe.

Frontend does not decide whether motion is safe.

---

## 4. Safety Layers

DYX uses multiple independent safety layers.

```text
Mission authority
       ↓
Estimator / localisation readiness
       ↓
RPP command validity
       ↓
Motion Control validation
       ↓
PX4 Gateway freshness
       ↓
PX4 Offboard failsafe
       ↓
PX4 actuator control
```

Failure at any required layer shall prevent autonomous motion.

---

## 5. System Health State

The system shall expose a consolidated health model.

Conceptual fields:

```text
system_online
platform_ready
ros_ready

px4_connected
dds_healthy
px4_telemetry_fresh

estimator_ready
gnss_ready
rtk_ready

mission_ready
rpp_ready
motion_control_ready

estop_clear
failsafe_clear

control_authority_ready
autonomy_move_allowed
```

Exact ROS message schemas are defined during `dyx_interfaces` implementation.

---

## 6. `autonomy_move_allowed`

Conceptually:

```text
autonomy_move_allowed =
    platform_ready
    AND ros_ready
    AND px4_connected
    AND dds_healthy
    AND px4_telemetry_fresh
    AND estimator_ready
    AND localisation_policy_passed
    AND mission_ready
    AND rpp_ready
    AND motion_control_ready
    AND estop_clear
    AND failsafe_clear
    AND command_fresh
```

This is a logical contract, not executable code.

Additional mandatory conditions may be introduced when supported by verified requirements.

Conditions shall not be silently removed.

---

## 7. Estimator Readiness

`estimator_ready=true` shall mean more than:

```text
vehicle_local_position topic exists
```

It requires validated estimator state.

Relevant PX4 evidence includes:

```text
vehicle_attitude
vehicle_local_position
vehicle_global_position
vehicle_gps_position
estimator_status_flags
vehicle_status
failsafe_flags
```

Exact production localisation acceptance criteria are not frozen here.

They must be established by estimator commissioning and hardware evidence.

Until then:

```text
localisation production acceptance = TBD
```

---

## 8. RTK Policy

RTK health and estimator health are related but distinct.

Conceptually:

```text
RTK corrections healthy
        ↓
GNSS solution quality
        ↓
PX4 EKF fusion
        ↓
estimated vehicle state
```

`dyx_rtk` may report correction transport health.

PX4 remains the state-estimation authority.

No external node shall replace PX4 EKF position with raw GNSS position inside the control loop.

---

## 9. Master/Nozzle Accuracy Truth

For commissioning and final accuracy evidence:

```text
Master RTK antenna = Nozzle control point
```

Raw Master RTK position may therefore be used as an external measurement of nozzle position when the GNSS solution satisfies the required quality policy.

This does not make raw GNSS the autonomous control-state authority.

Control state remains:

```text
PX4 EKF
```

Accuracy evidence and control-state authority must remain separate.

---

## 10. Communication Health

The communication contract is defined by:

```text
docs/interfaces/px4_companion_communication_v1.md
```

Communication health shall distinguish at minimum:

```text
DISCONNECTED
TRANSPORT_READY
DDS_DISCOVERED
TELEMETRY_VALID
ESTIMATOR_READY
CONTROL_AVAILABLE
```

DDS discovery alone does not authorize motion.

---

## 11. Mission Authority

Mission Manager owns mission lifecycle.

Conceptual states may include:

```text
IDLE
LOADED
READY
ACTIVE
PAUSED
COMPLETED
ABORTED
FAILED
```

Exact state schema is defined during mission implementation.

Autonomous motion shall only be permitted in explicitly motion-authorized mission states.

For example:

```text
PAUSED
ABORTED
FAILED
COMPLETED
```

shall not produce continuing autonomous movement.

---

## 12. RPP Readiness

The RPP process may exist while control is unavailable.

Valid example:

```text
RPP process = RUNNING
RPP state   = WAITING_FOR_ESTIMATOR
```

RPP readiness requires valid inputs needed to calculate the current control solution.

RPP shall never treat missing/stale vehicle state as zero error.

Missing state means:

```text
NO VALID CONTROL SOLUTION
```

---

## 13. MotionSetpoint Validity

RPP outputs the frozen `MotionSetpoint` contract.

A command contains:

```text
timestamp_us
sequence
control_mode
speed_mps
heading_rad
yaw_rate_rad_s
valid
```

Production active modes:

```text
STOP
SPEED_RATE
PIVOT_RATE
```

`SPEED_HEADING` remains reserved for architecture compatibility and shall not be accepted as an active production V1 motion command.

---

## 14. Motion Control Safety Boundary

`dyx_motion_control` is the final semantic validator before the PX4 gateway.

It validates, at minimum:

```text
message freshness
valid flag
control mode
finite values
sequence/session validity

speed limits
yaw-rate limits
reverse policy

mission authority
safety authority
E-stop state

required system readiness
```

If validation fails:

```text
requested speed = 0
requested yaw rate = 0
accepted = false
```

Motion Control shall not invent steering corrections.

---

## 15. No Silent Command Reuse

A previously valid command shall not remain authoritative after its freshness window expires.

Forbidden behavior:

```text
RPP dies

last command:
speed = 1.0 m/s
yaw_rate = 0

gateway continues sending forever
```

Required behavior:

```text
command becomes stale
        ↓
companion detects stale command
        ↓
literal STOP
        ↓
speed = 0
yaw_rate = 0
```

Exact timeout:

```text
TBD — MEASURED RATE/JITTER REQUIRED
```

No arbitrary production timeout is frozen here.

---

## 16. PX4 Offboard Loss

Companion command freshness and PX4 Offboard-loss protection are separate safety layers.

### Layer A

```text
RPP / command failure
       ↓
Motion Control / Gateway watchdog
       ↓
STOP 0/0
```

### Layer B

```text
gateway / ROS / companion /
Ethernet / XRCE failure
       ↓
OffboardControlMode heartbeat disappears
       ↓
PX4 Offboard-loss handling
```

Both shall remain active.

---

## 17. E-Stop

E-stop is a highest-priority motion inhibitor.

Conceptually:

```text
estop_active == true
        ↓
autonomy_move_allowed = false
        ↓
STOP
```

Software shall not automatically clear a physical E-stop.

Recovery requires verified E-stop release and normal readiness revalidation.

---

## 18. PX4 Failsafe

PX4 remains authoritative for its internal failsafe mechanisms.

If PX4 reports a condition incompatible with autonomous operation:

```text
failsafe_clear = false
```

Companion software shall not attempt to defeat or hide PX4 failsafe state.

---

## 19. Startup Behaviour

At startup:

```text
autonomy_move_allowed = false
```

Components become ready independently.

Example:

```text
Backend                 READY
PX4                     DISCONNECTED
Estimator               UNAVAILABLE
RPP                     WAITING
Motion Control          STOP
Autonomy Move Allowed   FALSE
```

Later:

```text
PX4                     CONNECTED
DDS                     HEALTHY
Estimator               READY
Mission                 READY
RPP                     READY
Safety                  CLEAR
Motion Control          READY

Autonomy Move Allowed   TRUE
```

No readiness state shall be assumed before evidence exists.

---

## 20. PX4 Disconnect

If PX4 disconnects:

```text
px4_connected = false
autonomy_move_allowed = false
```

Backend shall remain operational.

Frontend shall continue to display the rover system and show PX4 as unavailable.

---

## 21. Estimator Loss During Motion

If required estimator state becomes invalid or stale while moving:

```text
estimator_ready = false
        ↓
autonomy_move_allowed = false
        ↓
STOP
```

RPP shall not dead-reckon autonomously using its own unofficial estimator.

Recovery requires estimator readiness to pass again.

Mission continuation policy is owned separately by Mission Manager.

---

## 22. RTK Degradation During Motion

The response to:

```text
RTK FIX
→ RTK FLOAT
→ DGPS
→ 3D FIX
```

shall not be invented in this contract.

The final policy depends on estimator commissioning evidence and the required marking-accuracy envelope.

Until validated, the production policy remains:

```text
TBD
```

The system must expose the degradation immediately even before final motion policy is frozen.

---

## 23. RPP Failure

If RPP crashes, stops publishing, produces invalid data, or produces stale data:

```text
rpp_ready = false
        ↓
command invalid/stale
        ↓
Motion Control rejects
        ↓
STOP
```

PX4 connection may remain healthy.

Backend may remain healthy.

Recorder may remain healthy.

RPP failure shall not require the complete system to crash.

---

## 24. Backend Failure

Backend is not part of the physical motion safety loop.

Backend failure shall not corrupt PX4/RPP/Motion Control state.

Whether an already-running mission continues after backend/GCS loss is a separate explicit mission policy.

That policy shall not be inferred here.

---

## 25. Frontend Failure

Frontend is not a real-time controller.

Loss of:

```text
tablet
React Native application
Wi-Fi
frontend socket
```

shall not directly corrupt the PX4 ↔ companion control link.

The mission policy may independently decide whether GCS loss requires pause/abort.

---

## 26. Recorder Failure

Recorder failure shall be reported as:

```text
recorder_healthy = false
```

Recorder failure shall not directly inject control commands.

Whether a production mission is permitted without required evidence recording is an operational policy to be defined by the recorder/evidence contract.

---

## 27. Recovery Principle

Fault recovery must revalidate state.

Forbidden:

```text
fault disappears
→ immediately replay old command
```

Required:

```text
fault disappears
       ↓
input freshness verified
       ↓
estimator verified
       ↓
mission authority verified
       ↓
RPP produces new valid command
       ↓
Motion Control accepts new command
```

Old movement commands shall not be resurrected.

---

## 28. Health Reason Codes

Boolean health alone is insufficient for diagnostics.

The implementation should expose reason information such as:

```text
OK
PX4_DISCONNECTED
DDS_UNHEALTHY
TELEMETRY_STALE
ESTIMATOR_NOT_READY
GNSS_UNAVAILABLE
RTK_DEGRADED
MISSION_NOT_READY
RPP_NOT_READY
RPP_COMMAND_STALE
INVALID_MOTION_COMMAND
ESTOP_ACTIVE
PX4_FAILSAFE
MOTION_CONTROL_NOT_READY
```

Exact enum values shall be frozen with the ROS interface implementation.

---

## 29. Frontend Presentation

Frontend receives projected health from backend.

It shall not recompute readiness from raw telemetry.

Conceptually:

```text
ROVER          ONLINE
PX4            CONNECTED
DDS            HEALTHY
ESTIMATOR      READY
RTK            FIXED
MISSION        READY
RPP            READY
SAFETY         CLEAR
AUTONOMY       READY
```

Or:

```text
ROVER          ONLINE
PX4            CONNECTED
DDS            HEALTHY
ESTIMATOR      NOT READY
RTK            FLOAT
RPP            WAITING
AUTONOMY       BLOCKED
```

The backend transports authoritative states.

The frontend displays them.

---

## 30. Telemetry Staleness

Every safety-relevant high-rate state shall have a freshness concept.

A value is not valid simply because a message was received once.

Required pattern:

```text
value
source timestamp
receive timestamp
age
valid/fresh state
```

Exact freshness limits remain hardware-dependent where not already frozen by another contract.

---

## 31. Process Health

Process existence and functional readiness are different.

Example:

```text
dyx_rpp process alive = true
rpp_ready             = false
```

Therefore system health shall not use only Linux process status as control readiness.

---

## 32. Service Independence

Expected production service separation:

```text
dyx-platform.service
dyx-ros.service
dyx-backend.service
dyx-recorder.service
```

Failure of one service shall be visible to the others where relevant.

No service may fabricate another service's health.

---

## 33. Logging Requirements

Safety transitions shall be recorded.

At minimum:

```text
timestamp
run/session ID
previous state
new state
reason
source component
```

Important transitions include:

```text
PX4 connect/disconnect
DDS healthy/unhealthy
estimator ready/lost
RTK state changes
E-stop changes
PX4 failsafe changes
RPP ready/lost
command stale
Motion Control rejection
autonomy enabled/blocked
```

---

## 34. Safety Test Matrix

Before production release, test at minimum:

```text
RPP process kill
Motion Control process kill
PX4 Gateway process kill

PX4 reboot
companion reboot

Ethernet disconnect
XRCE Agent kill

estimator loss
GNSS loss
RTK degradation

stale RPP command
invalid NaN/Inf command
invalid mode
reverse command
over-limit speed
over-limit yaw rate

E-stop activation
PX4 failsafe

backend failure
frontend disconnect
recorder failure
```

Every test must record:

```text
detected fault
detection latency
resulting motion command
PX4 state
health state
recovery behaviour
```

---

## 35. Hardware-Dependent Values

The following shall remain `TBD` until measured:

```text
DDS telemetry freshness thresholds
RPP command stale timeout
gateway watchdog timeout
estimator acceptance thresholds
GNSS acceptance thresholds
RTK degradation policy
reconnection timing
system recovery timing
```

No production values shall be invented merely to complete configuration.

---

## 36. Production Readiness Gate

System Health & Safety remains:

```text
NOT COMMISSIONED
```

until:

```text
physical geometry is measured
estimator is validated
DDS communication is hardware-tested
freshness thresholds are measured
watchdogs are tested
E-stop is tested
PX4 Offboard loss is tested
RPP stale-command behaviour is tested
recovery is tested
```

Software implementation may proceed before this gate.

Production autonomous operation may not.

---

# Current Status

```text
Architecture authority             FROZEN
PX4 command contract               FROZEN
MotionSetpoint contract            FROZEN

Vehicle geometry contract          DEFINED
Physical geometry                  NOT MEASURED

PX4 communication contract         DEFINED
Hardware communication             NOT TESTED

System health contract             DEFINED BY THIS DOCUMENT
Health interfaces                  NOT IMPLEMENTED
Motion validator                   NOT IMPLEMENTED
Hardware safety tests              NOT STARTED
```

**Next document:** `backend_telemetry_contract_v1.md`
