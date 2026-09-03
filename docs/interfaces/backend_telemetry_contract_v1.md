# DYX 4WD — Backend Telemetry Contract V1

**Status:** IMPLEMENTATION BASELINE
**Authority:** DYX 4WD Production Stack Architecture V1
**Classification:** DERIVED — NOT FROM V1 SPEC
**Purpose:** Define the production data boundary between ROS, `dyx_system_gateway`, Python backend, and frontend, including state ownership, telemetry freshness, update-rate classes, reconnect behavior, and rover online/offline semantics.

---

## 1. Architectural Boundary

The production telemetry path is:

```text
PX4 / ROS control graph
        ↓
dyx_system_gateway
        ↓
local IPC boundary
        ↓
Python backend
        ↓
REST + authenticated Socket.IO
        ↓
Frontend
```

The backend shall not directly participate in the ROS real-time control graph.

The frontend shall not directly consume DDS/uORB/PX4 topics.

---

## 2. Ownership Rule

Every telemetry value has one authoritative producer.

```text
PX4 / estimator
  → vehicle pose, velocity, attitude, GNSS, failsafe

dyx_px4_gateway
  → PX4/DDS communication health

dyx_rtk
  → correction transport / RTK service health

dyx_mission
  → mission lifecycle and active target

dyx_rpp
  → guidance/tracking/control diagnostics

dyx_motion_control
  → command acceptance/rejection and applied command

dyx_system_gateway
  → projection/serialization across ROS↔backend boundary

backend
  → client transport, caching, authentication, API/socket delivery

frontend
  → presentation only
```

Backend and frontend shall not silently recompute authoritative control values.

---

## 3. Backend Independence

The backend shall operate independently of PX4 availability.

Valid state:

```text
backend_online = true
frontend_connected = true
px4_connected = false
estimator_ready = false
rpp_ready = false
```

This state shall not be treated as a backend failure.

The frontend must be able to show:

```text
ROVER APPLICATION ONLINE
PX4 OFFLINE
ESTIMATOR UNAVAILABLE
AUTONOMY BLOCKED
```

---

## 4. System Gateway Role

`dyx_system_gateway` is the sole production ROS↔backend boundary.

It shall:

```text
subscribe to approved ROS state
project authoritative telemetry
include source/freshness metadata
serialize stable interface objects
receive approved backend commands
forward commands to ROS-owned APIs
```

It shall not:

```text
implement RPP
recompute estimator state
invent mission state
decide safety policy
perform frontend presentation logic
```

---

## 5. Local IPC Transport

The exact local transport between `dyx_system_gateway` and backend is an implementation choice.

Permitted examples include:

```text
Unix domain socket
local gRPC
equivalent local IPC mechanism
```

Production requirements:

```text
local-only by default
versioned schema
bounded payloads
reconnectable
observable health
no direct frontend access
```

Exact IPC technology is not frozen by this document.

---

## 6. Telemetry Classes

Telemetry shall be rate-classed instead of publishing every value at one universal frequency.

### FAST_CONTROL

Target use:

```text
vehicle pose
heading
vehicle speed
RPP tracking state
RPP heading error
RPP goal distance
cross-track error
along-track remaining
requested speed
requested yaw rate
applied speed
applied yaw rate
```

Expected production class:

```text
20–50 Hz
```

Exact frequencies shall be measured against CPU/network/frontend performance.

---

## 7. MEDIUM_STATE

Typical signals:

```text
GNSS status
RTK status
estimator flags
PX4 mode
arming state
battery state where applicable
mission progress summary
```

Expected class:

```text
5–10 Hz
```

---

## 8. SLOW_HEALTH

Typical signals:

```text
service health
process health
storage status
recorder status
software versions
network state
```

Expected class:

```text
1–2 Hz
```

---

## 9. EVENT_DRIVEN

The following should normally be event-driven:

```text
mission start
pause
resume
abort
complete
point reached
point failed
point skipped
E-stop transition
failsafe transition
PX4 connect/disconnect
estimator ready/lost
RTK mode change
recorder start/stop/failure
parameter change
```

Event messages shall not depend only on polling.

---

## 10. No Frontend Recalculation

