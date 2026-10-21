# Design: Guided setup wizard

## Context

`./setup.sh` launches `scripts/interactive-setup.sh`, a Bash TUI. On
`release/1.7.0` (`ccc9eac`) it works like this:

- **Sections.** `CURRENT_SECTION` is 0 Benches, 1 AI assistants, 2 Tools,
  3 Requirements and 4 Profiles; `current_selection` is the focused row. The main
  screen (`draw_three_sections`, `draw_item_compact`) draws Benches, AI assistants
  and Tools side by side as three 24-column lists with 6-column gaps (84 columns),
  under a boxed requirements strip (`draw_requirements_summary`, right label
  `P Manage`). → walks Benches → AI → Tools → Requirements → Profiles.
- **Requirements** (section 3, `draw_requirements`): REQUIRED SOFTWARE and
  OPTIONAL VAULT panels. Since v1.6, `requirement_items=(docker setup_tools vault)`,
  with `wsl` prepended on WSL, so every row is a service row whose
  `State [Action]` runs on Space or Enter (`activate_requirement`).
- **Profiles** (section 4, `draw_profiles`, key G): a PERSONAL & COMPANY
  IDENTITIES panel with the cached `setup-profiles.py --summary` text and the rows
  in `profile_items=(personal_profiles workbenches_account ai_accounts)`. Enter or
  Space runs `activate_profile`, which refuses until required items are ready.
- **Keys.** Space queues install/update, D queues removal, P toggles
  Requirements, G toggles Profiles (both remember section and row), V runs the
  Vault action from any section, R refreshes, Q exits 130. Enter applies (or, with
  `--select-only`, writes the selection file) unless checks are running or
  required items are not ready.
- **Rendering.** `render_setup_frame` builds the frame off-screen and `draw_ui`
  rewrites only changed lines; the width is clamped to 36–87 columns and the height
  is ignored. First paint happens before Docker, Tools, jq or Python run; a
  background worker (`setup-status-loader.sh`, inside Tools) publishes a `catalog`
  file and `*.row` status files that `poll_status_loader` consumes. When checks
  finish with required items unresolved, the TUI jumps to Requirements.

Problems: the 84-column main screen overflows narrower terminals (side-by-side
captures break at 60 and 36 columns); nothing guides a new workstation through
the order it needs; benches are bare names; and Enter applies without showing
what will change. The catalog lacks goBench, rustBench and 365Bench even though
they are locked submodules, and the shell consumers that look benches up build jq
paths by interpolation (`".benches.${bench}.path"`), which jq rejects for a
digit-leading name such as `365Bench`. In `process_selections` the failed lookup
yields an empty path, making the bench directory the workBenches root itself.

A design spike exists on the local, unpushed branch `prototype/tui-guided-wizard`
(final commits `57f07a9`, `6ca1243`; a categories/About iteration is uncommitted).
It is built on `origin/main` `9441dc8` and predates Profiles, so it is a reference
for behaviour and test impact, not code to port.

## Goals / Non-Goals

**Goals:**

- One step per screen in setup order, with a nav bar that always shows where the
  user is, what is queued and whether the workstation is ready.
- Benches browsed by category with an explanation of each bench.
- Every queued change visible on Review before anything is applied.
- A frame that fits 36–87+ columns and any known height.
- All locked benches offered, with safe catalog lookups.
- Unchanged setup contracts, first-paint speed and redraw behaviour.

**Non-Goals:**

- The disabled OpenTUI app (`scripts/setup-ui`).
- Profiles internals (`scripts/setup-profiles.py` and its manager screens).
- New Electrical Engineering benches or Science sub-groups (chemistry, physics).
- Categories or About panels for AI assistants and Tools.
- Changes to Docker, Tools or Vault service behaviour.

## Decisions

### D1. Steps map onto the existing sections; Review becomes section 5

Keep `CURRENT_SECTION` values 0–4 as they are (Benches, AI assistants, Tools,
Workstation = the former Requirements, Profiles) and add Review as 5. The step
order is a separate map: `3 → 0 → 1 → 2 → 4 → 5`.

