# DYX 4WD — MotionSetpoint Contract V1

**Document status:** Production interface contract  
**Interface:** `dyx_rpp` → `dyx_motion_control`  
**Repository:** `Vetri2425/DYX_4WD`  
**Primary architecture source:** `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`  
**PX4 downstream contract:** `docs/interfaces/px4_contract_v1.md`  
**Version:** V1

> DERIVED — NOT FROM V1 SPEC: After source-auditing PX4 v1.17 native rover control, `SPEED_RATE` is selected as the single production driving mode for straight tracking, active correction, curves, and terminal approach. `SPEED_HEADING` remains reserved in the enum for compatibility with the frozen architecture but is not valid for production V1 execution.

---

## 1. Purpose

This document freezes the canonical motion-command contract produced by `dyx_rpp` and consumed by `dyx_motion_control`.

The interface must answer exactly one question:

> **What motion does RPP request the rover to execute right now?**

It must not contain PX4-specific transport details, motor commands, actuator outputs, mission-management commands, backend fields, or frontend presentation fields.

The contract exists to separate:

```text
RPP intelligence
    ↓
MotionSetpoint
    ↓
Motion Control validation
    ↓
ValidatedMotionSetpoint
    ↓
PX4 Gateway
```

RPP owns path-level movement intent.

Motion Control owns safety validation and fail-to-zero behavior.

PX4 Gateway owns translation to the pinned PX4 rover interface.

---

## 2. Authority Boundary

### `dyx_rpp` owns

- path-following geometry;
- cross-track error;
- along-track error;
- goal distance;
- path heading;
- corrected desired heading;
- heading error;
- yaw correction;
- desired yaw rate;
- desired forward speed;
- pivot entry;
- pivot taper;
- pivot release;
- terminal speed profile;
- terminal heading correction;
- final stop request;
- stop-certificate decision.

### `dyx_motion_control` owns

- finite-value validation;
- mode validation;
- command freshness;
- source sequence validation;
- mission-state gating;
- emergency-stop gating;
- global speed limits;
- global yaw-rate limits;
- allowed acceleration/deceleration envelope;
- stale-command watchdog;
- fail-to-zero conversion;
- rejection/fault reason.

### `dyx_motion_control` must not

- compute cross-track correction;
- alter path heading;
- invent a yaw correction;
- choose a new target;
- decide pivot entry/release;
- decide mission completion;
- replace RPP guidance logic.

---

## 3. Canonical Message

The production ROS message shall be defined in:

```text
ros2_ws/src/dyx_interfaces/msg/MotionSetpoint.msg
```

Recommended V1 schema:

```text
uint8 MODE_STOP=0
uint8 MODE_SPEED_HEADING=1
uint8 MODE_SPEED_RATE=2
uint8 MODE_PIVOT_RATE=3

uint64 timestamp_us
uint32 sequence
uint8 control_mode

float32 speed_mps
float32 heading_rad
float32 yaw_rate_rad_s

bool valid
```

### 3.1 Field semantics

#### `timestamp_us`

Monotonic source timestamp representing when RPP produced this command.

Units:

```text
microseconds
```

This field is used for freshness checks.

It must not be interpreted as wall-clock UTC.

#### `sequence`

Monotonically increasing RPP command sequence number.

Purpose:

- identify duplicate commands;
- detect gross ordering problems;
- improve logs and replay;
- support deterministic watchdog diagnostics.

Wraparound is allowed according to unsigned 32-bit arithmetic.

A sequence reset is allowed only when RPP restarts or the control session is explicitly reset.

#### `control_mode`

Defines how the motion fields are to be interpreted.

Production V1 valid modes:

```text
MODE_STOP
MODE_SPEED_RATE
MODE_PIVOT_RATE
```

Reserved:

```text
MODE_SPEED_HEADING
```

#### `speed_mps`

Requested longitudinal rover speed in body-x direction.

Units:

```text
m/s
```

Sign convention:

```text
positive = forward
zero     = no requested longitudinal translation
negative = reverse
```

Production V1 autonomous mission control does not permit reverse motion unless a later reviewed contract explicitly enables it.

#### `heading_rad`

RPP's desired heading intent.

Units:

```text
rad
```

Frame and angular convention:

```text
navigation frame: NED
0 rad             = North
positive yaw      = clockwise toward East
normalized domain = [-pi, pi)
```

