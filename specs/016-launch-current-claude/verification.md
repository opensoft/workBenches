# Launch-current-Claude delivery verification

Verified on 2026-10-04 in the `py-bench` dev container against workBenches test revision `a31152c4070345f756b87f19f1fef3083b20701d` (runtime base `0e51e1b9529b15106930a18d849198a4111bfcf3`) and openRepoTools PR head `6ed41896c1b3701b7da44e20dc6711e41ba309fc`, merged with main `82ecebee13edaa915b68550170faffdf761754d5`. The per-revision resolver results below distinguish the full focused run from the final narrow validation fix.

Feature 016 landed in workBenches PR #121 (`2c4d7e7`) on 2026-09-29. Its ruled amendments landed in PR #122 (`18a2fca`), with Speckit alignment in PR #123 (`86750e7`). All fourteen implementation tasks are complete.

Eighteen focused workBenches suite invocations passed. Nine previously uncounted suites now report successful assertions explicitly; counters include repeated fixture checks and preserve the existing failure paths. The counts below were read from those suite outputs. Test fixtures stub CLI, registry and Docker calls; this verification did not rebuild an image, install commands, or restart a session.

All eighteen commands below were rerun exactly as written after the relative-path fixes. The harness cleared ambient `CLAUDE_*`, `LANES_*`, `WORKBENCHES_CLAUDE_*` and `TMUX*` variables and set `WORKBENCHES_CLAUDE_CURRENT_BIN=/nonexistent/resolver` and `WORKBENCHES_CLAUDE_RESTART_CHECK_BIN=/nonexistent/restart-check`. The binary-selection suite supplies its own resolver fixtures.

| Invocation from the repository root | Exact passing count |
|---|---|
| `bash devcontainer.test/test-claude-profile-binary-selection.sh base-image/files/claude-profile` | 122 assertions |
| `bash devcontainer.test/test-claude-profile-lane-default.sh base-image/files/claude-profile` | 49 scenarios; 206 assertions |
| `bash devcontainer.test/test-claude-profile-lane-start.sh base-image/files/claude-profile` | 21 assertions |
| `bash devcontainer.test/test-claude-profile-session-start-hook.sh base-image/files/claude-profile` | 13 scenarios; 36 assertions |
| `bash devcontainer.test/test-claude-profile-name-guard-hook.sh base-image/files/claude-profile` | 27 scenarios; 59 assertions |
| `bash devcontainer.test/test-claude-profile-amendment-11.sh base-image/files/claude-profile` | 111 scenarios; 467 assertions |
| `bash devcontainer.test/test-claude-profile-skill-install.sh base-image/files/claude-profile` | 11 scenarios; 142 assertions |
| `bash devcontainer.test/test-claude-profile-preserves-model.sh` | 6 assertions |
| `bash devcontainer.test/test-claude-profile-lane-default.sh base-image/files/lclaude` | 49 scenarios; 206 assertions |
| `bash devcontainer.test/test-claude-profile-lane-start.sh base-image/files/lclaude` | 21 assertions |
| `bash devcontainer.test/test-claude-usage-guard-auto-swap.sh` | 25 scenarios; 102 assertions |
| `bash devcontainer.test/test-claude-tmux-statusline.sh base-image/files/claude-profile base-image/files/claude-statusline-command.sh` | 16 assertions |
| `bash devcontainer.test/test-claude-tmux-statusline-env-isolation.sh base-image/files/claude-profile base-image/files/claude-statusline-command.sh` | 5 assertions |
| `bash devcontainer.test/test-claude-statusline-snapshots.sh base-image/files/claude-statusline-command.sh` | 19 assertions |
| `bash devcontainer.test/test-ai-cli-install-summary.sh` | 38 assertions |
| `bash devcontainer.test/test-layer3-codex-version.sh` | 18 assertions |
| `bash devcontainer.test/test-layer3-claude-version.sh` | 43 checks |
| `bash devcontainer.test/test-ensure-layer3-freshness.sh` | 12 assertions |

The latest openRepoTools focused wrapper run passed **453 tests**, with 411 deselected, in 180.65 seconds on `9ef4c0d09b1444d9f01e7ebc2a62cf6f66fbc93a`. It covered resolver/update locking, restart detection, direct lane-start resolution, installer/receipt behavior, hooks, guards and repository hygiene. Strict `openspec validate launch-current-claude --strict` passed. The original 443-test run passed on `900aa9278dab785e637880c87d0562db24040b3b`; its initial workBenches tests used revision `4f287be5dd79f1742a22e410cfa9372cf65b5e20`.

A subsequent resolver review found that relative cache paths could give two checkouts independent locks for the same user installation. openRepoTools commit `66d786296db096aad529077fe1923e9c64136c43` anchors those paths under `$HOME` and adds concurrent-checkout regressions for both `CLAUDE_CURRENT_CACHE_DIR` and `XDG_CACHE_HOME`. On that exact head, `bash tests/run.sh -k 'claude_current or claude_restart_check or repo_hygiene or openrepotools_command or install_skill_and_hook or guard_launch_mode'` passed **445 tests**, with 411 deselected, in 216.19 seconds. The same invocation produced a 451-test result in 179.22 seconds on `208e50672ba05390892e87dd21e334aaeffaa49b`: that head additionally preflights Claude before a binding handoff or other lane mutation and qualifies version-only notices as `NEWER COPY INSTALLED`, leaving selection to the next registry check. Replaced binaries retain `RESTART NEEDED`. These fixes do not change the calling interface or workBenches runtime.

The 453-test result adds regressions for a declined handoff performing no resolver call/update and for selecting the completed handoff's agent. `9ef4c0d09b1444d9f01e7ebc2a62cf6f66fbc93a` preflights a possible Claude replacement only after handoff approval and before release, then reads the agent afresh. The final head `6ed41896c1b3701b7da44e20dc6711e41ba309fc` additionally requires a regular executable file in resolver output. Its `bash tests/run.sh -k resolver_that_names_nothing_runnable` run passed **6 tests**, with 859 deselected, in 9.79 seconds, including a searchable directory. Full current-head CI remains the suite of record.

Delivery remains gated on openRepoTools PR #134 and its current-head CI. The OpenSpec archive task 2.2 stays open until those commands land. The three prerequisite changes have already been archived. Neither this record nor task 1.2/2.1 completion declares #134 merged or authorizes runtime deployment.

Review reproduced dangling fixture symlinks when either lane suite was given a relative `lclaude` path. Test revision `39b1f5c9365bb84b1e6528959849be5d7921e2fd` canonicalizes the launcher argument before constructing those symlinks. Both lane-default and lane-start commands in the table were rerun exactly as written, for both `claude-profile` and `lclaude`: all four passed with the same 49 scenarios/206 assertions and 21 assertions respectively. The original eighteen-suite run used absolute paths; the table's relative lane invocations are supported and verified by this follow-up.

The subsequent exact-command sweep found the Amendment 11 suite changed its working directory before resolving a relative launcher argument. Test revision `a31152c4070345f756b87f19f1fef3083b20701d` resolves that argument first. The complete eighteen-command table then passed with the counts shown above.