- *Alternative:* the prototype's Review = 4. Rejected: 1.7 already uses 4 for
  Profiles, and unit tests set `CURRENT_SECTION=4` to mean Profiles
  (`test-setup-profiles.py`, `test-setup-requirements.py`).
- *Alternative:* renumber sections in step order. Rejected: churns every test and
  return-target variable for no behavioural gain.

### D2. The wizard opens on Workstation

The first frame is step 1, so it shows `REQUIREMENTS · Loading…` and the
blinking rows that `test-tools-runtime.py` and `test-setup-async.py` look for on
first paint. P's default return target is Benches. The readiness jump (D13) still
lands on Workstation when checks end unresolved. *Alternative:* open on Benches as
1.7 does. Rejected: it contradicts the step order and, with the strip now shown
only on Workstation, would hide readiness at startup.

### D3. Enter opens Review; only Review applies

Enter on a Workstation service row or a Profiles row runs that row's action, as
in 1.7. Enter anywhere else opens Review. Enter on Review applies (or writes the
selection file with `--select-only`) under today's gating: blocked while
`status_async_ui` is true and checks are running or required items are not Up.
With nothing queued, Enter on Review finishes without changes (exit 0, nothing
applied or built), as today's empty Enter does. *Alternative:* a confirmation
prompt after Enter. Rejected: `test-setup-guided-flow.py` asserts there is no
"Apply these changes?" prompt, and a full Review step shows removals and warnings
that a yes/no prompt would not.

### D4. Head, selector area and notices

Head: banner → version/OS line → nav → one rule. No per-step title or
description lines ("too busy"). Directly under the rule is the step's selector
area: the requirements strip on Workstation, the CATEGORY block on Benches, the
identities line on Profiles, nothing on AI assistants and Tools; Review starts
with its instruction line. Notices (from V, a Profiles action, a blocked Apply or
the readiness check) appear after the selector area on the current step, because
the strip that used to carry them is no longer on every screen.

### D5. Nav bar and its six-step fit

Steps before the current one show `✓`, the current step a highlighted `●`, later
steps `○`, each followed by its queued-change count when non-zero. The Workstation
item shows readiness instead: green `✓`, yellow `⚠`, or a blinking `…` while
checks run. The approved mockup has five steps with ` ── ` connectors (75
columns). With Profiles added, six steps need 91 columns with ` ── ` and 86 with
` ─ `, so at the 87-column maximum the nav uses short connectors and fits only
while every count is a single digit. When neither form fits, the nav collapses to
`Step N of 6 · <Name>` plus one mark per step (the first is the readiness mark).

### D6. Benches: categories, order and arrival

Categories come from the catalog (`order`, then id); a bench's category is its
`category` field or, if absent, its path. Within a category, benches are listed
in catalog-name order (code-point order, as `jq keys` and 1.7 list them), so
Software Engineering reads cppBench, dotNetBench, flutterBench, frappeBench,
goBench, javaBench, pyBench, rustBench; the mockup's order is illustrative.
Categories without benches are listed dim as "coming soon" and skipped by focus.
Arriving on Benches by ← or → focuses the category zone on the first category
that has benches, matching 1.7's ←/→, which reset focus to a section's first
row. P/G returns and the readiness jump restore the exact zone, category and
bench.

### D7. Two focus zones on Benches

- **Category zone:** ↑/↓ change the current category and preview its benches (no
  bench row is highlighted). Tab, Shift+Tab, Space, or ↓ on the last focusable
  category move to the bench zone on that category's first bench. D does nothing.
- **Bench zone:** ↑/↓ move within the current category only. ↑ on its first bench,
  Tab or Shift+Tab return to the category zone, keeping the category. Space and D
  queue as in 1.7.

`current_selection` stays an index into `bench_items` in both zones, so Space/D,
the footer and `get_checked_state` keep working. The zone, category and About
offset join the main loop's change detection.

### D8. About panel

