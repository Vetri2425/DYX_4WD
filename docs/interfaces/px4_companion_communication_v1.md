# DYX 4WD — PX4 ↔ Companion Communication Contract V1

**Status:** IMPLEMENTATION BASELINE
**Scope:** PX4 ↔ Jetson/Radxa communication only
**Transport target:** Dedicated Ethernet
**Middleware:** Micro XRCE-DDS / ROS 2
**MAVROS:** Not part of production architecture

---

## 1. Purpose

The PX4 communication layer is the first hardware-facing service required by the DYX ROS control system.

Its responsibilities are limited to:

```text
Ethernet readiness
XRCE-DDS Agent availability
PX4 DDS discovery
PX4 telemetry reception
PX4 command transport
connection-health reporting
reconnection
communication-loss detection
```

It shall not own:

```text
path planning
RPP steering
mission logic
terminal logic
RTK accuracy decisions
backend lifecycle
```

---

## 2. Production Chain

```text
PX4 FMUv6X
   ↕
Dedicated Ethernet
   ↕
Micro XRCE-DDS Agent
   ↕
ROS 2 / DDS
   ↕
dyx_px4_gateway
```

No MAVROS or MAVLink command bridge exists in the production control path.

---

## 3. Service Ownership

Platform communication shall be started by:

```text
dyx-platform.service
```

It owns:

```text
network configuration
Ethernet readiness
XRCE Agent process
XRCE Agent restart
basic transport health
```

ROS starts separately through:

```text
dyx-ros.service
```

`dyx_ros` shall not configure the operating-system network.

---

## 4. Startup Order

Required boot sequence:

```text
Linux boot
   ↓
network device available
   ↓
dedicated PX4 Ethernet configured
   ↓
dyx-platform.service
   ↓
XRCE Agent running
   ↓
dyx-ros.service
   ↓
dyx_px4_gateway starts
   ↓
wait for PX4 DDS topics
   ↓
validate telemetry
   ↓
publish PX4 health state
```

No motion is authorized merely because the XRCE Agent process exists.

---

## 5. Communication State Model

The gateway shall distinguish communication states.

Minimum conceptual states:

```text
DISCONNECTED
TRANSPORT_READY
DDS_DISCOVERED
TELEMETRY_VALID
ESTIMATOR_READY
CONTROL_AVAILABLE
```

### DISCONNECTED

No valid PX4 communication.

### TRANSPORT_READY

Ethernet and XRCE Agent are available.

This does not prove PX4 is connected.

### DDS_DISCOVERED

Expected PX4 DDS endpoints have been discovered.

This does not prove telemetry is current.

### TELEMETRY_VALID

Required PX4 telemetry is being received within validated freshness limits.

### ESTIMATOR_READY

Estimator/GNSS health policy has passed.

The exact localisation readiness policy belongs to the estimator commissioning contract.

### CONTROL_AVAILABLE

All required communication and PX4 state prerequisites for control are valid.

This still does not independently authorize autonomous movement.

---

## 6. Required PX4 Telemetry

The gateway shall consume the required stock PX4 DDS outputs including:

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

Additional topics may be added only when there is a defined consumer.

Do not subscribe to large sets of unused PX4 topics.

---

## 7. PX4 Command Interface

The production gateway shall support the native PX4 rover command path defined by `px4_contract_v1.md`.

Primary incoming PX4 topics include:

```text
/fmu/in/offboard_control_mode

/fmu/in/rover_speed_setpoint
/fmu/in/rover_rate_setpoint
/fmu/in/rover_attitude_setpoint

/fmu/in/vehicle_command
```

`TrajectorySetpoint` shall not be used for DYX rover motion.

---

## 8. Communication Health

Communication health shall not be represented by one DDS callback.

The gateway shall independently monitor freshness of required signals.

Conceptually:

```text
vehicle_status_age
vehicle_attitude_age
local_position_age
gps_age
estimator_status_age
```

The exact timeout values are:

```text
TBD — HARDWARE MEASUREMENT REQUIRED
```

They shall be derived from measured publication rates, jitter, DDS behaviour, and hardware tests.

No arbitrary timeout is frozen here.

---

## 9. Fail-Safe Principle

Communication failure must fail toward zero motion.

Two layers are required.

### Layer A — Companion watchdog

If the active motion command becomes stale or invalid:

```text
requested speed = 0
requested yaw rate = 0
```

The gateway shall not continue replaying an old movement command indefinitely.

### Layer B — PX4 Offboard-loss protection

If the gateway, ROS process, companion, Ethernet link, DDS Agent, or DDS heartbeat disappears:

```text
OffboardControlMode heartbeat stops
```

PX4 then owns Offboard-loss handling according to its configured failsafe policy.

Both layers are mandatory.

---

## 10. Reconnection

Loss of PX4 communication must not require restarting the complete rover software stack.

Expected behavior:

```text
PX4 disappears
    ↓
gateway reports disconnected
    ↓
motion authority removed
    ↓
PX4 returns
    ↓
DDS rediscovered
    ↓
telemetry revalidated
    ↓
estimator revalidated
    ↓
system returns to READY
```

Autonomous movement shall not automatically resume merely because communication returned.

