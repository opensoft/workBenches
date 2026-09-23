# Design

## Context

The Claude profile launcher currently owns profile configuration, binary choice, tmux setup, lane resolution, `lane-start` handoff, and lane identity exported to hooks. `lane` and `lane-handoff` in openRepoTools call or print `pclaude`; the in-force lane protocol names bare `pclaude` as the restart command.

## Goals / Non-Goals

**Goals:** Make lane selection opt-in by entry point while sharing one profile and tmux implementation. Preserve explicit legacy callers during rollout. Keep lane identity absent from profile-only sessions.

**Non-Goals:** Change lane matching precedence, lane storage, the Claude binary selector, or the tmux default for interactive profile sessions.

## Decisions

1. Install `lclaude` as a small wrapper that calls `pclaude` with an internal lane-mode option. The existing launcher remains the single owner of profile and tmux setup. A wrapper that calls `lane-start` first would duplicate profile setup and risk launching Claude twice.
2. Bare `pclaude` defaults to no lane. The internal mode and explicit `--lane` enable lane behavior; `--no-lane` remains an explicit override. Suppress lane probes, picker, binding exports, and lane identity for plain profile launches. Clear inherited lane identity before launching Claude.
3. Carry lane mode through the interactive tmux re-exec. The child command already carries selected binary and lane facts; it must also carry the new mode marker.
4. Update openRepoTools to prefer `lclaude` for lane launch and restart, falling back to explicit `pclaude --lane` while older workBenches installations exist. Update its source before moving the vendored pin in workBenches.
5. Amend the workstation lane protocol and user-visible restart instructions to name `lclaude`; retain explicit `pclaude --lane` as a migration alias.

## Risks / Trade-offs

- [Bare `pclaude` in an old handoff starts without a lane] → Land openRepoTools fallback first, then install `lclaude` and update restart instructions; retain explicit `pclaude --lane`.
- [Lane mode is lost during tmux re-exec] → Thread the mode explicitly and test an interactive parent-to-child launch.
- [Inherited lane identity triggers a hook for a profile-only session] → Clear lane identity at entry and test nested launch behavior.
- [Running containers retain old launchers] → Treat source merge and container rebuild as separate rollout steps; do not claim existing containers changed.

## Migration Plan

1. Land openRepoTools compatibility that prefers `lclaude` when present and otherwise uses explicit `pclaude --lane`.
2. Land the lane protocol amendment and workBenches launcher, packaging, tests, and pinned openRepoTools copy.
3. Update installed launchers through the normal bench rebuild or setup process. Older containers keep their old behavior until updated.
