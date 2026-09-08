---
name: "speckit-specify"
description: "Codex wrapper for the Speckit specification workflow."
---
<!-- speckit-overlay-shape: 1 -->

# speckit-specify

Slash label: `/speckit.specify`.

Use `../../../.agents/skills/speckit-specify/SKILL.md` as the source workflow.

Rules:
- Read the source skill before doing anything else.
- Treat text after `/speckit.specify` as the original command input for the source skill.
- Execute the source skill exactly, including prerequisite checks, file generation, and summary output.
- Honour the source skill's "Three-leg projects" rules when the `before_specify` hook reports `REPO_SHAPE: "three-leg"`: spec files go under `FEATURE_DIR`, `.specify/feature.json` lives at `PROJECT_ROOT`, and follow-on commands run from `PROJECT_ROOT`.
