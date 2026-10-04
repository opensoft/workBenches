# Launch-current-Claude delivery verification

Verified on 2026-10-04 in the `py-bench` dev container against workBenches test revision `4f287be5dd79f1742a22e410cfa9372cf65b5e20` (runtime base `0e51e1b9529b15106930a18d849198a4111bfcf3`) and openRepoTools PR head `900aa9278dab785e637880c87d0562db24040b3b`, merged with main `82ecebee13edaa915b68550170faffdf761754d5`.

Feature 016 landed in workBenches PR #121 (`2c4d7e7`) on 2026-09-29. Its ruled amendments landed in PR #122 (`18a2fca`), with Speckit alignment in PR #123 (`86750e7`). All fourteen implementation tasks are complete.

Eighteen focused workBenches suite invocations passed. Nine previously uncounted suites now report successful assertions explicitly; counters include repeated fixture checks and preserve the existing failure paths. The counts below were read from those suite outputs. Test fixtures stub CLI, registry and Docker calls; this verification did not rebuild an image, install commands, or restart a session.

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

The openRepoTools focused wrapper run passed **443 tests**, with 411 deselected, in 170.92 seconds. It covered resolver/update locking, restart detection, direct lane-start resolution, installer/receipt behavior, hooks, guards and repository hygiene. Strict `openspec validate launch-current-claude --strict` passed.

Delivery remains gated on openRepoTools PR #134 and its current-head CI. The OpenSpec archive task 2.2 stays open until those commands land. The three prerequisite changes have already been archived. Neither this record nor task 1.2/2.1 completion declares #134 merged or authorizes runtime deployment.
