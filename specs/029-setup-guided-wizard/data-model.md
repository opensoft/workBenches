# Data Model: Guided setup wizard

**Feature**: [`029-setup-guided-wizard`](spec.md) · **Plan**: [plan.md](plan.md) · **Research**: [research.md](research.md)

The wizard keeps all state in Bash globals inside `scripts/interactive-setup.sh` and `scripts/lib/setup-status-loader.sh`. Names below are the planned ones; existing 1.7 names are kept where they exist and marked *(1.7)*. Rendering reads only this in-memory state (FR-038).

## 1. UI state

### 1.1 Sections and steps

| Section (`CURRENT_SECTION`) | Step index | Step name | Rows (`current_selection` indexes) | Selector area | Queued count in nav |
|---:|---:|---|---|---|---|
| 3 *(1.7 Requirements)* | 0 | Workstation | `requirement_items` *(1.7)*: `wsl` (WSL only), `docker`, `setup_tools`, `vault` | requirements strip | none; readiness mark instead |
| 0 *(1.7)* | 1 | Benches | category zone: `setup_bench_categories_focusable`; bench zone: `bench_items` index | `CATEGORY` block | changes with key `bench_*` |
| 1 *(1.7 AI assistants)* | 2 | Harness | `ai_items` *(1.7)*, separator skipped | none | changes on `ai_items` keys |
| 2 *(1.7)* | 3 | Tools | `tool_items` *(1.7)* | none | changes on `tool_items` keys |
| 4 *(1.7)* | 4 | Profiles | `profile_items` *(1.7)*: `personal_profiles`, `workbenches_account`, `ai_accounts` | identities line | never |
| **5** *(new)* | 5 | Review | none (read-only list, `setup_review_offset`) | instruction line | never |

```text
setup_step_sections=(3 0 1 2 4 5)
setup_step_names=(Workstation Benches Harness Tools Profiles Review)
setup_section_step=([3]=0 [0]=1 [1]=2 [2]=3 [4]=4 [5]=5)
```

`main()` sets `CURRENT_SECTION=3` before first paint; a sourced script starts at 0 (research R2).

### 1.2 Focus

| Variable | Type | Meaning |
|---|---|---|
| `CURRENT_SECTION` *(1.7)* | int 0–5 | current step's section |
| `current_selection` *(1.7)* | int | focused row; on Benches always an index into `bench_items` (D7), so Space/D, the footer and `get_checked_state` keep working |
| `setup_bench_zone` | `category` \| `bench` | Benches focus zone |
| `setup_bench_category` | category id | current category (both zones) |
| `setup_about_offset` | int ≥ 0 | first visible About line (Workstation, Benches, Harness, Tools and Profiles) |
| `setup_about_anchor` | string | what About describes: `bench:<name>`, `category:<id>`, `profile:<key>` or `workstation:<key>`; a change of anchor resets the offset to 0 (FR-046) |
| `setup_bench_offset[<category id>]` | assoc int | first visible bench row per category (edge-triggered scrolling, R5) |
| `setup_list_offset` | int | first visible row on Workstation, Harness, Tools, Profiles |
| `setup_review_offset` | int ≥ 0 | first visible Review item |
| `setup_benches_state` | `loading` \| `ready` \| `unavailable` | Benches content state (FR-049) |

### 1.3 Return targets (P and G)

Two targets with the same shape. The P target is written by P, by ← from Benches to Workstation and by the readiness jump; the G target by G, by → from Tools and by ← from Review (FR-023, FR-024, FR-028).

| Field | P target *(1.7 name, extended)* | G target *(1.7 name, extended)* |
|---|---|---|
| section | `requirements_return_section` | `profiles_return_section` |
| row | `requirements_return_selection` | `profiles_return_selection` |
| zone | `requirements_return_zone` | `profiles_return_zone` |
| category | `requirements_return_category` | `profiles_return_category` |
| bench name | `requirements_return_bench` | `profiles_return_bench` |
| Review offset | `requirements_return_review_offset` | `profiles_return_review_offset` |
| set? | `requirements_return_set` (bool) | `profiles_return_set` (bool) |

Default when unset: Benches, category zone, first category that has benches. A target's bench is stored **by name** and re-resolved to an index on return (FR-051).

### 1.4 Frame and layout state

| Variable | Meaning |
|---|---|
| `setup_ui_width` *(1.7)* | frame width = terminal columns − 1, clamped to 36–87 |
| `setup_ui_height` | terminal rows, or empty when unknown |
| `setup_ui_frame_columns` *(1.7)*, `setup_ui_frame_rows` | size of the last paint; a difference forces a full repaint (FR-039) |
| `setup_ui_size_stale` | set by the `WINCH` trap; `draw_ui` re-reads the size (R5) |
| `setup_ui_painted` *(1.7)* | false after a helper returns; forces clear and size re-read |
| `setup_ui_layout` | `roomy` \| `tight` |
| `setup_frame_lines` | the frame being built (array, R1) |
| `setup_ui_previous_lines` *(1.7)* | last frame written, for the line diff |
| `setup_ui_cache_key` and cache arrays | static parts keyed by width × layout; About wrap cache keyed by anchor × text width |
| `setup_ui_signature` | change-detection string for the main loop (replaces `$(get_checked_state)` per iteration; also covers zone, category, offsets and step) |

