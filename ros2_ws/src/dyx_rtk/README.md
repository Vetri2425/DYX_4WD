# dyx_rtk

## Authority

> "RTK owns correction delivery."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 16 has no literal "Authority:" line or prose authority sentence -- it opens directly with a Responsibilities list. This quote is taken from Section 29's Production Authority Summary, the closest canonical one-line ownership statement in the document.

## Must not

> DERIVED — NOT FROM V1 SPEC: Section 16 has no explicit "must not" list. Inferred from Section 29's single-decision-per-module rule and RTK's scoped responsibility list.

- command rover motion or steering (motion ownership belongs to RPP/Motion Control, Sections 9/12)
- decide mission state (that belongs to dyx_mission, Section 8)

---

Skeleton only -- Milestone 1. No control logic implemented.