The About panel is the "small scrolling window". In the bench zone it is titled
`ABOUT <BENCH>` and shows the description (or the tagline), a blank line, then
`Use it for` and `Contains` lists packed with ` · ` under a 13-column label and
wrapped by words. In the category zone it is titled `ABOUT <CATEGORY>` and shows
the category summary and its bench names. With a known height it gets 2–8 text
lines of spare rows. When the text is longer than the window, the top border
shows `a–b of n`, the window's last line `▼ more` (first line `▲ more` once
scrolled), and the bottom border `PgUp/PgDn scroll`; PgUp/PgDn (`ESC [5~`,
`ESC [6~`, trailing `~` consumed) and `[`/`]` move by the window less one line,
clamped. The offset resets when the zone, category or focused bench changes.
*Alternative:* a separate full-screen details view. Rejected: Brett asked for a
small scrolling window on the same screen.

### D9. Height-aware layout

`draw_ui` also reads `tput lines`. Panels are collected first, then laid out in
the rows the head and footer leave. Space is given up in this order:

1. Blank spacers and the wordmark (tight layout: always at 24 rows or fewer, and
   whenever the roomy layout would not fit).
2. On Benches, the category block collapses to one line
   (` CATEGORY  ● Software Engineering · 8 benches   Tab ⇄ benches`).
3. Lists scroll inside their panel with `▲ N more`/`▼ N more`, keeping the
   focused row visible; on Benches the bench panel keeps at least three rows.
4. About shrinks (never below two lines unless hidden).
5. Below the supported size, lines are dropped from the top of the frame rather
   than overprinting the footer.

The four-row wordmark is drawn only at 42+ columns when the height is unknown or
at least 40 rows. An unknown height never clips. A width or height change repaints
the whole frame.

### D10. Padding counts characters

Bash `printf` field widths count bytes, so multibyte text (`…`, `·`, `✓`) is
padded from `${#text}`. Prototype commit `57f07a9` fixed this for requirement
detail lines, which are still misaligned on 1.7. Only single-column glyphs are
used.

### D11. Presentation metadata lives in `bench-config.json`

Add top-level `categories` and per-bench `category`, `tagline`, `usedFor[]` and
`contains[]` beside the existing `url`, `path`, `description`, `ai_keywords` and
`project_scripts`. *Alternative:* a separate presentation file. Rejected: two
files keyed by bench name drift apart, and `bench-config.json` is already what the
TUI, the selection validator, the release freeze and component removal read.
The fields are additive; Python consumers index by name and ignore them.

### D12. Metadata reaches the TUI through the status worker

The worker already runs `init_components` inside Tools, where jq exists, and
publishes `catalog`. It now also writes `bench-categories` and `bench-meta`
beside it, categories first, each atomically (`.tmp` then `mv`), so the arrival
of `bench-meta` marks the metadata complete. The foreground reads them with
`read` into associative arrays, validates bench names (`^[a-zA-Z0-9_+-]+$`) and
category ids (`^[a-z0-9][a-z0-9-]*$`), and the renderer reads only those arrays.
Rows are tab-separated, control characters become spaces, an empty value travels
as `-`, and list items are joined with `|` (a `|` inside an item becomes `/`).
When a TTY is absent (keys piped by tests), interactive and `--select-only` runs
load the same arrays synchronously after `init_components`; `--apply-plan` and
`--dependencies-plan` never load them.

- *Alternative:* run jq in the foreground at startup. Rejected: jq lives in
  Tools, and first paint must not wait for Docker or Tools.
- *Alternative:* publish a JSON snapshot. Rejected: Bash cannot parse it without
  jq or Python.

### D13. Safe lookups that fail closed

Every shell lookup becomes `jq -r --arg n "$bench" '.benches[$n].<field> // empty'`
(and the same for `.infrastructure[$n]` in `setup-workbenches.sh`). Affected:
`interactive-setup.sh` (`check_component_status`, `process_selections`),
`scripts/setup-workbenches.sh`, `scripts/update-project.sh` and
`scripts/launchBench`. `process_selections` refuses a bench whose path is empty
or not under `devBenches/`, `sysBenches/` or `bioBenches/` (the rule
`setup_selection.py` and `release-workbenches.py` already apply) and records it as
failed; no git, clone or setup script runs. A static test rejects any shell file
that interpolates a name into a `.benches.` path, and a behaviour test with a
digit-leading fixture bench proves each consumer resolves the right directory.
*Alternative:* rename 365Bench. Rejected: the name is used by its repository, the
`m365-bench` image mapping, `wave-container-shell.sh` and the release lock.