### 1.5 Notices

`requirements_notice` *(1.7)* holds the single notice shown after the selector area on the current step (FR-032). Set by V, Profiles actions, a blocked Apply and the readiness jump; cleared when a Workstation service action (V included) starts, or by R, or replaced by a later notice (1.7 lifetime). Review's blocker line is computed from state (checks running, or requirements unresolved), not stored as a notice.

## 2. Bench catalog (`config/bench-config.json`)

Formal schema: [contracts/bench-config.schema.json](contracts/bench-config.schema.json).

```text
catalog
├── categories: { <id>: { label, order, summary } }            (new)
├── benches:    { <name>: { url, path, description,            (1.7)
│                           ai_keywords[], project_scripts[],  (1.7, optional)
│                           category, tagline, usedFor[],      (new)
│                           contains[] } }                     (new)
└── infrastructure: { <name>: { ... } }                        (1.7, unchanged)
```

| Entity | Field | Rule |
|---|---|---|
| Category | id (key) | `^[a-z0-9][a-z0-9-]*$`; exactly `software-engineering`, `science`, `system-administration`, `electrical-engineering` (FR-052) |
| | `label` | non-empty single line, single-column printable characters |
| | `order` | integer; categories sort by `order`, then id |
| | `summary` | non-empty single line, single-column printable characters |
| Bench | name (key) | `^[a-zA-Z0-9_+-]+$` (may start with a digit: `365Bench`) |
| | `url`, `path` | equal to the release lock's entry for the same path; `path` starts with `devBenches/`, `sysBenches/` or `bioBenches/`, no `..` |
| | `category` | a defined category id; Electrical Engineering has none; the other three at least one |
| | `tagline` | 1–35 characters, single line, no version-like token |
| | `description` | non-empty single line |
| | `usedFor[]`, `contains[]` | non-empty lists of non-empty single-line strings, no version-like token |
| | all copy fields | no control characters (U+0000–U+001F, U+007F–U+009F); no wide, fullwidth, combining, zero-width or bidi formatting characters; no whole-field value `-` (worker sentinel, R3) |

**Version-like token** (FR-053): a standalone number — dotted or not — not joined to a letter, or a number prefixed by `v` or `version-`; allow-list `Microsoft 365`, `Dynamics 365`. Accepted: `ARM64`, `MMseqs2`, `py3Dmol`, `m365`. Rejected: `Go 1.26`, `Python 3`, `v2`, `version-4`.

**Release-lock coverage** (FR-054): `{bench.path} == {repository.path for repository in config/release-lock.json}` in both directions, URLs equal; today 12 entries: cppBench, dotNetBench, flutterBench, frappeBench, goBench, javaBench, pyBench, rustBench (Software Engineering), gentecBench, simBench (Science), 365Bench, cloudBench (System Administration).

**Source of copy**: `specs/029-setup-guided-wizard/bench-copy-draft.json` — `categories` and `benches.<name>.{category, tagline, description, usedFor, contains}` are merged in; the draft-only `draft` and `evidence` fields are not copied; `newBenches` supplies `url`, `path`, `description` and `ai_keywords` for goBench, rustBench and 365Bench. Existing `url`, `path`, `ai_keywords` and `project_scripts` are kept.

Checked during planning (in memory, 2026-10-21): the 1.7 catalog with the draft merged in and the three new benches added validates against the contract schema (12 benches); its paths equal the release lock's and every URL matches exactly; the unchanged 1.7 catalog is rejected (no `categories`).

Catalog-name order inside a category is code-point order of the names (as `jq keys`), so `365Bench` precedes `cloudBench` (FR-044).

## 3. Worker metadata files

Full format: [contracts/worker-metadata-files.md](contracts/worker-metadata-files.md). Published by the status worker into the private status directory, beside `catalog` and the `<key>.row` files, each atomically.

| File | Record | Foreground target |
|---|---|---|
| `catalog` *(1.7; path field new)* | `name` or `name ⇥ path` per line | `bench_items`, `component_description[bench_<name>]`, `setup_bench_path[name]` (validated bench-root path, for the FR-050 fallback) |
| `bench-categories` | `id ⇥ order ⇥ label ⇥ summary` | `bench_category_label[id]`, `bench_category_order[id]`, `bench_category_summary[id]`, `bench_categories_loaded=true` |
| `bench-meta` | `name ⇥ category ⇥ tagline ⇥ description ⇥ usedFor ⇥ contains` | `bench_meta_category[name]`, `bench_meta_tagline[name]`, `bench_meta_description[name]`, `bench_meta_used_for[name]`, `bench_meta_contains[name]`, `bench_meta_loaded=true` |
| `<key>.row` *(1.7)* | `state ⇥ detail` | `component_status`, `requirement_detail` (detail sanitised) |
| `done` *(1.7)* | empty | checks finished |

