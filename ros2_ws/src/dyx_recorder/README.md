# dyx_recorder

## Authority

> "Recorder owns field evidence."

(architecture doc: `docs/architecture/DYX_4WD_Production_Stack_Architecture_V1.md`)

> Judgement call: Section 19 has no literal "Authority:" line. This quote is taken from Section 29's Production Authority Summary.

## Must not

> DERIVED — NOT FROM V1 SPEC: Section 19 has no explicit "must not" list. Inferred from Section 19 ("production component, must not remain a developer script") and Section 21 (Service 4 failure independence).

- participate in control decisions or gate control-loop execution -- it must keep recording even if the backend fails (Section 21, Service 4)
- remain a developer script -- it is a production component (Section 19, explicit)

---

Skeleton only -- Milestone 1. No control logic implemented.