### D14. Profiles step

The selector area is one line, ` IDENTITIES  ` followed by the cached summary
lines joined with ` · ` and truncated with `…`; the summary is not parsed, so
`setup-profiles.py` stays untouched. Rows: Personal & companies, Workstation
account, AI accounts. Enter or Space opens them through `activate_profile` with
1.7's readiness gate and result notices. The About panel explains the focused row
from fixed text in the TUI. The footer keeps `G Back … Q Quit` on one line.

### D15. Review step

Non-empty INSTALL, UPDATE and REMOVE panels list items in step order with the
step name; REMOVE notes that projects and credentials are kept. Yellow warnings
appear for Shell setup and Org workspace; a yellow blocker line appears while
Apply is blocked. If the grouped panels do not fit, one combined CHANGES list is
shown; if that does not fit either, ↑/↓ scroll it with `▲/▼ N more`, so every
queued change can be read before applying. The scrolling is an addition to the
prototype, which could hide items on short terminals.

### D16. AI assistants, Tools and the footer

AI assistants and Tools keep 1.7's items, order, separator and Space/D rules in
single-column panels (ASSISTANTS and SPEC TOOLS; TOOLS) titled
`I of N installed`; rows show the checkbox, status symbol, name, status label (60+
columns) and queued action. The footer keeps 1.7's context line,
`<Name> · <State>[ → <action>]` (or the category summary in the category zone),
with `Changes selected: N` on the right; acceptance suites wait on that format
(`Codex CLI · (not installed|needs creds|Ready)`, `pyBench · …`). Hints are
per-step and split over two lines at 80+ columns; V is advertised only on
Workstation.

## Mockups

### Approved Benches step (87 columns)

```
workBenches v1.6.0                                                 Ubuntu 24.04 · WSL 2
 ✓ Workstation ── ● Benches 2 ── ○ AI assistants 1 ── ○ Tools 1 ── ○ Review
───────────────────────────────────────────────────────────────────────────────────────
 CATEGORY                                                                Tab ⇄ benches
   ● Software Engineering       8 benches · 4 installed · 1 queued
   ○ Science                    2 benches · 1 installed
   ○ System Administration      2 benches · 1 installed · 1 queued
   ○ Electrical Engineering     coming soon

╭─ SOFTWARE ENGINEERING ─────────────────────────────────────────── 4 of 8 installed ─╮
│   [ ] ✓ pyBench        Python                              Installed                │
│ › [✓] ✓ javaBench      Java and JVM services               Installed     → Update   │
│   [ ] ✗ goBench        Go                                  Not installed            │
│   [ ] ✗ rustBench      Rust                                Not installed            │
│   ▼ 4 more                                                                          │
╰─────────────────────────────────────────────────────────────────────────────────────╯
╭─ ABOUT JAVABENCH ──────────────────────────────────────────────────────── 1–4 of 9 ─╮
│ Java development environment for JVM services, libraries and Android tooling.       │
│                                                                                     │
│ Use it for   Spring Boot APIs · Maven and Gradle builds · JUnit test runs           │
│ Contains     OpenJDK · Maven · Gradle · Spring Boot CLI · …                  ▼ more │
╰────────────────────────────────────────────────────────────────── PgUp/PgDn scroll ─╯
───────────────────────────────────────────────────────────────────────────────────────
javaBench · Ready → update                                          Changes selected: 2
Navigation: ↑↓ Move  Tab Category  Space Select  D Remove  PgUp/PgDn About
            ←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit
```

Notes on the approved mockup:

- It predates the Profiles decision: the final nav also lists Profiles before
  Review, which at 87 columns needs short connectors (D5).
- The About text and taglines are placeholder copy; the catalog uses the drafted,
  evidence-based copy once Brett approves it.
- Bench order and counts are illustrative (D6).
- The version line reads v1.6.0 because the mockup was drawn before 1.7.

