# dyx_system_gateway

## Authority

> "This is the single ROS-to-backend boundary."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 18 has no literal "Authority:" line. This is its own descriptive first sentence; Section 29's Production Authority Summary phrases it as "owns Backend <-> ROS boundary", which is equivalent.

## Must not

- let backend code subscribe directly to ROS (Section 18, explicit)
- let any ROS control node depend on FastAPI (Section 18, explicit)

---

Skeleton only -- Milestone 1. No control logic implemented.
