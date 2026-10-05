## 1. Governance and handoff

- [x] 1.1 Ratify the Layer 3, launch and restart-notice decisions in this change (Brett Heap, 2026-09-29, verbatim "ratify the OpenSpec change when it's green"; record in `review/ratification-2026-09-29.md`).
- [x] 1.2 Define and implement Speckit feature `016-launch-current-claude` for the Layer 3 user copy, the launcher's resolution through `claude-current`, and the status line restart notice, with focused regression coverage.

## 2. Verification and delivery

- [x] 2.1 Run the feature's suites in the declared bench test environment and record the local counts (#105: the claude-profile suites have no CI of their own), without altering running sessions.
- [x] 2.2 Archive this change only after feature 016 and the `opensoft/openRepoTools` commands it calls have landed, and after `prefer-updated-claude`, `refresh-shared-ai-cli-tooling` and `repair-ai-cli-runtime-layout` are archived.
