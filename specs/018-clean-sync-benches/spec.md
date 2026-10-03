# Feature: Clean and synchronize workBenches

Authorized scope: implement the approved cleanup plan while preserving all existing changes and live workloads. Governance: `openspec/changes/clean-sync-benches/`.

Acceptance: every retained repository checkout is clean and matches its intended upstream, or has an explicit review/maintenance exception. All eight parent gitlinks match intended child commits. Existing open feature PRs and their worktrees remain recoverable. No credentials or host-specific absolute paths enter committed artifacts.

Do not confuse clean Git status with activation of container configuration or completion of an application/database upgrade.
