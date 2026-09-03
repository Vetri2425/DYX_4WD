# dyx_bringup

## Authority

> "dyx_bringup is the only production ROS launch authority."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 20 phrases this as a plain sentence, not under an "Authority:" heading like Sections 7/8/9/12/13. Used verbatim since it is already authority-shaped.

## Must not

- hard-code tuning values in launch files (Section 20, explicit)
- use Python launch logic unless genuinely required -- XML is preferred (Section 20)

---

Skeleton only -- Milestone 1. No control logic implemented.