If RPP reports:

```text
cross_track_error
along_remaining
heading_error
goal_distance
requested_speed
requested_yaw_rate
```

the frontend shall display those values directly.

Forbidden:

```text
frontend independently recalculates
cross track / along / heading / goal distance
from raw pose
```

The frontend may perform formatting, unit conversion, and visual smoothing only when that does not change the semantic value.

---

## 11. Accuracy Authority

Mission accuracy and live RPP tracking are different concepts.

### Live tracking

Owned by:

```text
dyx_rpp
```

Examples:

```text
current cross-track error
current along-track remaining
current heading error
current goal distance
```

### Final marking accuracy

Owned by the production accuracy/result pipeline.

It must ultimately compare the nozzle control point against surveyed truth according to the geometry/estimator contract.

The frontend shall not derive final mission accuracy from live tracking telemetry.

---

## 12. Canonical Telemetry Envelope

Each telemetry stream should expose metadata equivalent to:

```text
schema_version
source
source_timestamp
gateway_receive_timestamp
backend_receive_timestamp
sequence
valid
fresh
age_ms
```

Exact field names are frozen during interface implementation.

---

## 13. Timestamp Layers

The system contains multiple legitimate time domains.

Examples:

```text
PX4 synchronized timestamp
ROS node clock
monotonic control timestamp
backend wall clock
frontend display time
```

These must not be mixed silently.

Telemetry shall preserve enough information to determine:

```text
when source data was generated
when gateway received it
when backend received it
```

UTC may be used for human-readable logs.

Control freshness shall use the appropriate monotonic/synchronized source semantics defined by the relevant control contract.

---

## 14. Freshness

A telemetry value is not automatically valid because it was received once.

Required concept:

```text
value
valid
fresh
source_timestamp
age
```

Backend shall not endlessly serve an old value as though it is current.

---

## 15. Stale Data Presentation

When source data exceeds its approved freshness threshold:

```text
fresh = false
```

Frontend behavior should distinguish:

```text
0.02 m current
```

from:

```text
0.02 m STALE
```

or unavailable state.

Backend shall not replace stale values with fabricated zeros.

---

## 16. Missing Data

Missing telemetry must remain distinguishable from a true numeric zero.

Examples:

```text
speed = 0.0
```

means measured/reported zero speed.

Whereas:

```text
speed = unavailable
```

means no authoritative current measurement exists.

The backend schema shall preserve this distinction.

---

## 17. Rover Online State

`rover_online` shall describe the production application/backend availability, not PX4 availability.

Conceptually:

```text
rover_online =
    backend service reachable
    AND system identity available
```

PX4 is a separate state:

```text
px4_connected
```

Therefore:

```text
rover_online = true
px4_connected = false
```

is valid.

---

## 18. Frontend Connection State

Frontend connectivity is separate again:

```text
frontend_connected
```

Loss of frontend connection shall not automatically mean:

```text
rover_offline
px4_offline
mission_failed
```

Each authority retains its own state.

---

## 19. System Status Projection

The backend should expose a consolidated system status object containing, conceptually:

```text
rover_online
platform_ready
ros_ready
px4_connected
dds_healthy
estimator_ready
gnss_ready
rtk_ready
mission_state
rpp_ready
motion_control_ready
recorder_state
estop_clear
failsafe_clear
autonomy_move_allowed
```

The values originate from their authoritative owners.

Backend only projects them.

---

## 20. Vehicle State Projection

A canonical live vehicle state should include, where available:

```text
latitude_deg
longitude_deg
altitude_m

local_north_m
local_east_m
local_down_m

yaw_rad
roll_rad
pitch_rad

speed_mps
velocity_north_mps
velocity_east_mps

angular_rate_z_rad_s
```

The exact source mapping shall be documented during gateway implementation.

---

## 21. GNSS Projection

Relevant fields may include:

```text
fix_type
latitude
longitude
altitude
eph
epv
hdop
vdop
satellites_used
velocity
heading
heading_accuracy
jamming_state
spoofing_state
RTCM-related metrics where available
```

PX4 `vehicle_gps_position` remains the primary PX4 GNSS telemetry authority.

---

## 22. Estimator Projection

