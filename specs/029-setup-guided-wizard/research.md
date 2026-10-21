# Research: Guided setup wizard

**Feature**: [`029-setup-guided-wizard`](spec.md) · **Plan**: [plan.md](plan.md) · **Date**: 2026-10-21

This file records the open technical choices that `spec.md`, the OpenSpec `design.md` (D1–D19) and the clarifications left to the plan. Each record gives the decision, why, and the alternatives. Requirements are not reopened here: where a choice is already fixed by the approved design, the record only fixes the implementation detail and cites the decision.

All measurements below were taken on 2026-10-21 on Brett's developer workstation — AMD Ryzen AI MAX+ 395 (32 threads), WSL 2 Ubuntu 24.04, GNU Bash 5.2.21, `LANG=C.UTF-8`. The probes sourced read-only copies of the scripts (`git archive` of `029-setup-guided-wizard` at `8488a6e` and of `prototype/tui-guided-wizard` at `896b481`) with every status stubbed, wrote frames to `/dev/null`, and changed nothing on the machine. Times are medians.

## R1. Render-performance strategy (FR-060, SC-006)

### Measurements

| What | Median |
|---|---:|
| One `$(…)` command substitution inside the sourced setup process (100 × `$(setup_ui_pair …)` = 361–404 ms) | 3.6–4.0 ms |
| One `$( [ … ] && echo … )` (100 × = 350–361 ms) | 3.5–3.6 ms |
| One `$(tput cols)` inside the setup process (100 × = 563–619 ms) | 5.6–6.2 ms |
| One `$(…)` in a small shell / one `$(tput cols)` in a small shell | 2.2 ms / 3.4 ms |
| One `printf -v` pair with padding (100 × = 0.6–4.5 ms) | 0.006–0.045 ms |
| **1.7** `render_setup_frame`, 87 columns: Requirements / main screen (Benches, AI) / main screen (Tools) / Profiles | 69 / 203 / 265 / 24 ms |
| **1.7** `draw_ui`, main screen (also when nothing changed, because it always renders) | 252–255 ms |
| **Prototype** `render_setup_frame`, 87×40: Workstation / Agents, Tools, Review / Benches bench zone / Benches category zone | 175 / 68–73 / 87 / 80 ms |
| **Prototype** `draw_ui` on Benches | 104–106 ms |
| **Prototype** key → redraw on Benches (`handle_input` + `draw_ui` for ↓ ↑ Tab PgDn Tab; 658 ms per 5 keys) | 132 ms per key |
| **Fork-free sketch**: a 32-line Benches frame at 87 columns (head, category block, 8 bench rows, word-wrapped About, footer) built with builtins only, diffed and written | **3.8 ms** |

The prototype builders' 75–115 ms per frame agrees with the prototype rows above. The finding that matters: **1.7 itself already takes ~250 ms per redraw** on this workstation, and the prototype ~130 ms per key. Rendering cost is dominated by forks — every `$(…)`, pipeline and external command costs 3.5–6 ms in a process the size of `interactive-setup.sh` on WSL 2 — not by string work, which is two to three orders of magnitude cheaper. Porting the prototype's renderer would miss the 100 ms budget.

### Decision

The render path forks **zero** times per frame. Concretely:

1. **Frame into an array, not stdout.** `draw_ui` calls a builder that fills the global array `setup_frame_lines` directly; it no longer captures `$(render_setup_frame)` and `mapfile`s it. `render_setup_frame` stays as a thin public shim that builds the array and prints it (suites and the non-hot paths call it).
2. **Helpers return through variables.** Every helper on the render path writes its result with `printf -v "$out"` or a `local -n` nameref instead of printing: `setup_ui_pair`, `setup_ui_rule`, `setup_status_label`, the panel borders, row formatters, the nav, the strip, the footer and the requirement action. `workbenches_requirement_action` lives in `scripts/lib/tools-container.sh` and has other callers, so it is left unchanged and a variable-returning sibling (`workbenches_requirement_action_v`) is added beside it.
3. **No subshell tests.** `$( [ … ] && echo true || echo false )` patterns (about 30 per 1.7 main frame with 9 benches) become plain `[[ … ]]` conditionals.
4. **Static parts cached.** Rules, panel top and bottom borders, the banner and the hint lines are built once per (frame width, layout) key and reused until the width, the height or the layout (roomy/tight) changes.
5. **Derived text cached.** Wrapped About lines are cached per (bench or category, text width) and invalidated when metadata or the frame width changes. Category counts are recomputed only when a status or a queued change changes (the existing `status_ui_dirty` and state-signature checks), never per row.
6. **Terminal size cached** (R5): `tput` runs only on first paint, after a helper returns and after `SIGWINCH`, never per frame.
7. **No fork in the main loop.** `local current_state=$(get_checked_state)` runs every loop iteration in 1.7 (one fork per key). It becomes a function that writes the change-detection signature into a variable; the signature also covers the zone, current category, About offset, Review offset and the step.
8. **Status polling.** `poll_status_loader` forks (`mv`, `rm`) only while the worker is publishing; with checks finished it does nothing. It is left as is, except that new metadata files are consumed with builtins plus one `rm -f` per poll.

**Target.** Median key → completed redraw **≤ 25 ms** at 87×40 on this workstation (4× headroom under the 100 ms requirement), with 0 forks on the render path. The requirement and the gate stay at FR-060's 100 ms.

**How it is measured** (also in [quickstart.md](quickstart.md)):

- `devcontainer.test/test-setup-render-timing.py` (new, local gate). It sources the script with a fixture catalog of all 12 benches carrying the draft copy (long About text), stubs `tput` to 88×40 and every status to a known state, opens the Benches bench zone, and replays ↑, ↓, Tab and PgDn as raw bytes through `handle_input` followed by `draw_ui > /dev/null`, 25 rounds of 4 keys (100 samples), timing each key with `$EPOCHREALTIME` inside the shell (no fork in the timer). It prints median, p90 and max, and the median render time of every step at 87×40; it fails when the median exceeds 100 ms. It runs locally and is not a CI gate (spec Assumptions; shared runners make timings noisy).
- A deterministic guard that does run in CI: a static check (in `test-setup-wizard-layout.py`) that the bodies of the render-path functions — those named `setup_frame_*`, `setup_ui_*` and `wizard_render_*`, plus `draw_ui` — contain no command substitution (`$(` other than `$((`), backtick, process substitution or pipeline. Together with the existing recording-stub test (SC-005: no `jq`, `python3`, `docker` or `git` call while rendering), this keeps forks out of the renderer between timing runs.
- The measured medians are recorded in `specs/029-setup-guided-wizard/release-qa.md` with the commit and the workstation.

### Alternatives considered

