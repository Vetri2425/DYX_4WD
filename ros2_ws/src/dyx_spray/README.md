# dyx_spray

## Authority

> "Spray owns marking actuator execution."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 17 has no literal "Authority:" line; its opening sentence ("Spray control stays independent from RPP") is a boundary statement, not an authority statement. This quote is taken from Section 29's Production Authority Summary instead, for consistency with the other packages that lack an explicit Authority: header.

## Must not

- decide when to mark -- Mission Manager requests marking, Spray only executes it (Section 17)
- calculate path or steering

---

Skeleton only -- Milestone 1. No control logic implemented.
