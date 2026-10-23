# Contract: setup interfaces and accepted lifecycle extension

**Requirement**: FR-015, SC-009 — existing mode names, schemaVersion and old component payloads stay compatible; the approved setup-workstation-lifecycle extension below adds service keys and prerequisite ordering; existing component queues preserve their schema/payload meaning from the 1.7 TUI; non-interactive modes draw no wizard frame. Restated from `release/1.7.0` at `ccc9eac` so the implementation and `devcontainer.test/test-setup-wizard.py` can check against it.

## `setup.sh` (root launcher)

The interactive TUI is one stage of `setup.sh`, which then validates and applies the selection:

1. `scripts/interactive-setup.sh --select-only "$selection_file"` — the TUI; `$selection_file` comes from `mktemp` and is removed on exit.
2. `python3 scripts/setup_selection.py rows "$selection_file"` — validate.
3. `setup_selection.py empty` → nothing selected: finish without applying or building.
4. `setup_selection.py benches` → the selected bench paths (rejects a path outside `devBenches/`, `sysBenches/`, `bioBenches/` or with `..`); `release-workbenches.py prepare --selection` in a frozen release.
5. `setup_selection.py providers`, `review`, `node`, `docker`, `selected <key>` → credential, dependency and image planning.
6. `scripts/interactive-setup.sh --dependencies-plan "$selection_file"`.
7. `scripts/interactive-setup.sh --apply-plan "$selection_file"`.

Accepted extension: after the TUI saves the private plan, a strict native reader validates the generated JSON before service preflight/install. Selected prerequisites install first; service-only plans skip unrelated component setup. All removals run last, only after successful work. Unsupported host removals and foreign containers refuse before mutation. Other component validation/planning remains as listed above.

## `scripts/interactive-setup.sh` modes

| Invocation | Draws a frame | Loads bench metadata | Behaviour |
|---|---|---|---|
| no arguments (interactive) | yes | yes | Enter on Review applies in-process (`ensure_selected_dependencies`, `process_selections`) |
| `--select-only <file>` | yes | yes | Enter on Review writes `<file>` and exits 0 |
| `--dependencies-plan <file>` | **no** | **no** | loads the selection, checks Node/npm for selected tools |
| `--apply-plan <file>` | **no** | **no** | loads the selection, prepares frozen sources when releasing, runs `process_selections` |
| anything else | no | no | "Unknown setup option: …", exit 2 |

With a TTY on stdin and stdout, interactive and `--select-only` runs paint first and start the background checks (1.7); without one they run the checks synchronously and still draw, reading keys from stdin (suites pipe keys this way).

## Selection file

Written by `save_selection`:

- created in a private mode-0600 temporary file and atomically renamed over an owned regular destination; caller symlinks are rejected, never followed. The native writer needs no Python/Docker;
- JSON:

```json
{"schemaVersion": 1, "components": [{"key": "bench_365Bench", "action": "install"}, {"key": "codex_cli", "action": "update"}]}
```

| Field | Rule (`setup_selection.py load`) |
|---|---|
| `schemaVersion` | exactly `1` |
| `components[]` | each `{key, action}` once; `key` is a known tool key, `wsl`, `docker`, `setup_tools`, `vault`, or `bench_<catalog name>`; `action` is `install`, `update` or `uninstall` |
| service keys | wsl/docker/setup_tools/vault accept install/uninstall only |
| config-only keys | `host_shell`, `workspace_repo`, `ai_accounts`, `workbenches_account` accept `install` only |
| file | private regular file of the current user, not a symlink, at most 64 KiB |

A component is written when `component_checked[key]` is `true` and `component_action[key]` is non-empty; order follows Bash's associative-array iteration, as in 1.7 (consumers do not depend on order). An empty run in `--select-only` writes `{"schemaVersion": 1, "components": []}` (FR-014).

`bench_365Bench` becomes a valid key because 365Bench enters the catalog; nothing in the format changes.

## Exit codes

| Code | When |
|---:|---|
| 0 | applied or written successfully; empty run |
| 1 | an apply step failed (`process_selections` reports failures, including an unresolved bench path, FR-058) |
| 2 | unknown option |
| 130 | Q, closed input, Ctrl+C, or a cancelled helper that propagates cancel |
| 143 | termination |

## Rendering guarantees kept from 1.7

- First frame (containing `Navigation:` and `Loading`, with the blink attribute) is drawn before any Docker, catalog-parsing, Python, Git or network check (FR-038, SC-005).
- Rendering any step runs no `jq`, `python3`, `docker` or `git` (FR-038).
- After first paint only changed lines are written; an unchanged frame writes nothing; the screen is cleared only on first paint, after a helper returns, or on a width or height change (FR-039).
- Q exits 130 within two seconds and leaves no check process running (FR-027, SC-007).


Refinement 029-A06 adds manual reference rows to the browsing catalog only. They have no actions or credential-plan options and are not valid serialized selection keys. Existing native and Python allowlists reject these IDs; no desktop installation is inferred from the corresponding CLI. Presence inventory does not check login.
