---
name: "speckit-git-feature"
description: "Codex wrapper for the Speckit git feature workflow."
---
<!-- speckit-overlay-shape: 1 -->

# speckit-git-feature

Slash label: `/speckit.git.feature`.

Use `../../../.agents/skills/speckit-git-feature/SKILL.md` as the source workflow.

Rules:
- Read the source skill before doing anything else.
- Pass any text after `/speckit.git.feature` through as the original command input for the source skill.
- Execute the source skill exactly, including branch creation behavior.
- The hook is shape-aware: in an openRepoShape three-leg project it creates the branch and a worktree in BOTH legs and returns `REPO_SHAPE`, `PROJECT_ROOT`, `SPEC_WORKTREE_PATH`, `CODE_WORKTREE_PATH`, and `FEATURE_DIR`. Never run it against the assembly root expecting a root branch.
