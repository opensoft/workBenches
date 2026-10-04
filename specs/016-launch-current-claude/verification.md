# Launch-current-Claude delivery verification

Verified on 2026-10-04 in the `py-bench` dev container against workBenches main `0e51e1b` and the openRepoTools resolver branch merged with main `82ecebe`.

Feature 016 landed in workBenches PR #121 (`2c4d7e7`) on 2026-09-29. Its ruled amendments landed in PR #122 (`18a2fca`), with Speckit alignment in PR #123 (`86750e7`). All fourteen implementation tasks are complete.

Eighteen focused workBenches suite invocations passed. Test fixtures stub CLI, registry and Docker calls; this verification did not rebuild an image, install commands, or restart a session.

| Suite | Result |
|---|---|
| `test-claude-profile-binary-selection.sh` | claude-current resolution: 72 checks passed; PASS: Claude profile binary selection |
| `test-claude-profile-lane-default.sh` | claude-profile lane default: 49 scenarios, 206 assertions passed |
| `test-claude-profile-lane-start.sh` | claude-profile lane-start hand-off tests passed |
| `test-claude-profile-session-start-hook.sh` | claude-profile SessionStart hook: 13 scenarios, 36 assertions passed |
| `test-claude-profile-name-guard-hook.sh` | claude-profile UserPromptSubmit name guard (Amendment 12): 27 scenarios, 59 assertions passed |
| `test-claude-profile-amendment-11.sh` | claude-profile Amendment 11: 111 scenarios, 467 assertions passed |
| `test-claude-profile-skill-install.sh` | lane-swap skill + swap command install (act 4b: --install is the sole writer): 11 scenarios, 142 assertions passed |
| `test-claude-profile-preserves-model.sh` | PASS: Claude profile model preservation |
| `test-claude-profile-lane-default.sh-lclaude` | claude-profile lane default: 49 scenarios, 206 assertions passed |
| `test-claude-profile-lane-start.sh-lclaude` | claude-profile lane-start hand-off tests passed |
| `test-claude-usage-guard-auto-swap.sh` | claude-usage-guard auto-swap: 25 scenarios, 102 assertions passed |
| `test-claude-tmux-statusline.sh` | claude tmux statusline tests passed |
| `test-claude-tmux-statusline-env-isolation.sh` | claude tmux statusline env-isolation regression passed |
| `test-claude-statusline-snapshots.sh` | usage-snapshot publisher populated both files correctly; claude statusline snapshot tests passed |
| `test-ai-cli-install-summary.sh` | ai-cli optional install summaries are status-aware |
| `test-layer3-codex-version.sh` | layer3 Codex version inherits the exact base version and remains overridable |
| `test-layer3-claude-version.sh` | layer3 Claude Code version: 43 checks passed; npm latest by default, exact when named, fail closed otherwise |
| `test-ensure-layer3-freshness.sh` | ensure-layer3 recipe freshness tests passed |

The openRepoTools focused wrapper run passed **443 tests**, with 411 deselected, in 170.92 seconds. It covered resolver/update locking, restart detection, direct lane-start resolution, installer/receipt behavior, hooks, guards and repository hygiene. Strict `openspec validate launch-current-claude --strict` passed.

Delivery remains gated on openRepoTools PR #134 and its current-head CI. The OpenSpec archive task 2.2 stays open until those commands land. The three prerequisite changes have already been archived. Neither this record nor task 1.2/2.1 completion declares #134 merged or authorizes runtime deployment.
