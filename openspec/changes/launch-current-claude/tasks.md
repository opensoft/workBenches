## 1. Speckit handoff

- [ ] 1.1 After this change is ratified, define and implement Speckit feature `016-launch-current-claude` for the Layer 3 user copy, the launcher's resolution through `claude-current`, and the status line restart notice, with focused regression coverage.

## 2. Verification and delivery

- [ ] 2.1 Run the feature's suites in the declared bench test environment and record the local counts (#105: the claude-profile suites have no CI of their own), without altering running sessions.
- [ ] 2.2 Archive this change only after feature 016 and the `opensoft/openRepoTools` commands it calls have landed, and after `prefer-updated-claude` is archived.