Derived per arrival (never per frame): `setup_bench_category_of[name]` (category or path fallback, FR-050), the ordered category list, per-category member lists in catalog-name order, and per-category counts (`benches`, `installed`, `queued`).

## 4. Queued-change model

Unchanged from 1.7; the wizard only adds views of it.

| Variable | Meaning |
|---|---|
| `component_checked[key]` *(1.7)* | `true` when a change is queued |
| `component_action[key]` *(1.7)* | `install` \| `update` \| `uninstall` (empty = keep) |
| `component_status[key]` *(1.7)* | `loading`, `installed`, `not installed`, `needs check`, `needs creds`, `needs setup`, `needs docker`, `image only`, `configured`, `optional`, `up`, `down`, `missing`, … |

Rules *(1.7, FR-018, FR-043)*: Space queues `install`, or `update` when the item counts as installed (`installed`, `needs creds`, `image only`), and pressing it again unqueues; D queues `uninstall` only for an installed item (or a bench in `needs docker`), and again unqueues; `loading` and `needs check` are not selectable; `host_shell` and `workspace_repo` queue `install` only.

Views:

- **Step of a change**: `bench_*` → Benches, `ai_items` → Harness, `tool_items` → Tools. Profiles and Workstation never hold queued changes.
- **Nav counts**: per step, the number of checked keys with a non-empty action.
- **Category counts** (FR-041): `benches` = members; `installed` = members whose status counts as installed; `queued` = members with a queued change.
- **Review groups** (FR-009): INSTALL (`install`), UPDATE (`update`), REMOVE (`uninstall`); within a group, step order then the step's row order; each item shows the step name; warnings for `host_shell` and `workspace_repo`.
- **Selection file** (FR-015, unchanged): every checked key with a non-empty action → `{"key", "action"}`; see [contracts/setup-contracts-unchanged.md](contracts/setup-contracts-unchanged.md).

**Catalog refresh** (FR-051, NB-5): when a refreshed catalog drops a bench, its `component_checked`/`component_action` entries are cleared, and focus or a return target naming it falls back to the category zone on the same category (or the first category with benches).

## 5. State transitions

### 5.1 Benches zones

```text
           ↑/↓ (focusable categories)                 ↑/↓ within category
         ┌────────────┐                             ┌────────────┐
         ▼            │   Tab, Shift+Tab, Space,    ▼            │
   ┌───────────────┐──┘   ↓ on last focusable  ┌──────────────┐──┘
   │ category zone │ ───────────────────────▶ │  bench zone  │   Space/D queue
   │ (no row mark) │ ◀─────────────────────── │ (› on bench) │
   └───────────────┘   Tab, Shift+Tab,        └──────────────┘
         │             ↑ on first bench              │
         │ Enter                                     │ Enter
         ▼                                           ▼
                           Review
```

Arrival by ←/→ or first catalog arrival: category zone, first category that has benches. P/G return and readiness jump: exact zone, category and bench.

### 5.2 Benches content

```text
loading ──(catalog + bench-meta arrive)──────────────▶ ready
loading ──(checks done, catalog but no metadata)─────▶ ready (degraded, FR-050)
loading ──(checks done or failed, no catalog)────────▶ unavailable ("could not be loaded … R retries")
unavailable/ready ──(R)──────────────────────────────▶ loading
```

### 5.3 Apply gate on Review

```text
Enter on Review:
  checks running                → blocker "waiting for checks", nothing applied
  required item not Up          → blocker "resolve workstation requirements first", nothing applied
  nothing queued                → (select-only: write empty selection) exit 0
  otherwise                     → interactive: ensure_selected_dependencies + process_selections
                                  select-only: save_selection, exit 0
```

## 6. Validation rules summary

| Rule | Where enforced | Requirement |
|---|---|---|
| Catalog schema, limits, characters, version tokens, lock coverage, simBench wording | `devcontainer.test/test-bench-catalog.py` | FR-052–FR-055, SC-003, SC-013 |
| Name-safe lookups; digit-leading resolution in 8 consumers; fail-closed apply | `devcontainer.test/test-bench-catalog-lookups.py` | FR-056–FR-058, SC-004 |
| Maintenance scripts preserve fields, derive category, skip unlocked clones | `devcontainer.test/test-bench-catalog-maintenance.sh` | FR-059 |
| Bench name `^[a-zA-Z0-9_+-]+$`, category id `^[a-z0-9][a-z0-9-]*$` on read | `poll_status_loader` / metadata readers | FR-048 |
| Control characters → space in all outside text | foreground sanitiser | FR-048, SC-011 |
| Selection file: `schemaVersion` 1, known keys, actions, private file | `scripts/setup_selection.py` *(1.7, unchanged)* | FR-015 |

## Tools/Harness About refinement 029-A05

Tools uses setup_tool_zone (category/tool), setup_tool_category, static group members/labels/summaries, and per-category list offsets. current_selection remains a global tool_items index. Harness uses the existing global ai_items index; separator rows remain nonfocusable. Cached About anchors add harness:<key>, tool:<key> and tool-category:<id>. P/G saves tool zone/category and list/About offsets alongside the existing targets.
