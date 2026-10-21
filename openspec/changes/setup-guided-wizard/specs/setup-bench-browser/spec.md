# Spec Delta: setup-bench-browser

## Purpose

Defines the Benches step of the setup wizard: the category block, the category
and bench focus zones, the bench panel, the scrolling About panel, the
height-aware layout, and how catalog metadata reaches the TUI without foreground
discovery, including fallbacks when metadata is missing.

## ADDED Requirements

### Requirement: Category block
The Benches step SHALL list every catalog category in catalog `order` (then by id) under a `CATEGORY` label with a `Tab ⇄ benches` hint, marking the current category `●` and the others `○`, each followed by `N benches · I installed · Q queued` with zero parts omitted and `bench` for one. A bench SHALL count as installed when Space would queue an update rather than an install (status `installed`, `needs creds` or `image only`, as 1.7 treats them). A category with no benches SHALL be shown dim as `coming soon` and SHALL NOT be focusable.

#### Scenario: Category counts
- **WHEN** Software Engineering has 8 benches with 4 installed and 1 queued, and Science has 2 benches with 1 installed and none queued
- **THEN** the block shows `Software Engineering  8 benches · 4 installed · 1 queued` and `Science  2 benches · 1 installed`

#### Scenario: Coming soon
- **WHEN** Electrical Engineering has no benches
- **THEN** it is listed dim with `coming soon`
- **AND** ↑/↓ in the category zone never focus it

### Requirement: Category zone
In the category zone ↑/↓ SHALL change the current category among those that have benches and show that category's benches without highlighting a bench row. Tab, Shift+Tab, Space, or ↓ on the last focusable category SHALL move to the bench zone on the category's first bench, and D SHALL do nothing.

#### Scenario: Preview a category
- **WHEN** Software Engineering is current in the category zone and the user presses ↓
- **THEN** Science becomes current and the bench panel lists gentecBench and simBench with no row marked focused

#### Scenario: Enter the bench zone
- **WHEN** System Administration is current in the category zone and the user presses Tab
- **THEN** the bench zone has focus on that category's first bench

#### Scenario: Down past the last category
- **WHEN** the last category with benches is current and the user presses ↓
- **THEN** the bench zone has focus on that category's first bench

#### Scenario: Space does not queue in the category zone
- **WHEN** the category zone has focus and the user presses Space
- **THEN** the bench zone gains focus and nothing is queued

### Requirement: Bench zone
In the bench zone ↑/↓ SHALL move only within the current category's benches. ↑ on the first bench, Tab or Shift+Tab SHALL return to the category zone with the same category current, and Space and D SHALL queue and unqueue changes by the same rules as before this change.

#### Scenario: Stay within the category
- **WHEN** the last bench of Software Engineering is focused and the user presses ↓
- **THEN** focus does not move

#### Scenario: Back to categories
- **WHEN** the first bench of Science is focused and the user presses ↑
- **THEN** the category zone has focus with Science current

#### Scenario: Queue an install
- **WHEN** rustBench is not installed and focused and the user presses Space
- **THEN** rustBench is queued for install and its row shows `→ Install`

### Requirement: Bench panel
The bench panel SHALL be titled with the current category and `I of N installed` (installed as in the category block; `Loading…` while any of its statuses is unknown) and SHALL show one row per bench, in catalog-name order (code-point order of the bench names, as 1.7 lists them), with checkbox, status symbol, name, tagline, status label and queued action. Below 70 columns it SHALL drop the tagline and below 50 columns the status label; the focused row SHALL be marked `›` only in the bench zone, and when the rows do not fit the panel SHALL show `▲ N more` or `▼ N more` and keep the focused row visible.

#### Scenario: Full row at 87 columns
- **WHEN** javaBench is installed, queued for update and focused in the bench zone
- **THEN** its row shows `› [✓] ✓ javaBench`, its tagline, `Installed` and `→ Update`

#### Scenario: Narrow row
- **WHEN** the frame is 40 columns wide
- **THEN** each bench row shows its checkbox, status symbol, name and queued action, with no tagline and no status label

#### Scenario: Panel scrolls
- **WHEN** only four of eight benches fit and the user moves focus to the sixth
- **THEN** the sixth bench is visible and the panel shows how many benches are hidden above and below

### Requirement: About panel content
The About panel SHALL describe the current focus. In the bench zone it SHALL be titled `ABOUT <BENCH>` and show the bench's description, then a `Use it for` list and a `Contains` list; in the category zone it SHALL be titled `ABOUT <CATEGORY>` and show the category summary and the names of its benches.

#### Scenario: Bench details
- **WHEN** simBench is focused in the bench zone
- **THEN** the About panel shows simBench's catalog description, a `Use it for` line with its `usedFor` items and a `Contains` line with its `contains` items

#### Scenario: Category details
- **WHEN** System Administration is current in the category zone
- **THEN** the About panel shows the category summary and the names 365Bench and cloudBench

### Requirement: About scrolling
When the About text is longer than its window, the panel SHALL show `a–b of n` in its top border, `▼ more` on the last visible line while text remains below, `▲ more` on the first visible line once scrolled, and a `PgUp/PgDn scroll` hint in its bottom border. PgUp/PgDn and `[`/`]` SHALL scroll by the window height less one line, clamped to the text, and the offset SHALL return to the first line whenever the zone, category or focused bench changes, and SHALL be kept, clamped to the new text, when the same bench's details are refreshed.

#### Scenario: Page down
- **WHEN** the About window shows lines 1–4 of 9 and the user presses PgDn
- **THEN** it shows lines 4–7 of 9 with `▲ more` and `▼ more`