Estimator health projection should include relevant verified PX4 state such as:

```text
tilt aligned
yaw aligned
GNSS position fusion
GNSS velocity fusion
GNSS yaw fusion
GNSS fault
GNSS yaw fault
inertial dead reckoning
vehicle at rest
position validity
velocity validity
```

The frontend should receive meaningful interpreted fields, not require knowledge of PX4 bit layout.

---

## 23. RPP Telemetry

RPP shall expose the exact control state it uses.

Conceptually:

```text
rpp_state
target_index
target_latitude
target_longitude

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

Frontend shall not recompute these.

---

## 24. Motion Control Telemetry

The final companion-side validator should expose:

```text
source_sequence
control_mode

requested_speed_mps
requested_yaw_rate_rad_s

applied_speed_mps
applied_yaw_rate_rad_s

accepted
reason_code

command_age
```

This allows field logs to distinguish:

```text
RPP requested X
Motion Control allowed Y
PX4 received Y
```

---

## 25. Mission Telemetry

Mission state is owned by `dyx_mission`.

Frontend projections may include:

```text
mission_id
mission_name
mission_state

total_targets
active_target_index

completed_targets
failed_targets
skipped_targets

mission_started_at
mission_elapsed

current_target_status
```

Mission events should use stable target identity, not rely solely on UI row position.

---

## 26. Mission Result Authority

Completed waypoint result data shall not be overwritten by lower-authority transient telemetry.

Once a canonical terminal result is committed:

```text
COMPLETED
FAILED
SKIPPED
```

frontend fallback state must not silently replace it.

Final result authority must be explicit in the result pipeline.

---

## 27. Command Boundary

Backend commands shall travel:

```text
Frontend
   ↓
Backend authorization/validation
   ↓
System Gateway
   ↓
ROS owner
```

Examples:

```text
mission load/start/pause/resume/abort
recording start/stop
parameter request
arm/disarm request
Offboard request
```

The backend shall not directly publish PX4 control topics.

---

## 28. Command Acknowledgement

Commands should support acknowledgement semantics.

Conceptually:

```text
command_id
command_type
requested_at
accepted
result
reason
completed_at
```

Transport-level receipt is not the same as execution success.

---

## 29. Reconnection

Frontend reconnect shall not create a new fake system state.

On reconnect:

```text
frontend connects
        ↓
backend sends authoritative current snapshot
        ↓
frontend subscribes to incremental updates
```

The frontend shall not assume the last locally cached state remains valid.

---

## 30. Backend Restart

After backend restart:

```text
backend starts
      ↓
connects to System Gateway
      ↓
requests/currently receives authoritative state
      ↓
rebuilds cache
      ↓
serves frontend
```

Backend shall not persist stale live telemetry as current state across restart.

---

## 31. System Gateway Restart

If System Gateway restarts:

```text
backend remains online
gateway_connected = false
ROS telemetry unavailable
```

Frontend shall continue to show backend/rover application availability while clearly marking ROS/PX4-derived data unavailable or stale.

---

## 32. PX4 Restart

PX4 restart must appear as a state transition.

Expected sequence may include:

```text
PX4_CONNECTED
↓
PX4_DISCONNECTED
↓
DDS_DISCOVERED
↓
TELEMETRY_VALID
↓
ESTIMATOR_READY
```

The backend shall not hide this transition.

---

## 33. No Unbounded Socket Flood

The backend shall not emit every ROS callback directly to every frontend client without rate control.

Required concepts:

```text
rate class
latest-value cache
event queue
bounded serialization
client backpressure strategy
```

The control graph must never block waiting for frontend transport.

---

## 34. Latest-Value Telemetry

High-rate state should generally use latest-value semantics.

Example:

```text
pose t0
pose t1
pose t2
pose t3
```

If the frontend cannot render all four before `t3`, it is generally more useful to receive the latest valid state than to build an unbounded queue.

Events are different and shall not be silently dropped under normal operation.

---

## 35. Frontend Render Rate

Frontend render rate does not have to equal source telemetry rate.

For example:

```text
RPP source = 50 Hz
backend transport = 30–50 Hz
UI numeric rendering = lower if necessary
```

This is acceptable only if semantic data freshness remains accurate.

Frontend performance optimizations shall not change the authoritative value.

---

## 36. Unit Contract

Production units should be explicit and SI-first.

Examples:

```text
distance       metres
speed          m/s
yaw rate       rad/s
angles         rad internally
latitude/lon   degrees
time           µs/ms/s depending field contract
accuracy       metres internally
```

Frontend may display:

```text
mm
cm
degrees
km/h
```

as presentation formatting.

---

## 37. Coordinate Frames

Frame identity must accompany state where ambiguity is possible.

Examples:

```text
NED
body FRD
global WGS84
local estimator frame
```

Backend shall not rename North/East fields to generic X/Y without preserving frame semantics.

---

## 38. Schema Versioning

Backend telemetry contracts shall be versioned.

Conceptually:

```text
schema_version = 1
```

Breaking field changes require explicit schema revision.

Frontend and backend shall not depend on accidental field ordering.

---

## 39. Compatibility

During migration, compatibility adapters may exist.

They must be clearly separated from authoritative production state.

Forbidden:

```text
legacy field silently overrides new authoritative field
```

Preferred:

```text
canonical state
   ↓