### Illustrative Workstation, Review and Profiles steps

These follow the approved description; they are not reviewed mockups. The
current nav item is highlighted on screen, shown here by its padding.

```
workBenches v1.7.0                                                 Ubuntu 24.04 · WSL 2
  ✓ Workstation  ─ ○ Benches 2 ─ ○ AI assistants 1 ─ ○ Tools 1 ─ ○ Profiles ─ ○ Review
───────────────────────────────────────────────────────────────────────────────────────
 REQUIREMENTS · 3/3 ready   WSL 2 Up   Docker Up   Tools Up   Vault Up [V Connect]

╭─ REQUIRED SOFTWARE ───────────────────────────────────────────────────── 3/3 ready ─╮
│ › ✓ WSL 2                                                               Up  [Check] │
│     Ubuntu-24.04 runs as a WSL 2 distribution.                                      │
│   ✓ Docker                                                              Up  [Check] │
│   ✓ Tools                                                               Up  [Check] │
╰─────────────────────────────────────────────────────────────────────────────────────╯

╭─ OPTIONAL VAULT ────────────────────────────────────────────────────────────────────╮
│   ✓ Vault                                                Up · Signed out  [Connect] │
╰─────────────────────────────────────────────────────────────────────────────────────╯
───────────────────────────────────────────────────────────────────────────────────────
WSL 2 · Up                                                          Changes selected: 4
Navigation: ↑↓ Move  Enter Check  V Vault
            ←→ Steps  P Back  R Refresh  Q Quit
```

```
workBenches v1.7.0                                                 Ubuntu 24.04 · WSL 2
 ✓ Workstation ─ ✓ Benches 2 ─ ✓ AI assistants 1 ─ ✓ Tools 1 ─ ✓ Profiles ─  ● Review
───────────────────────────────────────────────────────────────────────────────────────
Nothing has changed yet. Enter applies these changes.

╭─ INSTALL · 2 ───────────────────────────────────────────────────────────────────────╮
│ + rustBench                                                          Benches        │
│ + Shell setup                                                        Tools          │
╰─────────────────────────────────────────────────────────────────────────────────────╯
╭─ UPDATE · 2 ────────────────────────────────────────────────────────────────────────╮
│ ↻ javaBench                                                          Benches        │
│ ↻ Codex CLI                                                          AI assistants  │
╰─────────────────────────────────────────────────────────────────────────────────────╯
⚠ Shell setup replaces your shell settings.
───────────────────────────────────────────────────────────────────────────────────────
Review · Nothing applied yet                                        Changes selected: 4
Navigation: ↑↓ Scroll  ← Back  Enter Apply  P Workstation  R Refresh  Q Quit
```

```
workBenches v1.7.0                                                 Ubuntu 24.04 · WSL 2
 ✓ Workstation ─ ✓ Benches 2 ─ ✓ AI assistants 1 ─ ✓ Tools 1 ─  ● Profiles  ─ ○ Review
───────────────────────────────────────────────────────────────────────────────────────
 IDENTITIES  Personal identities: 1 · Default: me@example.org · GitHub accounts: 2 · C…

╭─ PROFILES ─────────────────────────────────────────────────────────── Now or later ─╮
│ › Personal & companies                                                              │
│   Workstation account                                                               │
│   AI accounts                                                                       │
╰─────────────────────────────────────────────────────────────────────────────────────╯
╭─ ABOUT PERSONAL & COMPANIES ────────────────────────────────────────────────────────╮
│ Personal identity, GitHub and company accounts. Company, GitHub and AI access       │
│ are authorized separately.                                                          │
╰─────────────────────────────────────────────────────────────────────────────────────╯
───────────────────────────────────────────────────────────────────────────────────────
Personal & companies                                                Changes selected: 4
Navigation: ↑↓ Move  Enter Open  PgUp/PgDn About
            ←→ Steps  G Back  P Workstation  R Refresh  Q Quit
```

## Key Map

