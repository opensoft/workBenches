# Verification and delivery

Date: 2026-10-06. User authorized the automatic startup fallback. Source implemented in branch `020-default-claude-effort`; not committed, pushed, or merged by this request.

## Tests

- Red phase: new argument test failed because default effort was absent.
- Focused effort suite: 52 scenarios, 69 assertions passed, including both CLI forms, profile/inherited effort env, resume, print mode, prompt boundary, utilities, login/status, settings preservation, and tmux server/client effort isolation.
- Amendment 11: 111 scenarios, 465 assertions passed.
- Binary selection: 122 assertions passed; underlying resolver reported 72 checks passed.
- Lane default: 49 scenarios, 206 assertions passed.
- Lane-start handoff: 21 assertions passed.
- Name guard: 27 scenarios, 59 assertions passed.
- Model preservation: 6 assertions passed.
- SessionStart hook: 13 scenarios, 36 assertions passed.
- Skill installation: 11 scenarios, 142 assertions passed.
- Lane default through lclaude: 49 scenarios, 206 assertions passed.
- Bash syntax, diff whitespace, and strict OpenSpec validation passed.
- ShellCheck was unavailable; existing suites reported known vendored documentation findings. Those unrelated findings are unchanged.

All tests used isolated manifests/profiles and mock Claude binaries. No provider request or live credential authentication was used to prove model effort.

## Live installation

Atomic launcher replacement and byte comparison completed in cloud-bench, py-bench, m365-bench, and cpp-bench. The host claude-profile symlink now resolves to this feature worktree's tested launcher. Previous files/link were backed up before replacement. Every installed launcher, including the host-linked copy tested through cloud-bench's shared host mount, passed the 52-scenario focused suite.

Installed source SHA-256: `f61f7123572c1cb3e48b8187bf4749e380e067d51458715691acfe371ef2c1b0`.

Backup records (runtime paths expressed portably):

- Host: `$HOME/.local/state/workbenches/launcher-backups/effort-020.LpI011/claude-profile` (original symlink).
- cloud-bench: `$LAUNCHER_BACKUP_ROOT/effort-020.xRmeRt/claude-profile`.
- py-bench: `$LAUNCHER_BACKUP_ROOT/effort-020.MomJhf/claude-profile`.
- m365-bench: `$LAUNCHER_BACKUP_ROOT/effort-020.qgH7d3/claude-profile`.
- cpp-bench: `$LAUNCHER_BACKUP_ROOT/effort-020.WfSg8z/claude-profile`.

`LAUNCHER_BACKUP_ROOT` is each container's installation-prefix-relative `share/workbenches/launcher-backups` directory. Rollback restores only that launcher's previous file/link atomically from its listed backup, then byte-compares it. No credentials or profile data are included in these backups.

## Boundaries and remaining rollout

No existing session, container, model setting, credential, or unrelated checkout was restarted or rewritten. Parent checkout remains on main with its pre-existing cloudBench submodule dirtiness preserved. py-bench-advance does not have the standard brett user and was not altered.

This is a live rollout, not a merged or image-persistent release. Keep the feature worktree while the host link points to it. A host profile setup run can reset that link to main; a container recreation from the current image can restore the previous launcher. Merge the source through the normal review workflow before the next estate setup/image rebuild. Rebuilding or merging was not performed by this request.

## Publication verification — 2026-10-26

The user requested committing and pushing unpublished work. Before publication,
the following checks were rerun in py-bench against this worktree:

- Focused effort suite: 52 scenarios, 69 assertions passed.
- Binary selection: 122 assertions passed, including 72 resolver checks.
- Lane default: 49 scenarios, 206 assertions passed.
- Lane-start handoff: 21 assertions passed.
- Amendment 11: 111 scenarios, 467 assertions passed; the suite still reports
  its explicitly identified pre-existing vendored documentation findings.
- Bash syntax, diff whitespace, and strict OpenSpec validation passed.
- A high-confidence token/private-key pattern scan found no matches in the
  feature diff or newly added files. This is not an exhaustive secret audit.

This publication does not merge the feature, rebuild images, restart sessions,
or reverify the historical live-installation claims above.
