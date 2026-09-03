# DYX 4WD — Vehicle Geometry & Estimator Physical Contract V1

**Status:** PRE-COMMISSIONING BASELINE  
**Physical measurements:** NOT YET AVAILABLE  
**Rule:** No dimensions, offsets, orientations, or antenna baselines may be invented.  
**Purpose:** Define exactly what must be measured before estimator precision validation and autonomous control commissioning.

---

## 1. Authority

This document defines the physical geometry contract between:

```text
Vehicle hardware
      ↓
PX4 EKF2
      ↓
dyx_px4_gateway
      ↓
Trajectory / Mission
      ↓
DYX RPP
```

PX4 owns state estimation.

RPP and trajectory shall consume the resulting vehicle state but shall not independently correct for unknown or guessed sensor geometry.

---

## 2. Canonical Vehicle Body Frame

DYX uses the PX4 body-frame convention:

```text
X = Forward
Y = Right
Z = Down
```

Canonical body reference point:

```text
BODY_ORIGIN = vehicle reference / centre-of-body point
```

The exact physical definition and surveyed location of this point are:

```text
STATUS = TBD — MEASUREMENT REQUIRED
```

No software component may assume that the FCU, IMU, GNSS antenna, or nozzle is located at the body origin.

---

## 3. Required Physical Measurements

Before precision estimator commissioning, measure and record all positions in metres relative to `BODY_ORIGIN`.

### FCU / IMU

```text
imu_x_m = TBD
imu_y_m = TBD
imu_z_m = TBD
```

Also record mounting orientation:

```text
imu_roll_mount_deg  = TBD
imu_pitch_mount_deg = TBD
imu_yaw_mount_deg   = TBD
```

The FCU/IMU is explicitly allowed to be mounted away from vehicle centre.

---

## 4. Master RTK Antenna / Nozzle

Production physical rule:

```text
MASTER RTK ANTENNA = NOZZLE CONTROL POINT
```

Its body-frame position must be measured:

```text
master_nozzle_x_m = TBD
master_nozzle_y_m = TBD
master_nozzle_z_m = TBD
```

This point is the primary marking accuracy control point.

Do not replace it with vehicle-centre position when calculating true marking accuracy.

---

## 5. Slave RTK Antenna

Measure:

```text
slave_x_m = TBD
slave_y_m = TBD
slave_z_m = TBD
```

The master-to-slave vector is therefore:

```text
baseline_x =
    slave_x_m - master_nozzle_x_m

baseline_y =
    slave_y_m - master_nozzle_y_m

baseline_z =
    slave_z_m - master_nozzle_z_m
```

Derived baseline length:

```text
baseline_length_m =
    sqrt(
        baseline_x² +
        baseline_y² +
        baseline_z²
    )
```

All values remain `TBD` until physically measured.

---

## 6. Dual-GNSS Heading Geometry

Record:

```text
master_to_slave_baseline_length_m = TBD
master_to_slave_body_yaw_deg      = TBD
vertical_baseline_offset_m         = TBD
```

The sign and orientation must be experimentally validated against the PX4 NED yaw convention.

No software shall infer antenna ordering or heading sign from CAD assumptions.

---

## 7. Rover Dimensions

Required measurements:

```text
wheel_track_m = TBD
wheelbase_m   = TBD

vehicle_length_m = TBD
vehicle_width_m  = TBD
```

Definitions:

```text
wheel_track =
    lateral distance between left and right wheel
    centre lines

wheelbase =
    longitudinal distance between front and rear
    axle/wheel centre lines
```

For PX4 differential-rover control, wheel track is the primary differential geometry parameter.

Wheelbase remains part of the DYX physical model and commissioning record.

---

## 8. Wheel Geometry

Record:

```text
front_left_wheel_radius_m  = TBD
front_right_wheel_radius_m = TBD
rear_left_wheel_radius_m   = TBD
rear_right_wheel_radius_m  = TBD
```

If all wheels are verified identical, a single nominal value may later be frozen.

Do not assume equality before measurement.

---

## 9. PX4 Estimator Geometry Mapping

Once measured, the relevant PX4 estimator configuration must be derived from this document.

### IMU position

Candidate PX4 parameters:

```text
EKF2_IMU_POS_X
EKF2_IMU_POS_Y
EKF2_IMU_POS_Z
```

Values shall represent the measured IMU displacement relative to the chosen vehicle body reference according to PX4 parameter semantics.

### Primary GNSS antenna position

Candidate PX4 parameters:

```text
EKF2_GPS_POS_X
EKF2_GPS_POS_Y
EKF2_GPS_POS_Z
```

These shall be populated from the measured Master/Nozzle geometry only after sign/frame verification.

### GNSS heading

Relevant estimator contract:

```text
EKF2_GPS_CTRL
EKF2_GPS_YAW_OFF
```

Exact production values are not frozen by this document.

---

## 10. Vehicle Attitude / FCU Mounting

The physical orientation of the FCU must be measured and mapped to PX4's board-orientation configuration.

No assumption is permitted that:

```text
FCU X axis == vehicle X axis
FCU Y axis == vehicle Y axis
FCU Z axis == vehicle Z axis
```

until verified.

Required evidence:

```text
vehicle facing known North
vehicle level
PX4 reported roll/pitch/yaw checked
positive physical yaw direction checked
```

---

## 11. Estimator Output Reference