This is intentionally **not** ROS REP-103 ENU yaw.

Any ENU <-> NED conversion must occur at an explicitly owned boundary.
No downstream node may silently reinterpret `heading_rad` as REP-103 ENU.

This field remains observable even when `SPEED_RATE` is active so:

- logs retain the desired heading;
- heading error can be audited;
- pivot taper/release can be explained;
- frontend/recorder can expose what RPP intended.

For production V1 this field is **informational to Motion Control** in `SPEED_RATE` and `PIVOT_RATE`; Motion Control must not derive a new yaw-rate command from it.

#### `yaw_rate_rad_s`

RPP's requested yaw-rate command.

Units:

```text
rad/s
```

Sign must match the PX4 NED yaw-rate convention used by the downstream PX4 contract.

The physical sign is hardware-verified before production acceptance.

#### `valid`

RPP declares whether the setpoint is internally valid.

`false` must never be treated as "reuse the last command."

If `valid == false`, Motion Control must convert the output to STOP.

---

## 3A. ROS 2 Timestamp Interoperability

Production V1 intentionally does not add `std_msgs/Header` to `MotionSetpoint`.

`timestamp_us` is a monotonic control-safety timestamp used for deterministic freshness evaluation. It must not be replaced by a wall-clock timestamp or TF frame timestamp.

ROS bag / MCAP recording already associates received messages with the recorder timeline. Offline tools shall use the bag/recorder timestamp for cross-topic timeline alignment while preserving `timestamp_us` as the source-side control freshness value.

This avoids introducing two competing command-age clocks into a safety-critical message.

---

## 4. Mode Contract

## 4.1 `MODE_STOP`

Meaning:

```text
RPP requests literal controlled zero motion.
```

Required invariants:

```text
control_mode   = MODE_STOP
speed_mps      = 0.0
yaw_rate_rad_s = 0.0
valid          = true
```

`heading_rad` must remain finite for diagnostics but has no control authority.

If no path, pivot target, or other meaningful heading intent exists, including cold RPP startup before a path is loaded, RPP shall publish:

```text
heading_rad = 0.0
```

RPP is not required to depend on current vehicle attitude merely to construct a safe STOP command.

If meaningful heading intent already exists, RPP may retain that finite desired heading for diagnostics while STOP remains active.

Motion Control output:

```text
speed = 0
yaw_rate = 0
mode = STOP
```

STOP is the canonical safe state.

---

## 4.2 `MODE_SPEED_RATE`

Meaning:

```text
RPP directly owns translational speed and path-level rotational correction.
```

Used for:

- straight path tracking;
- small heading correction;
- cross-track correction;
- curves;
- post-pivot release;
- cruise;
- acceleration;
- deceleration;
- terminal approach;
- terminal heading correction.

Required invariants:

```text
control_mode      = MODE_SPEED_RATE
speed_mps         = finite
yaw_rate_rad_s    = finite
heading_rad       = finite
valid             = true
```

Production V1 policy:

```text
speed_mps >= 0
```

The exact maximum speed and yaw-rate limits are runtime configuration owned by Motion Control / system configuration, not encoded into the message definition.

### Why `SPEED_RATE` is primary

The downstream PX4 v1.17 contract natively supports:

```text
RoverSpeedSetpoint + RoverRateSetpoint
```

This allows:

```text
RPP:
  desired heading
  heading error
  yaw correction
  yaw-rate intent

PX4:
  speed inner loop
  yaw-rate inner loop
  differential motor execution
```

This keeps one steering authority throughout normal motion.

---

## 4.3 `MODE_PIVOT_RATE`

Meaning:

```text
RPP requests zero longitudinal motion and explicit yaw-rate rotation.
```

Required invariants:

```text
control_mode      = MODE_PIVOT_RATE
speed_mps         = 0.0
yaw_rate_rad_s    = finite
heading_rad       = finite
valid             = true
```

During an active pivot:

```text
yaw_rate_rad_s != 0
```

At pivot completion RPP must transition to either:

```text
MODE_STOP
```

or:

```text
MODE_SPEED_RATE
```

RPP owns:

- pivot target heading;
- heading error;
- taper law;
- requested yaw-rate sign;
- requested yaw-rate magnitude;
- release threshold;
- transition timing.

Motion Control must not invent its own pivot taper or heading controller.

### True pivot expectation

The downstream PX4 contract maps:

```text
speed = 0
yaw_rate != 0
```

into native differential rover speed/rate control.

Physical counter-rotation remains a hardware acceptance requirement.

---

## 4.4 `MODE_SPEED_HEADING` — Reserved

The frozen architecture originally listed:

```text
STOP
SPEED_HEADING
SPEED_RATE
PIVOT_RATE
```

Production V1 retains the enum value to avoid gratuitous interface churn, but it is not executable.

If received:

```text
control_mode = MODE_SPEED_HEADING
```

Motion Control must:

```text
reject command
force STOP
record rejection reason
```

unless a future approved contract revision explicitly enables it.

### Reason

> DERIVED — NOT FROM V1 SPEC: The source-audited PX4 v1.17 architecture supports direct speed + yaw-rate control. Using `SPEED_HEADING` for straight motion and `SPEED_RATE` for corrections would introduce unnecessary authority switching and the possibility of heading/rate controller interaction. V1 therefore uses a single RPP rotational-authority model.

---

## 5. Finite / NaN / Infinity Rules

All active numeric MotionSetpoint fields must be finite.

For production-valid RPP commands:

```text
isfinite(speed_mps)      == true
isfinite(heading_rad)    == true
isfinite(yaw_rate_rad_s) == true
```

The internal `MotionSetpoint` contract does **not** use NaN as a control-mode selector.

NaN is used only later inside the PX4 Gateway where the PX4 rover contract explicitly requires it to disable a higher controller.

Therefore:

```text
NaN in MotionSetpoint = invalid command
Inf in MotionSetpoint = invalid command
```

Invalid numeric input always fails to STOP.

---

## 6. Reverse Policy

Production V1 autonomous precision marking is forward-only.

Therefore:

```text
speed_mps < 0
```

is invalid during normal mission execution.

Motion Control shall reject it and fail to STOP.

Reverse capability may be introduced later for:

- recovery;
- manual service mode;
- obstacle recovery;
- special maneuvering.

Such support requires a separate reviewed behavior/safety contract.

---

## 7. Freshness Contract

The MotionSetpoint must be considered a time-sensitive command.

A new command does not remain safe indefinitely.

Motion Control must calculate command age using a monotonic timebase compatible with `timestamp_us`.

If age exceeds the configured production freshness threshold:

```text
mode = STOP
speed = 0
yaw_rate = 0
```

The exact timeout value is intentionally not frozen here because it must be selected from measured RPP rate, gateway rate, DDS timing, scheduling jitter, and hardware test results.

### Critical rule

A stale MotionSetpoint must never result in:

```text
reuse previous speed
reuse previous yaw rate
```

---

## 8. Sequence Contract

`sequence` must normally increase for every newly generated RPP command.

Motion Control may accept repeated sequence numbers only according to an explicitly defined transport/republication policy.

At minimum the implementation must detect and diagnose:

- old sequence arriving after newer command;
- source reset;
- impossible jump if such a check is configured;
- duplicate command.

Sequence validation is secondary to timestamp freshness.

A sequence number alone must never prove freshness.

---

## 9. Mission and Safety Gating

A valid RPP command is not sufficient by itself to move the rover.

Motion Control must also require its external safety gates to permit motion.

Typical gates include:

```text
mission execution enabled
mission not paused
mission not aborted
emergency stop clear
control authority valid
PX4 gateway healthy enough for command acceptance
```

If any required gate fails:

```text
ValidatedMotionSetpoint.mode = STOP
speed = 0
yaw_rate = 0
```

RPP does not bypass these gates.

---

## 10. Fail-to-Zero Rules

The canonical safety response to an invalid command is:

```text
STOP
0 m/s
0 rad/s
```

Conditions include at minimum:

- `valid == false`;
- unsupported mode;
- NaN;
- Inf;
- negative autonomous speed;
- stale timestamp;
- failed sequence policy;
- emergency stop;
- mission disabled;
- upstream authority loss;
- unsafe global limit violation according to configured policy.

No invalid state may fall back to the previous nonzero command.

---

## 11. Limit Handling

Motion Control owns the absolute vehicle safety envelope.

Examples:

```text
max_forward_speed
max_abs_yaw_rate
max_acceleration
max_deceleration
mode-specific bounds
```

RPP owns guidance-level target selection within that envelope.

### V1 preferred behavior

For semantic contract violations:

```text
reject -> STOP
```