optional legacy projection
```

---

## 40. Authentication

External frontend/backend communication must use authenticated production transport.

Telemetry that can reveal operational system state shall not be exposed through unauthenticated production endpoints.

Exact authentication mechanism is outside this contract.

---

## 41. API and Socket Responsibility

REST is preferred for:

```text
initial state
configuration
mission files
historical/report queries
explicit commands
```

Socket/event transport is preferred for:

```text
live telemetry
state changes
mission events
health changes
command acknowledgements
```

Exact endpoint names are frozen during backend implementation.

---

## 42. Error Handling

Backend errors must not masquerade as rover-state values.

For example, a failed request must not produce:

```text
speed = 0
```

unless authoritative speed is actually zero.

Transport/API failure and state values remain distinct.

---

## 43. Diagnostics

Backend/system gateway diagnostics should expose:

```text
gateway_connected
gateway_last_message_age

socket_clients
telemetry_publish_rate

dropped/coalesced telemetry updates
serialization errors
schema mismatch

backend uptime
ROS boundary health
```

These diagnostics are not themselves control authority.

---

## 44. Recorder Integration

The recorder should capture authoritative ROS topics directly where possible rather than depending only on frontend telemetry.

Backend telemetry may still be recorded for end-to-end interface analysis.

The recorder/evidence contract defines exact recording scope.

---

## 45. Required Tests

Before production release, test:

```text
backend starts without PX4
frontend connects without PX4

PX4 connects after backend startup
PX4 disconnects during operation
PX4 reconnects

System Gateway restart
backend restart
frontend reconnect

high-rate telemetry load
slow frontend client
multiple frontend clients

stale source telemetry
missing fields
invalid numeric values

mission event ordering
command acknowledgement
schema mismatch

network interruption
socket reconnect
```

---

## 46. Performance Evidence

Measure:

```text
ROS source frequency
System Gateway receive frequency
backend receive frequency
socket transmit frequency
frontend receive frequency

source → gateway latency
gateway → backend latency
backend → frontend latency
end-to-end latency

CPU usage
memory usage
socket queue growth
dropped/coalesced updates
```

No production rate or latency guarantee shall be claimed without measured evidence.

---

## 47. Production Readiness Gate

Backend telemetry remains:

```text
NOT COMMISSIONED
```

until:

```text
System Gateway schema is frozen
backend IPC is implemented
authoritative source mapping is verified
freshness policy is implemented
reconnect behavior is tested
socket load is tested
frontend stale-state behavior is tested
end-to-end telemetry latency is measured
```

---

# Current Status

```text
Architecture authority           FROZEN
System health contract           DEFINED

Backend telemetry contract       DEFINED BY THIS DOCUMENT

System Gateway implementation    NOT STARTED
Backend IPC                       NOT IMPLEMENTED
Telemetry schema                 NOT FROZEN
Frontend integration             NOT IMPLEMENTED
End-to-end load testing          NOT STARTED
```

**Next document:** `recorder_evidence_contract_v1.md`