Mission/safety logic must explicitly authorize continuation.

---

## 11. PX4 Restart

The architecture must tolerate PX4 reboot while the companion remains powered.

Backend, recorder daemon and ROS processes should remain available where practical.

After PX4 reboot:

```text
old control authority = invalid

old command sequence/session =
    must not silently resume

estimator =
    must become ready again

Offboard =
    must be deliberately re-established
```

---

## 12. Companion Restart

If Jetson/Radxa reboots:

```text
PX4 detects Offboard loss
```

After companion startup:

```text
network
→ XRCE Agent
→ ROS
→ gateway
→ telemetry
→ estimator validation
→ control readiness
```

No previous movement command may survive the reboot.

---

## 13. Ethernet Contract

Production target:

```text
PX4 ↔ Companion
Dedicated wired Ethernet
```

The PX4 control network should not depend on:

```text
Wi-Fi
internet
4G
frontend connection
backend client connection
```

Loss of internet or GCS must not itself destroy PX4 ↔ companion control communication.

---

## 14. Network Configuration

Final production values remain:

```text
PX4 IP            = TBD
Companion IP      = TBD
subnet            = TBD
XRCE Agent port   = TBD
XRCE client config = TBD
```

No values shall be invented before hardware network commissioning.

The final values belong in production configuration rather than source-code constants.

---

## 15. Backend Independence

Backend lifecycle shall not depend on PX4 connection.

Valid system condition:

```text
Backend      ONLINE
Frontend     CONNECTED
PX4          OFFLINE
Estimator    UNAVAILABLE
RPP          WAITING
```

The frontend must be able to see this state.

PX4 disconnection is telemetry/state, not a backend crash condition.

---

## 16. RPP Independence

The RPP process may start before PX4 becomes available.

Expected state:

```text
RPP process = RUNNING
RPP control = WAITING_FOR_STATE
```

Only valid estimator/control readiness may allow RPP output to progress toward motion authority.

RPP shall not crash or repeatedly restart because PX4 is absent.

---

## 17. Telemetry Architecture

High-rate PX4 data remains inside ROS/DDS.

Backend receives a deliberate telemetry projection through the system gateway.

Do not forward every DDS sample blindly to Socket.IO.

Recommended conceptual classes:

```text
FAST
pose
yaw
speed
RPP errors

MEDIUM
GNSS/RTK
estimator state
mission progress

SLOW
battery
system health
temperatures
static information
```

Exact publication rates shall be measured and tuned later.

---

## 18. Time Contract

PX4 DDS timestamp handling follows `px4_contract_v1.md`.

With:

```text
UXRCE_DDS_SYNCT=1
```

the gateway shall not introduce a second manual PX4 time-offset conversion.

Internal DYX command freshness remains based on the DYX monotonic command timestamp contract.

These are separate timing layers.

---

## 19. Diagnostics

Communication diagnostics should expose at minimum:

```text
transport_ready
dds_discovered
px4_connected

last_px4_message_age
last_required_telemetry_age

vehicle_status_valid
attitude_valid
position_valid
gps_valid
estimator_status_valid

estimator_ready
control_available

xrce_agent_state
reconnect_count
connection_uptime
```

Exact schema will be defined during interface implementation.

---

## 20. Logging

The recorder shall retain enough information to diagnose communication failures.

Required evidence includes:

```text
PX4 connection transitions
DDS discovery/reconnect events
telemetry freshness
failsafe state
vehicle status
estimator state
command timestamps
MotionSetpoint
ValidatedMotionSetpoint
```

Do not generate uncontrolled debug files outside the production recorder.

---

## 21. Hardware Acceptance Tests

Before the communication layer is production-ready, verify:

```text
cold boot connection
PX4-first boot
companion-first boot

PX4 reboot
companion reboot

Ethernet disconnect
Ethernet reconnect

XRCE Agent kill
XRCE Agent restart

ROS gateway kill
ROS gateway restart

DDS interruption

stale motion command
Offboard heartbeat loss
```

For every failure test verify:

```text
no uncontrolled persistent motion
correct health transition
correct frontend-visible status
automatic communication recovery where appropriate
no automatic unsafe mission resume
```

---

## 22. Production Readiness Gate

Communication remains:

```text
NOT COMMISSIONED
```

until dedicated Ethernet and XRCE-DDS have been validated on the selected production companion and Pixhawk 6X hardware.

Passing CI proves software build/test integrity.

It does not prove physical Ethernet/DDS reliability.

---

# Current Status

```text
PX4 DDS source contract       VERIFIED
Native rover messages         VERIFIED
XRCE timestamp behavior       VERIFIED
PX4 Offboard semantics        VERIFIED

FMUv6X Ethernet compiled      VERIFIED
uXRCE-DDS client compiled     VERIFIED

Physical Ethernet link        NOT TESTED
XRCE over production link     NOT TESTED
Reconnect behavior            NOT TESTED
Hardware latency/jitter       NOT TESTED
Hardware watchdog behavior    NOT TESTED
```

**Next commissioning gate:** establish stable PX4 ↔ companion Ethernet/XRCE-DDS communication and measure its real rates, latency, jitter, reconnect behavior and failure handling.