| Key | Workstation | Benches: category zone | Benches: bench zone | AI assistants, Tools | Profiles | Review |
|---|---|---|---|---|---|---|
| ← / → | previous / next step; no wrap at Workstation or Review | same | same | same | same | same |
| ↑ / ↓ | move between service rows | change category (preview); ↓ on the last enters benches | move within the category; ↑ on the first returns to categories | move; skip the separator | move | scroll the list when it does not fit |
| Tab / Shift+Tab | — | enter the bench zone | return to the category zone | — | — | — |
| Space | run the row's action | enter the bench zone | queue/unqueue install or update | queue/unqueue install or update | open the row | — |
| D | — | — | queue/unqueue removal | queue/unqueue removal | — | — |
| Enter | run the row's action | open Review | open Review | open Review | open the row | apply (gated) |
| PgUp/PgDn, `[` / `]` | — | scroll About | scroll About | — | scroll About | — |
| P | return to the remembered step | go to Workstation | go to Workstation | go to Workstation | go to Workstation | go to Workstation |
| G | go to Profiles | go to Profiles | go to Profiles | go to Profiles | return to the remembered step | go to Profiles |
| V | Vault action (advertised) | Vault action | Vault action | Vault action | Vault action | Vault action |
| R | refresh; queued changes and focus kept | same | same | same | same | same |
| Q | quit, exit 130 | same | same | same | same | same |

## Focus Model

- Canonical focus: `CURRENT_SECTION`, `current_selection`, and on Benches the
  zone, current category and About offset.
- Two return targets, each holding step, row, zone and category: one for P
  (written by P, by ← from Benches, and by the readiness jump) and one for G
  (written by G, by → from Tools, and by ← from Review). The defaults are Benches'
  category zone and its first category.
- Catalog arrival and refresh keep the focused bench by name, as 1.7's
  `poll_status_loader` does, plus the zone and category.
- The main loop redraws when any part of the focus or queued state changes;
  `draw_ui` still writes only the changed lines.

## Layout and Height Rules

| Region | Roomy layout | Tight layout (≤ 24 rows, or roomy does not fit) |
|---|---|---|
| Banner | four-row wordmark at 42+ columns and unknown or ≥ 40 rows; else one line | one line, no padding |
| Version/OS, nav, rule | one line each | one line each |
| Selector area | strip / category block / identities line | strip / one-line category block / identities line |
| Spacers | one blank line between selector area and panels | none |
| Panels | full | scroll with `▲/▼ N more`; focused row stays visible |
| About (Benches, Profiles) | 2–8 lines from spare rows | 2+ lines if room, otherwise hidden |
| Footer | rule, context line, hints (two lines at 80+ columns) | same |

Width: frame width is the terminal width less one, clamped to 36–87; panels
drop the tagline below 70 columns and the status label below 50 (60 on AI
assistants and Tools); panel titles drop their right-hand label before the title
is cut.

## Data Flow

```
status worker (background, inside Tools: jq, git, python3)
  init_components ──► catalog            bench names, one per line
  bench_metadata  ──► bench-categories   id, order, label, summary  (TSV)
                  ──► bench-meta         name, category, tagline, description,
                                         usedFor, contains          (TSV)
  status checks   ──► <key>.row          state, detail
        │  each file written to .tmp, then mv
        ▼
poll_status_loader (foreground, Bash builtins only)
  read + validate ──► bench_items, bench_meta_*, bench_category_*,
                      component_status, requirement_detail
        ▼
render_setup_frame / draw_ui (in-memory state only; no jq, python3, docker, git)
```

## Risks / Trade-offs

- **jq hazard becomes live with 365Bench.** → D13 lands before or with the catalog
  additions, with a static check, a digit-leading regression test and fail-closed
  handling of unresolved paths.
- **Acceptance suites drive the TUI by keystroke.** → Update sequences, keep every
  asserted outcome, and rerun them on real hosts before release (table below).
- **Enter no longer applies on the first press.** → Review states that nothing has
  changed yet; footer hints and docs say "Enter Review" and "Enter Apply". On the
  first screen Enter now runs the focused service action (Check when everything
  is Up), which only re-checks readiness.
- **Six-step nav width.** → Short connectors at 87 columns, then the compact form
  (D5); flagged as an open question.
