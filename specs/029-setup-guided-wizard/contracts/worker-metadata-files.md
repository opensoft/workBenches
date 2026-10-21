# Contract: status-worker files

**Producer**: the status worker (`status_collect_inventory` in `scripts/lib/setup-status-loader.sh`, run by `scripts/setup-status-worker.sh` inside Tools, where `jq`, `git` and `python3` exist).
**Consumer**: `poll_status_loader` in the foreground TUI, using Bash builtins only (FR-038, FR-048).
**Location**: the private status directory `status_loader_dir` (`mktemp -d`, removed by `stop_status_loader`). Nothing here is a public file format; it exists so the foreground never runs discovery.

## Files

| File | Since | Written | Meaning |
|---|---|---|---|
| `catalog` | 1.7 (path field 029) | once per check run, before any `bench_*.row` | one bench per line, catalog-name order: `name` or `name ⇥ path` |
| `bench-categories` | 029 | immediately after `catalog` | category records |
| `bench-meta` | 029 | immediately after `bench-categories` | bench records; its arrival marks the metadata complete |
| `<key>.row` | 1.7 | per status | `state ⇥ detail` |
| `tools-ready` | 1.7 | once | Docker endpoint for the Tools shims |
| `done` | 1.7 | last | the worker finished |
| `worker.log` | 1.7 | throughout | appended to the setup log on stop |

Every file is written to `<file>.tmp` and renamed (`mv`) into place, so a reader never sees a partial file. The foreground consumes a file and deletes it; a later check run (R) publishes a fresh set.

## `catalog`

```text
name            (1.7 form, still accepted)
name ⇥ path     (written by the 029 worker)
```

`name` must match `^[a-zA-Z0-9_+-]+$` or the line is ignored (1.7). `path` is the bench's catalog path, accepted only when it starts with `devBenches/`, `sysBenches/` or `bioBenches/` and has no `..` segment; otherwise it is treated as unknown. The path exists so the foreground can place benches by path when categories arrive without bench details (FR-050) without reading `bench-config.json` itself.

## Record format (`bench-categories`, `bench-meta`)

- UTF-8 text, one record per line, `\n` line ends.
- Fields separated by one tab (`\t`).
- An empty field is written as a single `-` (Bash `read` with a tab IFS merges adjacent tabs). Readers map a field that is exactly `-` to empty.
- List fields join items with `|`; a `|` inside an item is written as `/`. Empty items are dropped.
- No field contains a control character: the producer replaces U+0000–U+001F and U+007F–U+009F with a space and trims; the consumer replaces them again (R3).
- Records whose key fails validation are ignored, not errors.

### `bench-categories`

```text
id ⇥ order ⇥ label ⇥ summary
```

| Field | Producer source | Consumer validation |
|---|---|---|
| `id` | key of `.categories` | `^[a-z0-9][a-z0-9-]*$`, else the record is ignored |
| `order` | `.order` (999 when absent) | `^[0-9]{1,6}$`, else 999 |
| `label` | `.label` (id when absent) | `-` → the id |
| `summary` | `.summary` | `-` → empty |

Example:

```text
software-engineering	1	Software Engineering	Language and framework toolchains for building, testing and shipping software.
electrical-engineering	4	Electrical Engineering	Circuit and electronics tooling; no benches are available yet.
```

### `bench-meta`

```text
name ⇥ category ⇥ tagline ⇥ description ⇥ usedFor ⇥ contains
```

| Field | Producer source | Consumer validation |
|---|---|---|
| `name` | key of `.benches` | `^[a-zA-Z0-9_+-]+$`, else the record is ignored |
| `category` | `.category`; when absent, `-` | `^[a-z0-9][a-z0-9-]*$`, else treated as absent; absent → placed by path (FR-050) |
| `tagline` | `.tagline` | `-` → empty |
| `description` | `.description` | `-` → empty |
| `usedFor` | `.usedFor` joined with `|` | `-` → empty list |
| `contains` | `.contains` joined with `|` | `-` → empty list |

Example (one line, tabs shown as `⇥`):

```text
365Bench⇥system-administration⇥Microsoft 365 and Dynamics⇥Microsoft 365, Dynamics 365 and Power Platform administration tools⇥Entra ID, Exchange and Teams admin|Power Platform and Dataverse work⇥...
```

The producer does **not** apply the path fallback; the consumer does, so the same rule covers a bench that arrives in `catalog` without any `bench-meta` record.

## Consumer behaviour (FR-049–FR-051)

| Situation | Benches step |
|---|---|
| neither `catalog` nor metadata yet, checks running | `Loading benches…`; nothing queueable |
| `catalog` arrived, metadata not yet, checks running | `Loading benches…`; nothing queueable |
| `catalog` + `bench-categories` + `bench-meta` | ready: categories in `order`, then id; benches by `category` |
| `bench-categories` but no `bench-meta`, checks done | ready: benches placed by path into the published categories; About `No details for this bench yet.` |
| `catalog` only, checks done | ready: every bench in one `Other benches` group; About `No details for this bench yet.`; still selectable |
| no `catalog`, checks done or could not start | "The bench list could not be loaded. R retries."; nothing queueable |
| unknown category id in `bench-meta` | category listed after the known ones, ordered by id, label title-cased from the id (`quantum-computing` → `Quantum Computing`) |
| bench without category outside the bench roots | `Other benches` |

Path fallback: `devBenches/` → `software-engineering`, `bioBenches/` → `science`, `sysBenches/` → `system-administration`, anything else (including an unknown path) → `Other benches`. The path comes from the `catalog` record; the foreground never reads `bench-config.json`. When checks finish with neither `bench-categories` nor `bench-meta`, the fallback is not applied: every bench goes to the single `Other benches` group (FR-050).

## Row files (1.7, sanitising added)

`<key>.row` keeps 1.7's format `state ⇥ detail`. 029 adds: the `detail` field is sanitised on read; for `personal_profiles` the detail carries the identities summary with record separator `\036` in place of newlines, and the consumer splits on `\036` before sanitising each line (R3).

## Synchronous path

With no TTY, interactive and `--select-only` runs build the same records in-process (same row builder, then the same readers) right after `init_components`, so keystroke-driven suites see the same categories. `--apply-plan` and `--dependencies-plan` never build or read them.
