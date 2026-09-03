# dyx_interfaces

## Authority

> "Define shared ROS messages, services, and actions."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 6 has no literal "Authority:" line (unlike trajectory/mission/rpp/motion_control/px4_gateway); this is the section's "Purpose:" line, used as the closest equivalent.

## Must not

- contain any control logic (Section 6: "No control logic is allowed here.")
- author .msg/.srv/.action files yet -- interface freeze is Milestone 2 (Section 55), after the PX4 DDS gateway is proven (Section 56, step 6 comes after step 4/5)

---

Skeleton only -- Milestone 1. No control logic implemented.
