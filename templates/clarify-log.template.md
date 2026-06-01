# Clarify Log — {{FEATURE_NAME}}

<!--
  TOP-OF-FILE SENTINELS. These two lines are the contract every reader branches on.
  Keep them on their own lines, in this order, immediately below this comment.
  Readers (spec-clarify-resume) do a cheap grep of these before doing anything else.

  GENERATION: PENDING | COMPLETE
    PENDING  -> the reviewer fan-out is still authoring questions (or has not started)
    COMPLETE -> every reviewer angle has finished; no new question blocks will be added
  CLARIFY: IN_PROGRESS | COMPLETE
    IN_PROGRESS -> answers not yet applied to spec.md; protocol still running
    COMPLETE    -> all answers applied to spec.md; protocol finished, loop may exit
-->
GENERATION: PENDING
CLARIFY: IN_PROGRESS

spec: {{SPEC_PATH}}
constitution: {{CONSTITUTION_PATH}}
created: {{TS}}

---

<!--
  QUESTION BLOCKS
  - Append-only during generation. The fan-out writes one block per question.
  - Reviewer angles (agent field): data-model | edge-cases | security-compliance | testability | integration
  - status:      OPEN | ANSWERED
  - class:       normal | critical   (critical = clinical / regulated / safety-impacting)
  - answered_by: human | architect-ai
  - A `class: critical` block answered by `architect-ai` does NOT count as resolved
    for completion purposes until a human re-answers or confirms it (force-escalation).

  COPY THIS BLOCK PER QUESTION, increment N, and fill the fields:

## Q{{N}}
- id: q{{N}}
- status: OPEN
- class: normal
- agent: {{REVIEWER_ANGLE}}
- question: {{QUESTION_TEXT}}
- answer:
- answered_by:
- ts:

-->
