# dyx_rpp

## Authority

> "How should the rover move to follow the active path?"

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 9 does not contain an explicit "RPP must not" list (unlike trajectory/mission/motion_control). This list is derived from Section 14 ("PX4 owns") and Section 10 (control ownership split) -- flagged as a judgement call.

## Must not

- perform state estimation (Section 14: PX4 owns EKF/attitude/position estimation)
- close the inner speed or yaw-rate control loop (Section 14: PX4 owns inner control)
- perform differential-drive actuator allocation (Section 14: PX4 owns this)
- arm/disarm PX4 directly (that transport belongs to dyx_px4_gateway, Section 13)

---

Skeleton only -- Milestone 1. No control logic implemented.
