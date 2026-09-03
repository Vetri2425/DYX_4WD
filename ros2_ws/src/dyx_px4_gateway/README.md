# dyx_px4_gateway

## Authority

> "Translate approved rover motion into PX4 DDS commands and return PX4 state."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 13 has no explicit "px4_gateway must not" list. The first bullet is inferred from its Authority line's own wording ("approved" implies it does not originate decisions); the second is the explicit rule stated for *other* packages, restated here as this package's boundary.

## Must not

- make path, mission, or steering decisions -- it only translates already-approved commands (Section 13: "translate approved rover motion")
- let other packages bypass it and publish PX4 DDS topics directly unless explicitly approved (Section 13)

---

Skeleton only -- Milestone 1. No control logic implemented.
