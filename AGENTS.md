# Repository Agent Instructions

<!-- OPENSPEC-SPECKIT-GLOBAL:START -->
## Shared Agent Protocols

Read `$HOME/.agents/AGENTS.md` for user-global workflow rules, including the
OpenSpec/Speckit protocol and project bootstrap contract.
<!-- OPENSPEC-SPECKIT-GLOBAL:END -->

## Repository Scope

- `workBenches` owns shared launcher and layered-image source files.
- Each bench under `devBenches/` is a separate repository and submodule.
- Run image, container, and Docker validation through the declared bench tooling.
- Preserve unrelated changes in the parent checkout and in bench submodules.

<!-- SPECKIT START -->
Active implementation plan: `specs/160-rclone-manifest-import/plan.md` (v1.6.2 Tools Rclone connector; stacked on company connection work).
<!-- SPECKIT END -->