A critical commissioning goal is to determine and verify exactly which physical point the configured PX4 estimated position represents after all lever-arm corrections.

The system must never compare positions belonging to different physical points.

Forbidden comparison:

```text
EKF body-reference position
        vs
raw Master/Nozzle position
```

unless both have first been transformed to the same physical point.

---

## 12. Nozzle Position Transformation

Once geometry is measured, DYX may derive nozzle position from body state:

```text
P_nozzle =
    P_body +
    R_body_to_navigation ×
    lever_arm_body_to_nozzle
```

For planar rover operation this is primarily dependent on:

```text
body position
yaw
measured nozzle X/Y offset
```

The implementation must use the same body-frame and yaw convention defined by the estimator contract.

---

## 13. Precision Ground Truth

Because:

```text
Master RTK antenna = Nozzle
```

the Master receiver position during valid RTK FIX is the preferred direct external measurement of the marking control point.

The estimator validation shall therefore compare:

```text
PX4-derived estimated nozzle position
                 vs
raw Master RTK/nozzle position
```

after timestamp alignment and coordinate transformation.

This comparison is for estimator validation.

Final mission marking error must separately compare the actual nozzle position against the surveyed target coordinate.

---

## 14. Pivot / Spot-Turn Physical Contract

The system shall not assume a perfect mathematical rotation about the body origin.

During:

```text
speed_mps = 0
yaw_rate_rad_s != 0
```

the real rover may translate because of:

```text
tyre scrub
wheel slip
unequal traction
surface deformation
mass distribution
motor mismatch
```

This motion is defined as physical pivot walk.

PX4 estimator must report the actual resulting displacement.

RPP must use the post-pivot estimator state rather than assuming unchanged position.

---

## 15. Pivot Commissioning Test

After geometry and estimator configuration are complete:

1. Place rover stationary with RTK FIX.
2. Record body estimate and Master/nozzle position.
3. Perform a controlled spot rotation.
4. Return to STOP.
5. Record final body estimate and Master/nozzle position.
6. Calculate actual nozzle displacement.
7. Calculate estimated nozzle displacement.
8. Compare both.

Required result fields:

```text
pivot_angle_deg
raw_master_dx_m
raw_master_dy_m
raw_master_radial_m

estimated_nozzle_dx_m
estimated_nozzle_dy_m
estimated_nozzle_radial_m

estimator_vs_master_error_m
```

No acceptance threshold is frozen until hardware data exists.

---

## 16. Straight-Line Estimator Validation

Required tests:

```text
stationary
slow straight
normal-speed straight
forward/reverse hardware test if permitted
left/right turn
spot turn
stop after motion
```

For each case record:

```text
RTK fix state
Master raw position
PX4 global position
PX4 local position
PX4 attitude
estimated nozzle position
estimator health flags
GNSS quality
timestamp
```

---

## 17. Configuration Ownership

Physical measurements belong in a single versioned DYX geometry configuration.

Conceptual configuration:

```yaml
vehicle:
  body_origin:
    definition: TBD

  imu:
    x_m: TBD
    y_m: TBD
    z_m: TBD
    roll_deg: TBD
    pitch_deg: TBD
    yaw_deg: TBD

  master_nozzle:
    x_m: TBD
    y_m: TBD
    z_m: TBD

  slave_gnss:
    x_m: TBD
    y_m: TBD
    z_m: TBD

  chassis:
    wheel_track_m: TBD
    wheelbase_m: TBD
    length_m: TBD
    width_m: TBD
```

This is illustrative only.

No production numeric values exist yet.

---

## 18. Parameter Governance

Geometry parameters are:

```text
IDLE_ONLY
```

They shall not be modified while an autonomous mission is active.

Any production geometry change requires:

```text
physical re-measurement
configuration revision
estimator validation
pivot validation
recorded commissioning evidence
```

---

## 19. Required Commissioning Evidence

Before declaring localisation production-ready, retain:

```text
vehicle geometry measurement sheet
photos of measurement reference points
FCU mounting/orientation record
Master antenna/nozzle location
Slave antenna location
antenna baseline
wheel track
wheelbase
PX4 parameter export
GNSS receiver configuration
stationary estimator log
straight-run log
turn log
pivot log
RTK FIX evidence
estimator health evidence
comparison report
```

---

## 20. Production Readiness Gate

Localisation shall remain:

```text
NOT COMMISSIONED
```

until all mandatory geometry fields are measured and the estimator has been validated against the Master/nozzle RTK truth.

The firmware may be used for controlled commissioning tests before this gate passes.

It shall not be described as production centimetre-accuracy localisation until hardware validation is complete.

---

# Current State

```text
PX4 source interface audit        COMPLETE
Estimator parameter audit        COMPLETE
DDS estimator telemetry audit    COMPLETE

Physical vehicle geometry        NOT MEASURED
FCU/IMU lever arm                 NOT MEASURED
Master/nozzle lever arm           NOT MEASURED
Slave lever arm                   NOT MEASURED
Dual-GNSS baseline                NOT MEASURED
Wheel track                       NOT MEASURED
Wheelbase                         NOT MEASURED

Estimator hardware validation     NOT STARTED
RTK truth comparison              NOT STARTED
Pivot localisation validation     NOT STARTED
```

**Next gate:** obtain physical measurements and freeze `vehicle_geometry_v1`.