- **Rendering cost in Bash.** Height budgeting and About wrapping run on every
  frame. → Use in-memory arrays only, keep partial redraw, and measure frame time
  at 87×40 in tests so key response stays immediate.
- **Glyph width differences across terminals** (`⚠`, `●`, `▼`). → Use
  single-column glyphs only, pad by characters (D10), and check Windows Terminal
  and the VS Code terminal manually.
- **Copy drifts from bench images.** → Copy is evidence-based and reviewed by
  Brett; catalog tests enforce presence and length; review copy when a bench
  image changes.
- **Newly offered benches reach users.** goBench, rustBench and 365Bench become
  installable from the TUI. → Release QA installs at least 365Bench through the
  TUI on a disposable workstation, which also exercises the digit-leading path.
- **Catalog rewrites drop metadata.** `update-bench-config.sh` regenerates the file
  from scratch and already drops `ai_keywords`. → It and `new-bench.sh` must
  preserve existing fields (bench-catalog spec).
- **The prototype is not a base.** It predates Profiles and numbers Review 4. →
  Implement on 1.7 from these specs; use the prototype only as a reference.

### Acceptance-suite impact

| Suite | Today | With the wizard |
|---|---|---|
| `test-workstation-acceptance.py` | waits for `REQUIREMENTS · N/N ready … Navigation:`; `\x1b[C\x1b[B\x1b[B \n` queues Codex and applies; Profiles via G; `\n` for an empty run | start on Workstation: `→ →` reaches AI assistants; `Enter Enter` reviews and applies; an empty run is `→ Enter Enter`; benches use `→ Tab` and index within the bench's category; after leaving Workstation, wait for the nav's `✓ Workstation` mark plus `Navigation:` instead of the strip; Profiles regex follows the new selector label |
| `test-wsl-workstation-acceptance.py` | same patterns, plus frozen-source and bench install/remove | same changes; outcomes (local work preserved, images removed) unchanged |
| `test-component-lifecycle.py` | `PQ` and `GQ` assert page text; `D→↓↓D\n` removes pyBench and Codex | text assertions follow the new panels and labels; `→ Tab D → ↓ ↓ D Enter Enter` |
| `test-tools-runtime.py` | queues a bench with Space on the main screen, then uses the strip's V button | `→ Tab Space ←` queues the first bench and returns to Workstation, where `[V …]` is visible |
| `test-setup-async.py`, `test-setup-requirements.py`, `test-setup-profiles.py`, `test-setup-guided-flow.py`, `test-setup-cancel.sh` | render or drive sections directly | section numbers are unchanged (D1); renders that expect the strip set the Workstation step; piped Enter becomes `Enter Enter` |

## Migration Plan

1. Land the safe lookups and the catalog changes together with the wizard in one
   pull request into `release/1.7.0`, carrying this change and Speckit feature
   `specs/029-setup-guided-wizard`.
2. No data migration: selection files, `setup.sh` modes and the apply path are
   unchanged, and catalog fields are additive.
3. If 1.7 freezes first, retarget the same pull request to the 1.8 line and move
   the scope note from `docs/release-1.7.0.md` to the 1.8 plan.
4. Rollback is a revert. Benches installed from the new catalog entries keep their
   checkouts and images; a reverted TUI simply stops offering them.

## Open Questions

For `/speckit-clarify` in `specs/029-setup-guided-wizard`:

1. Should `phpBench` and `opsBench` (local, gitignored clones outside the release
   lock) be catalogued?
2. Science sub-groups (bio, chemistry, physics): now, or when those benches exist?
3. Should AI assistants and Tools adopt categories and an About panel now?
4. Should the Workstation step's focused-row detail move into an About panel?
5. Review and approval of the drafted copy for all 12 benches.
6. Where do queued counts appear for Profiles (its rows are actions, so nothing
   there is queued in the TUI today)?
7. Six-step nav at 87 columns: accept short connectors (and the compact form for
   two-digit counts), or shorten a label?
8. Bench order within a category: catalog-name order (D6), or a curated order as
   the mockup suggests?
