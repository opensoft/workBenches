# Implementation Plan: Bench Process Reaping

## Authority and Scope

Implement OpenSpec change `fix-bench-reaping`. Only py-bench is authorized for live replacement. Preserve parent/submodule changes and unrelated live containers.

## Approach

Set `init: true` in the shared Wave Compose override. Expand launcher regression fixtures to capture the generated override and verify reaping is present across creation and repair. Use the changed launcher with the canonical workBenches root to retain declared mounts during activation.

## Verification

Run the launcher regression suite and Bash syntax checks inside the declared bench. Require a red regression with the unchanged launcher, then green with the feature launcher. Check merged Compose configuration for init and image/user metadata without printing environment contents. Inspect writable-layer changes before replacement. Repair only py-bench; verify runtime init, ten consuming-shell exits, zero zombies, user/group 1000 and two ordinary Wave checks retaining identity. Compare unrelated bench IDs and start times.

## Delivery

Keep source and verification evidence in this numbered feature worktree. Do not archive OpenSpec before landing. Report live activation separately from publication status.