- **Port the prototype renderer and trim it.** Rejected: measured at ~130 ms per key; trimming subshells piecemeal would leave the budget hostage to every future row.
- **Redraw only the rows that changed (row-level renderer, as 1.7's dead `update_selection_lines` tried).** Rejected: a step change, a scroll or a height change touches most rows anyway, and the line diff in `draw_ui` already limits terminal output; once the frame build is fork-free (3.8 ms) a full rebuild is cheap and far simpler.
- **Move rendering to Python or a compiled helper.** Rejected: a second process per key costs more than the budget it saves, and FR-038 forbids running Python on the render path.
- **Cache whole frames per state.** Rejected: the state space (step × focus × statuses × queued changes × size) is large and invalidation is error-prone; per-part caching gets the same benefit.

## R2. Review numbering and the step map (FR-001, FR-003, D1)

### Decision

`CURRENT_SECTION` keeps 1.7's values and adds Review: 0 Benches, 1 Agents (the former AI assistants), 2 Tools, 3 Workstation (the former Requirements), 4 Profiles, **5 Review**. Step order is a separate pair of arrays:

```bash
setup_step_sections=(3 0 1 2 4 5)            # step index -> section
setup_step_names=(Workstation Benches Agents Tools Profiles Review)
# section -> step index, built once: setup_section_step=([3]=0 [0]=1 [1]=2 [2]=3 [4]=4 [5]=5)
```

← and → move by step index and clamp at 0 and 5 (no wrap). The nav, the compact `Step N of 6 · <Name>` form, Review's step names and the footer all read these arrays, so the name "Agents" appears in one place.

The **opening step is set by `main()`** (`CURRENT_SECTION=3` immediately before the first paint, on both the asynchronous and the synchronous interactive paths); the value a sourced script starts with stays 0. Unit suites that source the script and drive `handle_input` from a known section keep their starting state, and renders that need the requirements strip set `CURRENT_SECTION=3`, as the design's suite table already says.

### Alternatives considered

- **Review = 4, as the prototype did.** Rejected in D1: 1.7 uses 4 for Profiles and suites set `CURRENT_SECTION=4` to mean Profiles.
- **Renumber sections in step order.** Rejected in D1: churns every test and return-target variable for no behavioural gain.
- **Change the sourced default to 3.** Rejected: `test-setup-requirements.py` sources the script, presses P and asserts it reached section 3; with a default of 3, P would return to Benches and the test would need a rewrite with no gain.

## R3. Metadata file format and sanitising (FR-048–FR-051, D12)

### Decision

The worker publishes two files beside `catalog` in the private status directory, each written to `<name>.tmp` and renamed, **categories first**: `bench-categories` (`id`, `order`, `label`, `summary`) and `bench-meta` (`name`, `category`, `tagline`, `description`, `usedFor`, `contains`). The arrival of `bench-meta` marks the metadata complete. The exact format is in [contracts/worker-metadata-files.md](contracts/worker-metadata-files.md):

- one record per line, fields separated by a tab; an empty field travels as `-`, because tab is IFS whitespace and `read` would merge adjacent tabs (prototype finding); a whole-field value of exactly `-` therefore cannot be expressed, and the catalog test rejects it in the catalog;
- list fields join items with `|`; a `|` inside an item becomes `/`;
- the worker builds the rows with `jq` from `config/bench-config.json`, already replacing control characters with spaces (`gsub("[[:cntrl:]]"; " ")`, which covers C0, DEL and C1 in jq's Unicode regex) and trimming;
- the foreground **re-sanitises** every field it reads (defence in depth: the files are outside text to the TUI), validates names (`^[a-zA-Z0-9_+-]+$`) and ids (`^[a-z0-9][a-z0-9-]*$`) and drops records that fail;
- the foreground sanitiser is a fork-free Bash function that works in any locale: it switches `LC_ALL=C` in a local scope, replaces bytes `0x01–0x1F` and `0x7F` with a space, and replaces the two-byte UTF-8 encodings of U+0080–U+009F (`0xC2 0x80–0x9F`) with a space. (Bash strings cannot hold NUL.) Under a UTF-8 locale `[[:cntrl:]]` would also work, but in the C locale it misses C1, and some terminals act on C1 CSI;
- the same sanitiser is applied to every other text the TUI shows but did not write (NB-7): worker status details (`*.row` detail field), the identities summary and helper results. The identities summary already travels with record separator `\036` in place of newlines; the foreground splits on `\036` **before** sanitising (RS is itself a control character).

In the synchronous path (no TTY, keys piped by tests), interactive and `--select-only` runs produce the same rows by calling the same row builder in-process after `init_components`; `--apply-plan` and `--dependencies-plan` never load them.

### Alternatives considered

- **Unit separator (`\037`) as the field delimiter.** `IFS=$'\037' read` keeps empty fields, so no `-` sentinel would be needed. Rejected for now because D12 fixed the TSV format and the prototype proved it; recorded here in case a real field ever needs a literal `-`.
- **A JSON snapshot.** Rejected in D12: Bash cannot parse it without `jq` or Python on the render side.
- **Sanitising only in the worker.** Rejected: FR-048 makes the foreground responsible, and the worker's output is still outside text to the renderer.
- **Running `jq` in the foreground after Tools starts.** Rejected in D12: first paint and rendering must not wait for or run Tools binaries.

## R4. `jq` lookup pattern and the fail-closed path check (FR-056–FR-058, D13)

### Sites on 1.7 (`ccc9eac`)

Re-found with `grep` over every shell file (`*.sh`, `launchBench`, `setup.sh`, `bootstrap.sh`, `devBenches/scripts/*`):

| File | Lines | Lookup |
|---|---|---|
| `scripts/interactive-setup.sh` | 765–766 | `check_component_status`: `.benches.${bench_name}.path`, `.url` |
| `scripts/interactive-setup.sh` | 1837, 1887, 1902, 1908, 2007–2008 | `process_selections`: `.benches.${bench}.path // "$bench"`, `.url` |
| `scripts/setup-workbenches.sh` | 249 | `.benches.${bench_name}.path // .infrastructure.${bench_name}.path` |
| `scripts/setup-workbenches.sh` | 388–390 | `.infrastructure.${infra_name}.url`, `.description`, `.path` |
| `scripts/setup-workbenches.sh` | 409, 460–462, 482, 489–490 | `.benches.${bench}.description`, `.url`, `.path` |
| `scripts/update-project.sh` | 75, 403, 430 | `.benches.${bench_name}.path`, `.description` |
| `scripts/launchBench` | 118 | `.benches.${bench_name}.description // empty` |

Already safe: `scripts/new-bench.sh:871` (`--arg key` and `.benches[$key]`), `scripts/update-bench-config.sh` (no per-name lookup), `devBenches/scripts/update-devBench-project.sh`, `scripts/workbench-config.sh` and `setup.sh` (no per-name lookup). The four Python consumers (`setup_selection.py`, `setup-components.py`, `release-workbenches.py`, `remove-bench-checkout.py`) index `json.loads(...)['benches']` by name.

In `process_selections` the fallback `// "$bench"` is itself inside the failing jq program, so for `365Bench` jq exits 3 with a compile error, `bench_path` is empty and `full_bench_path` becomes `$script_dir/../` — the workBenches root.

### Decision

- Every shell lookup passes the name as data: `jq -r --arg n "$name" '.benches[$n].path // empty' "$CONFIG_FILE"` (and `.infrastructure[$n]`). Where a field and a fallback are read together, the fallback moves into the program as data (`.benches[$n].path // .infrastructure[$n].path // empty`). No lookup keeps a `// "$name"` default.
- `process_selections` resolves a bench through one helper, `bench_checkout_path NAME VAR`, that sets `VAR` to the relative path only when it is non-empty, starts with `devBenches/`, `sysBenches/` or `bioBenches/` and has no `..` segment — the rule `setup_selection.py benches` already applies. Otherwise the bench is reported as failed (same `failed_components`/`fail_count` path as any failed component, message "cannot resolve <bench> in the bench catalog") and the loop continues; no `git`, clone, `setup-bench-runtime.py`, `build-layer.sh` or `setup.sh` runs for it, and the workBenches root is never used as a bench directory. `check_component_status` uses the same helper and reports `needs check` for an unresolved bench instead of probing the root.
- **Static check** (`devcontainer.test/test-bench-catalog-lookups.py`): scans every tracked shell file (by extension or `bash`/`sh` shebang) and fails on a `.benches` or `.infrastructure` path built from a shell variable — regex `\.(benches|infrastructure)\s*(\.|\[)\s*"?\\?"?\$` — and on any `jq` program string containing `${`. It prints file and line.
- **Behaviour test** (same file): a fixture repository whose catalog holds `365Bench` at `sysBenches/365Bench` (plus a decoy directory at the root) drives each consumer — `check_component_status`, `process_selections`, `setup-workbenches.sh`, `update-project.sh`, `launchBench`, and the four Python consumers — and asserts each resolves `sysBenches/365Bench` (and its description and URL where it reads them). A second fixture with an empty and an out-of-tree path asserts the failure report and that recording `git`, `docker` and `bash` stubs saw no call in the root.

### Alternatives considered

- **Bracket-quoting the name in the program (`.benches["'"$n"'"]`).** Rejected: still builds code from data; a quote in a name breaks it.
- **Rename 365Bench.** Rejected in D13 (repository, image mapping, `wave-container-shell.sh` and the release lock use the name).
- **Validate names against `^[A-Za-z_]` before lookup.** Rejected: it would make 365Bench unselectable instead of resolving it.

## R5. Terminal height and resize handling (FR-033–FR-037, FR-039)

### Facts

- In every PTY-driven suite the PTY is opened without a window size (`stty size` reports `0 0`), and `tput cols`/`tput lines` fall back to the terminfo defaults: **80×24**. Those suites therefore run at a 79-column frame in the **tight** layout. With no TTY at all and `TERM=xterm`, `tput` also reports 80×24.
- Unit suites stub `tput` as a shell function that answers only `cols` (`tput() { if [[ "$1" == cols ]]; then echo 88; fi; }`), so `tput lines` is empty there: **height unknown**.
- Bash's `read` builtin returns a status above 128 when a signal with a trap arrives. In 1.7 `handle_input` treats a failed `read` as Quit (`return 2`) when checks are not running; with a `SIGWINCH` trap that would quit setup on every resize.
- `checkwinsize` updates `LINES`/`COLUMNS` only after an external command, and the fork-free renderer runs none, so it cannot be relied on.

### Decision

- The size is read by `setup_ui_read_size` with `tput cols` and `tput lines` (the function or the binary, so suite stubs keep working): a non-numeric width falls back to 88 as in 1.7; a non-numeric or zero height means **unknown**. It runs on first paint, whenever `setup_ui_painted` is false (after a helper returns) and when `setup_ui_size_stale` is set, never otherwise.
- A `trap 'setup_ui_size_stale=true' WINCH` is installed with the TUI's other traps. `handle_input` checks the flag when `read` returns above 128: if it is set, it returns 3 (redraw, no key) instead of Quit, in both the timed and untimed `read`.
- `draw_ui` repaints the whole frame (clear + all lines) when the width **or the height** differs from the last paint, as FR-039 requires.
- Layout uses the known height: tight at 24 rows or fewer and whenever the roomy layout does not fit; panels scroll inside their rows; when even the tight layout does not fit, lines are dropped from the top of the frame (FR-036). With an unknown height nothing is clipped and no `N more` row is shown.
- Scrolling is **edge-triggered** (prototype lesson: recentring on every move felt busy). Each list keeps an offset; the window moves only when the focused row would leave it, and then by the smallest amount that brings the focused row back to its first or last visible line. Offsets reset when the list changes (step, category); the bench panel offset is kept per category while the user stays on Benches.

### Alternatives considered

- **`tput` on every frame (1.7).** Rejected: 2 × 5.6–6.2 ms per frame at a known height — 12% of the budget for a value that almost never changes.
- **`stty size`.** Rejected: also a fork, and it reports `0 0` on the suites' PTYs where `tput` reports 80×24; switching would change every suite's layout.
- **Recentre the focused row.** Rejected by the prototype review ("felt busy").

## R6. Nav fit, measured (FR-005–FR-007, D5)

### Measurements

Measured in characters with `${#nav}` under `C.UTF-8`, using the planned format — a leading space, items joined with ` ─ `, the current item padded by one space on each side for its highlight:

| Nav state | Width |
|---|---:|
| Nothing queued (any current step) | 73 |
| Benches, Agents and Tools each with a single-digit count | 79 |
| One two-digit count (for example `Benches 12`) | 80 |
| Largest possible: Benches 12, Agents 8, Tools 7 (the catalog has 12 benches; Agents has 8 selectable items, Tools 7) | 80 |
| Compact form `Step 2 of 6 · Benches` plus six marks | 34 |

### Decision

The renderer builds the full nav, measures it with `${#}` and uses it when its width is at most the frame width; otherwise it uses the compact form (no queued counts, NB-3). So the full nav shows at every terminal of 81 columns or more, and on an 80-column terminal (79-column frame) unless Benches has ten or more queued changes; the compact form shows at 60 columns and below 80. The 34-column compact line fits the 36-column minimum frame. The suites' 80×24 PTYs (R5) get the full nav whenever their queued counts are single digits, which every suite scenario is.

### Alternatives considered

None open: Brett chose "Agents" and short connectors (clarify Q1); this record only confirms the arithmetic the design reported.

## R7. Profiles About text source (FR-019, D14)

### Decision

The Profiles About panel reads a fixed associative array in `interactive-setup.sh`, `profile_about[personal_profiles|workbenches_account|ai_accounts]`, whose strings are 1.7's existing Profiles and Requirements copy, consolidated rather than rewritten:

- Personal & companies — 1.7's `profiles_summary` default and `draw_profiles` note: "Personal identity, GitHub and company accounts. Company, GitHub and AI access are authorized separately." (the design mockup's text);
- Workstation account — 1.7's `requirement_detail[workbenches_account]`: "Organization sign-in. AI and vault access are managed separately.";
- AI accounts — 1.7's `requirement_detail[ai_accounts]`: "Sign in, restore assistant profiles, or recover credentials from a vault."

The panel is sized and scrolled like Benches About (FR-046: 2–8 lines from spare rows when the height is known, `PgUp`/`PgDn` and `[`/`]`, offset reset on row change). Because the strings are TUI-written, they are not sanitised; the identities line above them is (R3). `setup-profiles.py` is untouched (non-goal).

### Alternatives considered

- **Ask `setup-profiles.py` for the text.** Rejected: Profiles internals are out of scope, and rendering must not run Python.
- **Put the text in a config file.** Rejected: three fixed sentences do not justify a new file or loader, and the bench-copy approval gate covers bench copy only.
- **New copy.** Rejected: "look only, same behaviour"; reusing shipped wording needs no new approval.

## R8. How keystroke-driven suites wait now that the strip is Workstation-only (SC-010)

### The problem

Four suites wait on the requirements strip's title, `REQUIREMENTS · N/N ready` (shown as `REQUIREMENTS · Loading…` while checks run), as the "checks finished and the workstation is ready" marker: `test-workstation-acceptance.py` (`TUI`, reused by `test-wsl-workstation-acceptance.py` as `tui.TUI`), `test-component-lifecycle.py`, `test-tools-runtime.py` and `test-setup-guided-flow.py`. The wizard opens on Workstation, so every wait **at startup** still matches. It breaks **after Profiles**: `account_setup_replies` in `test-workstation-acceptance.py` presses G on the component step, runs the AI accounts action, presses G to return — in the wizard that returns to **Agents**, which has no strip — and then waits for `TUI` again before pressing Enter. `terminal_screen()` emulates the visible screen, so the marker from an earlier Workstation frame is gone and the suite would hang until its timeout. (`test-tools-runtime.py` presses G from Workstation, so its return lands on Workstation and still sees the strip; `test-component-lifecycle.py` matches the raw cumulative transcript, so an earlier frame would satisfy it — a latent false positive the new marker also removes.)

### Decision

Suites wait on the nav's readiness mark, which FR-006 puts on **every** step and which has the same meaning as the strip title: the Workstation item shows a blinking `…` while checks run, a green `✓` when every required item is Up and a yellow `⚠` otherwise, and is never a step mark. The shared patterns, defined once in `test-workstation-acceptance.py` and imported by the WSL suite:

```python
READY = r'✓ Workstation[^\n]*\n[\s\S]*Navigation:'          # any step, checks done, required items Up
STRIP_READY = r'REQUIREMENTS · (\d+)/\1 ready[\s\S]*Navigation:'  # Workstation only (first frame)
REVIEW = r'Nothing has changed yet\. Enter applies these changes\.[\s\S]*Navigation:'
```

- Startup waits keep `STRIP_READY` (it proves the strip renders); every wait after the first key, and in particular the one after a Profiles return, uses `READY`. Apply becomes "wait `REVIEW`, then Enter" instead of a blind second Enter where the suite already waits between keys.
- The full nav names Workstation at the suites' 80×24 PTYs whenever queued counts are single digits (R6), which holds for every suite scenario. A suite that needs a narrower frame waits on `Navigation:` plus the readiness glyph in the compact form (`Step N of 6 · …` followed by `✓`).

### Alternatives considered

- **Press P to visit Workstation, wait for the strip, press P to come back.** Rejected: two extra keys per wait, and it moves focus through the very jump logic under test.
- **Keep the strip on every step.** Rejected by the spec (FR-030, strip on Workstation only).
- **Add a hidden or test-only marker.** Rejected: suites should assert what a user sees.
- **Wait on `Changes selected: N` or the context line alone.** Rejected: neither says the checks have finished, which is what the strip wait guaranteed.

## R9. Character counting and the locale (FR-033, D10)

### Decision

Padding and truncation count characters with `${#text}` and `${text:0:n}` and pad with `printf -v '%s%*s'` from the counted length (D10). `${#}` counts characters only under a UTF-8 `LC_CTYPE`; `setup.sh` and `interactive-setup.sh` set no locale today, so a host with `LANG` unset would count bytes and misalign every line containing `·`, `…`, `─` or `✓` (1.7's `setup_ui_pair` has the same latent fault). At startup the TUI checks the effective character map once (`${LC_ALL:-${LC_CTYPE:-$LANG}}` matching `UTF-8`/`utf8`); when it is not UTF-8 and `C.UTF-8` is available, it sets `LC_CTYPE=C.UTF-8` (and `LC_ALL=C.UTF-8` when `LC_ALL` was set to something else) for the TUI process. The sanitiser (R3) switches to `LC_ALL=C` locally, so it is unaffected. Only single-column glyphs are used, and the catalog test keeps wide, combining, zero-width and bidi characters out of the copy (NB-6).

### Alternatives considered

- **Byte-count and avoid multibyte glyphs.** Rejected: the approved design uses `·`, `…`, `─`, `●`, `○`, `✓`, `⚠`, `▲`, `▼`, `›`.
- **Leave the locale alone.** Rejected: FR-033 requires character-counted alignment.

## R10. Frame builder API and test seams

### Decision

- The builder is split by region: `setup_frame_head` (banner, version/OS line, nav, rule), `setup_frame_selector` (strip, category block, identities line or Review's instruction line), `setup_frame_notice`, one body builder per step, and `setup_frame_footer`. Each region appends to `setup_frame_lines` and reports its height, so the height budget (FR-047, D9) is computed from known parts before the variable parts (scrolling lists, About) are cut.
- Entry points that suites call stay, as stdout shims over the builders: `render_setup_frame`, `draw_requirements_summary`, `draw_requirement_item`, `draw_requirements`, `draw_profiles`, `draw_setup_footer`. State functions keep their names and contracts: `handle_input`, `activate_requirement`, `activate_profile`, `poll_status_loader`, `get_checked_state`, `init_components`, `load_statuses`, `process_selections`, `save_selection`, `load_selection`, `setup_required_ready`.
- The `ai_items=(…)` and `tool_items=(…)` literals in `init_components` keep their exact layout (one quoted item per line, closing `    )`), because `test-setup-credential-plan.py` parses them with a regex.
- `test-setup-async.py` overrides `render_setup_frame` to feed `draw_ui` a synthetic frame; that test moves its override to the array builder (`setup_frame_build`). The asserted outcome — shorter frames erase stale lines; external output invalidates the cache — is unchanged.

### Alternatives considered

- **Rename everything with a `wizard_` prefix, as the prototype did.** Rejected: churns nine suites for no behavioural gain.

## R11. Key parsing (FR-042, FR-043, FR-046)

### Decision

After `ESC`, `handle_input` reads two bytes with a 0.1 s timeout as today. `[A`/`[B`/`[C`/`[D` are the arrows; `[Z` is Shift+Tab; `[5` and `[6` read one more byte and require `~` (PgUp, PgDn); any other sequence is ignored. A raw tab (`\t`) is Tab. `[` and `]` scroll About. On Benches the zone handler gets the key first; anything it does not consume falls through to the shared keys. Enter accepts `''`, `\r` and `\n`, as 1.7 does.

### Alternatives considered

- **Use `read -d` or `-N` to read whole sequences.** Rejected: sequence lengths differ, and the 0.1 s tail read already handles slow terminals.