For ordinary bounded runtime requests that exceed an explicitly configured absolute physical maximum, the exact policy must be deliberate and tested:

```text
reject
or
static saturation clamp
```

It must not be accidental.

### Static saturation versus dynamic slew limiting

`dyx_motion_control` is a safety validator, not a second path-speed controller.

Production V1 ownership is:

```text
RPP:
  path-level acceleration/deceleration profile
  terminal speed shaping
  turn/pivot speed strategy

Motion Control:
  absolute limit validation
  optional instantaneous saturation to configured hard bounds
  no continuous smoothing controller
  no independent trajectory shaping

PX4:
  physical inner-loop speed/yaw-rate execution
  configured physical acceleration/deceleration/slew behavior
```

Therefore Motion Control must not silently ramp or low-pass an RPP command in a way that changes RPP path timing or steering intent.

Any static saturation/clamping must:

- be recorded;
- expose requested value;
- expose applied value;
- expose reason;
- preserve sign semantics.

---

## 12. Mode Transition Rules

Allowed production V1 transitions:

```text
STOP → SPEED_RATE
STOP → PIVOT_RATE

SPEED_RATE → SPEED_RATE
SPEED_RATE → PIVOT_RATE
SPEED_RATE → STOP

PIVOT_RATE → PIVOT_RATE
PIVOT_RATE → SPEED_RATE
PIVOT_RATE → STOP
```

`SPEED_HEADING` transitions are not allowed in production V1.

### No implicit transitional mode

Motion Control must not create an undocumented "half pivot" or "heading mode" while switching.

RPP explicitly publishes the mode it intends.

### Pivot release

Pivot release is owned by RPP.

Typical logical sequence:

```text
PIVOT_RATE
  yaw_rate tapers
        ↓
heading/release condition met
        ↓
SPEED_RATE or STOP
```

Motion Control validates the transition but does not decide it.

---

## 13. Acceleration / Deceleration Ownership

RPP determines desired speed profile for path behavior:

- cruise target;
- turn speed;
- terminal deceleration;
- post-pivot acceleration;
- precision approach speed.

Motion Control enforces the global physical/safety envelope.

PX4 later closes the physical speed loop and applies its configured speed/throttle slew behavior.

This creates three distinct layers:

```text
RPP:
  what speed should path-following request?

Motion Control:
  is that requested change safe/allowed?

PX4:
  how does the physical rover achieve it?
```

Do not duplicate the same controller at all three layers.

---

## 14. Heading Field Semantics

Even though production V1 drives using yaw-rate, `heading_rad` remains mandatory and finite.

Purpose:

- explain RPP intent;
- calculate/record heading error;
- support pivot target auditing;
- support terminal heading auditing;
- support frontend telemetry;
- support bag replay;
- support future contract revisions.

Motion Control does not close heading control from this field.

Downstream PX4 Gateway does not map it to `RoverAttitudeSetpoint` during the `SPEED_RATE` contract.

Instead the downstream PX4 attitude setpoint is explicitly disabled according to `px4_contract_v1.md`.

---

## 15. Relationship to PX4 Contract

The MotionSetpoint contract is vehicle-semantic and PX4-independent.

The PX4 Gateway mapping is:

### `MODE_STOP`

```text
RoverSpeedSetpoint.speed_body_x      = 0
RoverRateSetpoint.yaw_rate_setpoint  = 0
RoverAttitudeSetpoint.yaw_setpoint   = NaN
```

### `MODE_SPEED_RATE`

```text
RoverSpeedSetpoint.speed_body_x      = speed_mps
RoverRateSetpoint.yaw_rate_setpoint  = yaw_rate_rad_s
RoverAttitudeSetpoint.yaw_setpoint   = NaN
```

### `MODE_PIVOT_RATE`

```text
RoverSpeedSetpoint.speed_body_x      = 0
RoverRateSetpoint.yaw_rate_setpoint  = yaw_rate_rad_s
RoverAttitudeSetpoint.yaw_setpoint   = NaN
```

`heading_rad` remains internal DYX intent/telemetry in V1.

---

## 16. ValidatedMotionSetpoint

`dyx_motion_control` should not republish the raw message unchanged under the same semantic name.

The output should make validation explicit, for example:

```text
ValidatedMotionSetpoint
```

Recommended conceptual fields:

```text
uint64 timestamp_us
uint32 source_sequence
uint8 control_mode

float32 requested_speed_mps
float32 requested_yaw_rate_rad_s

float32 applied_speed_mps
float32 applied_yaw_rate_rad_s

bool accepted
uint16 reason_code
```

This exact downstream message is **not frozen by this document** unless separately adopted into `dyx_interfaces`.

The important rule is that raw requested and validated/applied authority remain distinguishable in logs.

---

## 17. Rejection Reason Model

Motion Control should expose machine-readable rejection reasons.

Recommended categories:

```text
NONE
SOURCE_INVALID
UNSUPPORTED_MODE
NONFINITE_SPEED
NONFINITE_HEADING
NONFINITE_YAW_RATE
REVERSE_NOT_ALLOWED
STALE_COMMAND
SEQUENCE_ERROR
MISSION_DISABLED
MISSION_PAUSED
MISSION_ABORTED
EMERGENCY_STOP
SPEED_LIMIT
YAW_RATE_LIMIT
ACCEL_LIMIT
DECEL_LIMIT
AUTHORITY_LOST
INTERNAL_ERROR
```

Numeric values should be frozen when the actual interface message is implemented.

Do not use human-readable strings as the only safety diagnostic.

---

## 18. Logging Requirements

Every control-cycle record should make it possible to reconstruct:

```text
timestamp
sequence
mode
RPP requested speed
RPP heading target
RPP heading error
RPP requested yaw rate
raw valid flag

Motion Control acceptance
Motion Control rejection reason
applied speed
applied yaw rate
command age

mission gate
estop gate
gateway health
PX4 mode/state
```

This is required for centimeter-level field debugging and post-mission evidence.

---

## 19. RPP Publishing Rules

RPP shall:

1. initialize every field explicitly;
2. publish a complete command each cycle;
3. never rely on previous-message values;
4. use monotonic timestamps;
5. increment sequence deterministically;
6. publish STOP rather than silence when RPP intentionally wants a controlled stop;
7. set `valid=false` if internal guidance output cannot be trusted;
8. never encode mode using NaN;
9. never publish PX4-specific control flags;
10. never publish actuator/PWM intent.

---

## 20. Motion Control Consumption Rules

Motion Control shall:

1. validate mode;
2. validate finite numeric values;
3. validate mode-specific invariants;
4. validate freshness;
5. validate source ordering policy;
6. validate mission/safety gates;
7. validate physical limits;
8. produce explicit applied command;
9. fail to STOP on any invalid safety state;
10. publish/record reason for rejection;
11. never create path-following steering.

---

## 21. Mode-Specific Validation Matrix

| Condition | STOP | SPEED_RATE | PIVOT_RATE | SPEED_HEADING |
|---|---:|---:|---:|---:|
| `valid=true` required | Yes | Yes | Yes | N/A |
| finite speed | Yes | Yes | Yes | Rejected |
| finite heading | Yes | Yes | Yes | Rejected |
| finite yaw rate | Yes | Yes | Yes | Rejected |
| speed must equal 0 | Yes | No | Yes | Rejected |
| yaw rate must equal 0 | Yes | No | No while pivot active | Rejected |
| forward-only policy | N/A | Yes | N/A | Rejected |
| production V1 executable | Yes | Yes | Yes | No |

---

## 22. Unit Tests Required Before Interface Acceptance

### Message validation

- STOP with exact zeros accepted;
- STOP with nonzero speed rejected;
- STOP with nonzero yaw rate rejected;
- SPEED_RATE finite values accepted;
- SPEED_RATE negative speed rejected;
- PIVOT_RATE zero speed accepted;
- PIVOT_RATE nonzero speed rejected;
- reserved SPEED_HEADING rejected;
- NaN speed rejected;
- NaN heading rejected;
- NaN yaw rate rejected;
- Inf values rejected;
- `valid=false` rejected.

### Freshness

- fresh timestamp accepted;
- stale timestamp produces STOP;
- future/invalid timestamp policy tested;
- stale command never reuses old nonzero output.

### Sequence

- increasing sequence accepted;
- duplicate behavior explicitly tested;
- out-of-order behavior explicitly tested;
- source restart/reset behavior explicitly tested.

### Safety gates

- estop → STOP;
- mission disabled → STOP;
- pause → STOP;
- abort → STOP;
- authority loss → STOP.

### Transitions