#### Scenario: Clamp at the end
- **WHEN** the About window shows lines 4–7 of 9 and the user presses `]` twice
- **THEN** it shows lines 6–9 of 9 with no `▼ more`

#### Scenario: Reset on focus change
- **WHEN** the About window is scrolled and the user moves to another bench
- **THEN** the About window shows the new bench's text from its first line

#### Scenario: Short text
- **WHEN** the About text fits its window
- **THEN** no range, `more` marker or scroll hint is shown

### Requirement: Height-aware Benches layout
With a known terminal height the Benches step SHALL give rows first to the category block, then to at least three bench rows (or all of them when fewer), then to between two and eight About lines. Rows left over SHALL go first to more bench rows, up to every bench of the current category, and then to About, up to eight lines. When the minimums do not fit, the category block SHALL collapse to one line naming the current category; with an unknown height nothing SHALL be clipped.

#### Scenario: Roomy terminal
- **WHEN** Benches is rendered at 88×40 with Software Engineering current
- **THEN** the category block lists every category on its own row and About shows between two and eight lines

#### Scenario: 24-row terminal
- **WHEN** Benches is rendered at 80×24
- **THEN** the category block is one line naming the current category, the bench panel shows at least three bench rows, and the frame has at most 24 lines

#### Scenario: Unknown height
- **WHEN** the terminal height cannot be read
- **THEN** every category, every bench of the current category and the whole About text are rendered

### Requirement: Metadata delivery without discovery
The background status worker SHALL publish bench and category metadata beside its catalog file, each file written atomically, and the foreground SHALL read it with Bash builtins only, ignoring bench names and category ids that fail validation and replacing control characters (U+0000–U+001F and U+007F–U+009F, including ESC and tab) with spaces. Until the metadata arrives, or checks finish without it (see Degraded metadata), the Benches step SHALL show `Loading benches…`; when checks finish, or cannot start, without publishing a bench list, it SHALL instead say that the bench list could not be loaded and that R retries, and no bench SHALL be queueable. The same control-character replacement SHALL apply to every other text the TUI shows but did not write: status details from the worker, the identities summary and the results of interactive helpers.

#### Scenario: Metadata arrives from the worker
- **WHEN** the worker finishes reading the catalog inside Tools
- **THEN** the Benches step shows categories, taglines and About text without the foreground having run jq or Python

#### Scenario: Control characters in catalog text
- **WHEN** a bench description contains an escape sequence such as `ESC [2J`
- **THEN** the TUI shows the text without the escape character and the screen is not cleared

#### Scenario: Before metadata arrives
- **WHEN** Benches is shown before the worker has published the catalog and its metadata
- **THEN** the step shows `Loading benches…` and no bench can be queued

#### Scenario: No bench list
- **WHEN** checks finish without the worker publishing a bench list
- **THEN** the Benches step says the bench list could not be loaded and that R retries
- **AND** no bench can be queued

#### Scenario: Control characters in other outside text
- **WHEN** a status detail from the worker or the identities summary contains `ESC [2J`
- **THEN** the TUI shows the text without the escape character and the screen is not cleared

### Requirement: Degraded metadata
A bench without a `category` SHALL be placed by its path: `devBenches/` under Software Engineering, `bioBenches/` under Science, `sysBenches/` under System Administration and any other path under `Other benches`. An unknown category id SHALL be listed after the known categories, ordered by id, with a label made by title-casing its hyphen-separated words. When categories arrive without per-bench metadata, benches SHALL still be placed by path into them. A bench SHALL show the metadata fields that exist, and its About text SHALL be `No details for this bench yet.` when its description, uses and contents are all missing. When checks finish without any metadata (neither categories nor bench details), every catalogued bench SHALL be listed in one `Other benches` group with that About text, and the group's About SHALL list its bench names. Every such bench SHALL remain selectable.

#### Scenario: Missing category field
- **WHEN** a catalogued bench at `sysBenches/testBench` has no `category`
- **THEN** it is listed under System Administration

#### Scenario: Unknown category id
- **WHEN** a bench names the unknown category id `quantum-computing`
- **THEN** it is listed under `Quantum Computing`, after the known categories

#### Scenario: Categories without bench details
- **WHEN** checks finish after the worker published categories but no bench details
- **THEN** each bench is listed under the category its path gives, with About text `No details for this bench yet.`

#### Scenario: No metadata at all
- **WHEN** checks finish and the worker published the catalog but no metadata
- **THEN** every bench is listed under `Other benches` with `No details for this bench yet.`
- **AND** Space still queues a bench that is not installed

### Requirement: Focus survives catalog updates
When the catalog or its metadata arrives or is refreshed, the Benches step SHALL keep the focused bench (matched by name), the zone, the current category and every queued change, and a bench remembered by the P or G return target SHALL be kept by name the same way. When the focused or a remembered bench is no longer catalogued, that focus SHALL fall back to the category zone on the same category (or the first category that has benches), and the bench's queued change SHALL be dropped, so Review lists only changes that can apply. When the bench list first arrives while Benches shows `Loading benches…`, focus SHALL go to the category zone on the first category that has benches.

#### Scenario: Catalog arrives while browsing
- **WHEN** the user has focused pyBench in the bench zone and refreshed metadata arrives
- **THEN** pyBench stays focused in the Software Engineering bench zone and queued changes are unchanged

#### Scenario: Focused bench leaves the catalog
- **WHEN** goBench is focused and queued for install and a refreshed catalog no longer lists it
- **THEN** the category zone has focus on Software Engineering
- **AND** goBench's queued change is gone