- STOP → SPEED_RATE;
- SPEED_RATE → STOP;
- STOP → PIVOT_RATE;
- PIVOT_RATE → SPEED_RATE;
- PIVOT_RATE → STOP;
- SPEED_RATE → PIVOT_RATE;
- no transition through reserved SPEED_HEADING.

---

## 23. Hardware/Integration Tests Required Later

The internal message contract is not production-qualified until integration tests prove:

- requested speed reaches PX4 as the same semantic speed;
- requested yaw rate reaches PX4 with correct sign;
- STOP maps to physical stop;
- PIVOT_RATE maps to zero-speed differential pivot;
- stale RPP command triggers fast fail-to-zero;
- gateway death triggers PX4 Offboard failsafe;
- no finite heading command reaches PX4 attitude control during SPEED_RATE;
- logs preserve raw and applied commands;
- mode transitions do not produce command spikes.

---

## 24. What Is Not in MotionSetpoint

Do not add:

```text
latitude
longitude
target waypoint ID
path point array
cross-track error
along-track error
goal distance
mission state
spray command
PX4 Offboard flags
PX4 arm/disarm command
motor outputs
PWM
DDS address
vehicle status
estop state
```

Those belong to other interfaces or status messages.

The motion command must stay small and semantically stable.

---

## 25. Compatibility Rule

Changes that alter any of the following require contract review before message modification:

- field meaning;
- units;
- sign convention;
- enum values;
- valid mode set;
- NaN semantics;
- reverse policy;
- timestamp semantics;
- sequence semantics;
- fail-to-zero behavior;
- RPP/Motion Control authority boundary.

Do not silently repurpose existing enum values.

Additive fields must be reviewed for replay/log compatibility and whether they belong in a separate status interface instead.

---

## 26. Production V1 Decision

The canonical RPP command is:

```text
MotionSetpoint
```

with production modes:

```text
STOP
SPEED_RATE
PIVOT_RATE
```

Reserved:

```text
SPEED_HEADING
```

Normal path tracking:

```text
mode     = SPEED_RATE
speed    = RPP desired speed
heading  = RPP desired heading (diagnostic/intention)
yaw_rate = RPP correction
```

Pivot:

```text
mode     = PIVOT_RATE
speed    = 0
heading  = target heading
yaw_rate = tapered RPP pivot rate
```

Stop:

```text
mode     = STOP
speed    = 0
yaw_rate = 0
```

This gives one path-level rotational authority:

```text
RPP
```

and one physical yaw-rate inner-loop authority:

```text
PX4
```

without unnecessary heading/rate ownership switching.

---

## 27. Source Index

Primary repository evidence:

1. `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`
   - Section 6 — `dyx_interfaces`
   - Section 9 — `dyx_rpp`
   - Section 10 — control ownership
   - Section 11 — original control modes
   - Section 12 — `dyx_motion_control`
   - Section 13 — `dyx_px4_gateway`
   - Section 14 — PX4 relationship

2. `docs/interfaces/px4_contract_v1.md`
   - primary `SPEED_RATE` decision;
   - native RoverSpeedSetpoint + RoverRateSetpoint mapping;
   - NaN attitude-disable rule;
   - true pivot contract;
   - stale-command watchdog requirement;
   - direct pinned `px4_msgs` production contract.

3. PX4 v1.17 pinned source audited while producing `px4_contract_v1.md`
   - `RoverSpeedSetpoint.msg`
   - `RoverRateSetpoint.msg`
   - `RoverAttitudeSetpoint.msg`
   - `OffboardControlMode.msg`
   - `DifferentialSpeedControl`
   - `DifferentialRateControl`
   - `DifferentialAttControl`
   - `DifferentialActControl`
   - `RoverDifferential`
   - `dds_topics.yaml`

---

## 28. Next Implementation Step

Once this document is reviewed and frozen:

```text
1. Define dyx_interfaces/msg/MotionSetpoint.msg
2. Add interface-level tests/schema checks
3. Implement pure C++ MotionSetpoint validator
4. Add stale-command watchdog tests
5. Define ValidatedMotionSetpoint/rejection diagnostics
6. Implement dyx_motion_control node wrapper
7. Implement dyx_px4_gateway mapping
8. Run DDS/PX4 hardware proof
9. Only then connect full RPP output
```

No RPP control implementation should depend on undocumented MotionSetpoint behavior.

---

# End of Contract
