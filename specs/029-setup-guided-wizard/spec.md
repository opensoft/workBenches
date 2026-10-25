# Feature Specification: Guided setup wizard

**Feature Branch**: `029-setup-guided-wizard`

**Created**: 2026-10-21

**Status**: Draft

**Related 1.7 addition (2026-10-23)**: Brett requested
[Kimi/GLM profile credentials](../031-kimi-glm-profile-credentials/spec.md).
Feature 031 owns those new profile, persistence and custody contracts; they are
planned separately and are not evidence that this wizard's completed UI work
implemented credential support. Preserve the wizard queue/navigation contracts
when integrating that feature.

**Input**: User description: "Replace the setup TUI's three-column main screen and its separate Requirements and Profiles pages with a guided wizard (Workstation → Benches → Agents → Tools → Profiles → Review) for workBenches 1.7, as decided in the approved OpenSpec change `setup-guided-wizard`: benches browsed by category with a small scrolling About panel, Enter opening Review before anything is applied, a layout that fits 36–87+ columns and any known height, and a complete, safely-read bench catalog."

**Source of decision**: OpenSpec change [`openspec/changes/setup-guided-wizard/`](../../openspec/changes/setup-guided-wizard/) —
[proposal](../../openspec/changes/setup-guided-wizard/proposal.md),
[design](../../openspec/changes/setup-guided-wizard/design.md) (mockups, key map, focus model, data flow, risks, open questions),
[tasks](../../openspec/changes/setup-guided-wizard/tasks.md), and four capability deltas:
[setup-wizard-flow](../../openspec/changes/setup-guided-wizard/specs/setup-wizard-flow/spec.md),
[setup-wizard-layout](../../openspec/changes/setup-guided-wizard/specs/setup-wizard-layout/spec.md),
[setup-bench-browser](../../openspec/changes/setup-guided-wizard/specs/setup-bench-browser/spec.md),
[bench-catalog](../../openspec/changes/setup-guided-wizard/specs/bench-catalog/spec.md) (45 requirements).
This feature is that change's single Speckit handoff; both land in one pull request into `release/1.7.0` (retarget to 1.8 without requirement changes if 1.7 freezes first).
The OpenSpec deltas stay authoritative for exact wording; implementation detail lives in `design.md` and the later `plan.md`.

**Clarification**: all 20 questions in `clarify-questions.md` were answered by Brett Heap on 2026-10-21; the answers are recorded below and folded into the requirements here and in the OpenSpec change.

**Checklist review**: the release-gate checklists in `checklists/` (2026-10-21) closed wording gaps in this spec and the OpenSpec deltas where the behaviour was already decided (by 1.7, the approved design or the clarifications). The 15 decisions it raised (`checklists/README.md` › Needs Brett, NB-1 to NB-15) were answered by Brett Heap on 2026-10-21 and are recorded under Clarifications › Session 2026-10-21 (checklist decisions), including his approval of the OpenSpec change (NB-15).

## Clarifications

### Session 2026-10-21

- Q: How should the six-step nav fit standard terminal widths? → A: Other — Brett: "use Agents instead of ai or ai assistants". The AI assistants step is named Agents wherever a step is named; the nav uses short ` ─ ` connectors and, at 79 columns with three single-digit counts, fits an 80-column terminal; the compact `Step N of 6 · <Name>` form remains only for frames too narrow for the full nav.
- Q: Which step should setup open on? → A: A — Workstation.
- Live review, 2026-10-22 (029-A02): Brett renamed the step from Agents to Harness and requested blank lines between the category block, bench panel and About. The earlier naming answer is retained as history; Harness is the current label everywhere the step is named. Extra section gaps apply to roomy layouts; tight layouts retain their existing content budget.
- Q: What should Enter do on the Workstation step? → A: A — run the focused service action, like Space.
- Q: How should Review behave when it does not fit, and can it edit the queue? → A: A — read-only; ↑/↓ scroll with `▲/▼ N more` when the list does not fit.
- Q: Do you approve the drafted copy for all 12 benches? → A: C — build with the draft; Brett approves or edits it in the running TUI before merge, recorded as a merge gate.
- Q: What is the minimum supported terminal size? → A: A — 36×24; below it best effort (lines drop from the top; below 36 columns lines may wrap).
- Q: How should footer hints fit at narrow widths? → A: B — below 60 columns at most two hint lines: the step's own keys plus ←→, Enter and Q; P, G, R, V and PgUp/PgDn keep working but are listed only at 60+ columns.
- Q: Where should focus land when arriving on Benches with ← or →? → A: A — the category zone on the first category that has benches, every time.
- Q: Should the Workstation step show the workBenches account and AI accounts? → A: B — no account rows; keep 1.7's `G Profiles` label on the OPTIONAL VAULT panel as the pointer.
- Q: Should phpBench and opsBench be catalogued? → A: A — no; the catalog matches the release lock exactly.
- Q: Should AI assistants and Tools get categories or an About panel now? → A: A — not now.
- Q: In what order should benches appear within a category? → A: A — catalog-name order.
- Q: Should categories without benches be shown as "coming soon"? → A: A — yes, dim and never focusable.
- Q: Should the bench copy name tool versions? → A: B — no version numbers in taglines, `usedFor` or `contains`; the catalog test rejects version-like tokens.
- Q: What key-response budget should the tests enforce? → A: A — 100 ms per key press (median of repeated renders at 87×40 on a developer workstation).
- Q: When should the readiness jump fire? → A: A — after every completed check run, including runs started by R, as in 1.7.
- Q: Science sub-groups (biology, chemistry, physics): now or later? → A: A — later, when chemistry or physics benches exist.
- Q: Should the Workstation explanation move into an About panel? → A: A — no; it stays under the focused row.
- Q: Should the Profiles step ever show a count in the nav? → A: A — no, never.
- Q: Below 60 columns, how should the footer show the queued total? → A: A — `Changes: N` at the right, with the context line cut with `…`.

### Session 2026-10-21 (checklist decisions)

Brett Heap answered the 15 decisions raised by the release-gate checklists (`checklists/README.md` › Needs Brett), choosing the recommended option each time.

- NB-1: What does the context line show where nothing is focused or a row has no state? → A: A — Review shows `Review · Nothing applied yet`, Profiles the row name alone, Benches `Loading benches…`; the total stays at the right (FR-021).
- NB-2: What is "the category summary" on the context line? → A: A — the category name and its counts as in the category block, e.g. `Science · 2 benches · 1 installed` (FR-021).
- NB-3: Does the compact nav show queued counts? → A: A — no; the footer keeps the total (FR-007).
- NB-4: How many hint lines between 60 and 79 columns? → A: A — the full per-step list, wrapped over as many lines as it needs; SC-002 still bounds 24-row frames (FR-022).
- NB-5: What happens when a bench leaves the catalog on refresh? → A: A — focus and any return target naming it fall back to the category zone on the same category (or the first category with benches); its queued change is dropped; About keeps its offset, clamped, when the same bench's text is refreshed (FR-026, FR-046, FR-051, SC-008, Edge Cases).
- NB-6: Which characters may bench copy contain? → A: A — single-column printable characters only; the catalog test also rejects wide, fullwidth, combining, zero-width and bidi formatting characters (FR-053).
- NB-7: Does the control-character rule cover outside text other than catalog text? → A: A — yes: status details, the identities summary and helper results too (FR-048, SC-011).
- NB-8: Is the digit-leading proof extended to the Python consumers? → A: A — yes; SC-004 counts 8 of 8 consumers (FR-057, SC-004).
- NB-9: How do the catalog maintenance scripts meet the lock-only catalog? → A: A — regeneration skips, with a warning, benches the release lock does not record; the new-bench script still adds entries, and the docs say a new bench needs a lock entry and copy first (FR-059).
- NB-10: How are partly missing details shown? → A: A — unknown ids get a title-cased label and are ordered by id; uncategorised benches outside the bench roots go to `Other benches`; categories without bench details still place benches by path; present fields are shown, with `No details for this bench yet.` when description, uses and contents are all missing; `Other benches` About lists its benches (FR-050).
- NB-11: What counts as "installed" in the counts? → A: A — a bench Space would update rather than install (`installed`, `needs creds`, `image only`) (FR-041, FR-044).
- NB-12: Do spare rows on Benches go to bench rows or About first? → A: A — bench rows first, up to every bench of the current category, then About up to eight lines (FR-047).
- NB-13: What does Benches show if no bench list ever arrives? → A: A — a line saying the bench list could not be loaded and that R retries; nothing can be queued (FR-049).
- NB-14: Where does Review's list start when Review opens? → A: A — at the first item when reached by Enter or ←/→; a P or G return restores the remembered position (FR-012).
- NB-15: Is the OpenSpec change approved? → A: A — yes: Brett Heap approved the proposal, design and four deltas on 2026-10-21 (OpenSpec `tasks.md` 1.1).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Step through setup and apply only from Review (Priority: P1)

A person runs `./setup.sh` on a new or existing workstation. Instead of three side-by-side lists, setup leads them one screen at a time through Workstation, Benches, Harness, Tools, Profiles and Review. A nav bar always shows where they are, what is queued on each step and whether the workstation is ready. They queue installs, updates and removals as they go; Enter takes them to Review, which lists every queued change, and only Enter on Review applies.

**Why this priority**: This is the change itself. It replaces the screen that overflows narrow terminals, gives a new workstation an order to follow, and removes the risk of applying queued changes on the first Enter without seeing them. Every other story builds on the step model.

**Independent Test**: Drive the TUI by keystrokes on a fixture workstation: queue one AI-assistant update and one tool install, press Enter, check that Review lists both in the right groups and that nothing has been applied, press Enter again, and check that exactly those changes are applied (or, in a selection-only run, that the selection file contains exactly them).

**Acceptance Scenarios**:

1. **Given** setup starts on a terminal, **When** the first frame appears, **Then** it shows the Workstation step and a nav bar listing Workstation, Benches, Harness, Tools, Profiles and Review in that order, with no three-column component screen.
2. **Given** the Tools step is shown, **When** the user presses →, **Then** Profiles is shown; **and when** they press ←, **Then** Tools is shown again with its first row focused.
3. **Given** Workstation is shown, **When** the user presses ←, **Then** the step does not change; likewise → on Review; **and when** they press → on Workstation, **Then** Benches is shown with the category zone focused on the first category that has benches.
4. **Given** two benches and one agent are queued and nothing else, **When** any step is shown, **Then** the nav reads `Benches 2` and `Harness 1`, and Tools, Profiles and Review show no count.
5. **Given** checks are running, **When** any step is shown, **Then** the nav's Workstation item shows a blinking `…`; when checks finish with Docker Down it shows a yellow `⚠`, and when every required item is Up a green `✓`.
6. **Given** Codex CLI is queued for update, **When** the user presses Enter on the Harness step, **Then** Review is shown, nothing is installed or updated, and the queued change is unchanged.
7. **Given** rustBench is queued for install, javaBench and Codex CLI for update and pyBench for removal, **When** Review is shown, **Then** rustBench (Benches) is under INSTALL, javaBench (Benches) and Codex CLI (Harness) under UPDATE, pyBench under REMOVE, with the line "Nothing has changed yet. Enter applies these changes."
8. **Given** Shell setup and Org workspace are queued, **When** Review is shown, **Then** yellow warnings say that Shell setup replaces shell settings and that Org workspace may create a GitHub repository.
9. **Given** more changes are queued than Review has rows for, **When** Review is shown, **Then** it shows how many items are hidden above or below, and ↑/↓ scroll the list until every queued item has been displayed; no key on Review queues or unqueues a change.
10. **Given** Codex CLI is installed, **When** the user presses Space on it, **Then** it is queued for update and its row shows `→ Update`; **given** an item that is not installed, **When** they press D on it, **Then** nothing is queued.
11. **Given** every required item is Up, checks have finished and Codex CLI is queued for update, **When** the user presses Enter on Review, **Then** setup applies exactly the queued changes, as Enter did before this change.
12. **Given** checks are still running, **When** the user presses Enter on Review, **Then** nothing is applied, Review says Apply is waiting for checks, and the TUI stays open; **and given** checks finished with Docker Down, **Then** nothing is applied and Review says workstation requirements must be resolved first.
13. **Given** a `--select-only` run with pyBench queued for install and Codex CLI for update, **When** the user presses Enter on Review, **Then** the selection file has `schemaVersion` 1 and exactly the components `bench_pyBench`/`install` and `codex_cli`/`update`.
14. **Given** nothing is queued, **When** Review is shown, **Then** it says no changes are selected and that Enter finishes without changes; **when** the user presses Enter, **Then** setup exits with status 0 without applying anything or building any image.
15. **Given** Docker is missing or Down, **When** Space selects its install/start and Enter opens Review, **Then** no action runs until Review Apply; applying installs/starts selected prerequisites before other work.
16. **Given** Workstation is shown on WSL with every service Up and the user signed out, **Then** one Containers panel lists WSL 2, Docker and Tools with checkboxes and `Installed · Up` and optional Vault with its installation/runtime status; About describes the focused service, the full footer shows `G Profiles`, and no account row appears in Containers.
17. **Given** every required item is Up, **When** the user presses Enter on Profiles › AI accounts, **Then** the existing AI account setup opens and on return Profiles shows "Profile action completed." with queued changes unchanged; **given** Docker is Down, **Then** no Profiles action opens and a notice asks to resolve workstation requirements first.
18. **Given** javaBench is installed, queued for update and focused with two changes queued in total, **Then** its state and queued action appear in the bench list, the footer divider shows `Changes selected: 2`, and no duplicate focused-bench context line appears below About.
19. **Given** `interactive-setup.sh --apply-plan <file>` runs with a valid selection file, **Then** it applies the selection without drawing any wizard frame.
20. **Given** Profiles is shown with Personal & companies focused, **Then** the identities line is directly under the rule, the rows Personal & companies, Workstation account and AI accounts are listed and an About panel explains Personal & companies; **when** the user presses ↓, **Then** About explains Workstation account.
21. **Given** more changes are queued than Review has rows, **When** the user presses Enter on Benches, **Then** Review opens at its first item and the context line reads `Review · Nothing applied yet` with the queued total at its right; **given** Software Engineering is current in the Benches category zone, **Then** its counts appear in the category block and are not repeated below About.

---

### User Story 2 - Browse benches by category and read what a bench contains (Priority: P1)

On the Benches step the person first picks a category (Software Engineering, Science, System Administration; Electrical Engineering is listed as coming soon), sees that category's benches with a short tagline and install state, and reads in a small scrolling About panel what the focused bench is used for and what it contains, without leaving the screen.

**Why this priority**: Brett's core ask for the redesign ("the user should select the category of the bench … when the user selects a bench, we can explain what the bench is used for and what it contains"). Without it, benches remain bare names and a new user cannot choose between them.

**Independent Test**: With a catalog that carries categories and per-bench copy, open Benches, move between categories, enter the bench zone, queue a bench, and scroll a long About text; each step is observable in the rendered frame without any other story.

**Acceptance Scenarios**:

1. **Given** the catalog has loaded, **When** Benches is shown, **Then** a `CATEGORY` block lists the four categories in catalog order with counts such as `8 benches · 4 installed · 1 queued` (zero parts omitted, `bench` for one), and Electrical Engineering is dim with `coming soon`.
2. **Given** Software Engineering is current in the category zone, **When** the user presses ↓, **Then** Science becomes current, the bench panel lists gentecBench and simBench with no row marked focused, and About shows the Science summary and its bench names.
3. **Given** the category zone has focus, **When** the user presses ↑/↓ repeatedly, **Then** Electrical Engineering is never focused.
4. **Given** System Administration is current in the category zone, **When** the user presses Tab (or Shift+Tab, Space, or ↓ on the last category with benches), **Then** the bench zone has focus on that category's first bench, and Space has queued nothing; **when** the user instead presses Enter in the category zone, **Then** Review is shown.
5. **Given** the last bench of Software Engineering is focused, **When** the user presses ↓, **Then** focus does not move; **given** the first bench of Science is focused, **When** they press ↑, **Then** the category zone has focus with Science current.
6. **Given** rustBench is not installed and focused, **When** the user presses Space, **Then** rustBench is queued for install and its row shows `→ Install`.
7. **Given** javaBench is installed, queued for update and focused at 87 columns, **Then** its row shows `› [✓] ✓ javaBench`, its tagline, `Installed` and `→ Update`.
8. **Given** simBench is focused in the bench zone, **Then** About is titled `ABOUT SIMBENCH` and shows simBench's description, a `Use it for` line with its uses and a `Contains` line with its contents.
9. **Given** the About window shows lines 1–4 of 9, **When** the user presses PgDn, **Then** it shows 4–7 of 9 with `▲ more` and `▼ more`; **when** they then press `]` twice, **Then** it shows 6–9 of 9 with no `▼ more`; **when** they move to another bench, **Then** About shows the new bench from its first line.
10. **Given** the About text fits its window, **Then** no range, `more` marker or scroll hint is shown.

---

### User Story 3 - Jump to Workstation or Profiles and come back (Priority: P2)

While on any step, the person can press P to check or fix workstation readiness, or G to set up identities on Profiles, and press the same key to return exactly where they were. If background checks finish with a requirement unresolved, setup takes them to Workstation, and P brings them back. V runs the Vault action, R refreshes and Q quits from anywhere without losing their place or their queued changes.

**Why this priority**: The wizard works with ←/→ alone, but readiness problems and identity setup interrupt real sessions; losing focus or queued work on every interruption would make the wizard worse than 1.7. Acceptance suites also rely on these keys.

**Independent Test**: From each step (and both Benches zones) press P then P, and G then G, and check the step and focus are restored; simulate a check run that ends with Docker Down and check the jump, notice and return.

**Acceptance Scenarios**:

1. **Given** javaBench is focused in the Software Engineering bench zone, **When** the user presses P and then P again, **Then** Workstation is shown and then Benches again with javaBench focused in the bench zone.
2. **Given** the TUI has just opened on Workstation, **When** the user presses P, **Then** Benches is shown with the category zone on its first category.
3. **Given** the user moved ← from Benches with Science focused in the category zone, **When** they press P, **Then** Benches is shown with Science focused in the category zone.
4. **Given** Codex CLI is focused on Harness, **When** the user presses G and then G again, **Then** Profiles is shown and then Harness with Codex CLI focused; **given** they reached Profiles by → from Tools, **When** they press G, **Then** Tools is shown with the row focused before.
5. **Given** the user is in the Benches bench zone, **When** checks finish with Docker Down, **Then** Workstation is shown with the Docker row focused and "Resolve workstation requirements to continue."; **and when** they press P, **Then** they return to the same bench in the bench zone.
6. **Given** the Vault action is Connect and a bench is queued, **When** the user presses V on Benches and cancels the browser approval, **Then** Benches is shown with the same focus, the bench still queued and "Connection cancelled.".
7. **Given** checks are still running, **When** the user presses V, **Then** no Vault action runs and the current step says checks are still loading; **given** checks have finished, **When** the user presses V on Harness and the action reports that Vault needs attention, **Then** the notice appears on Harness below the rule, no wider than the frame.
8. **Given** any step other than Workstation, **Then** no `V` hint or `[V <Action>]` button is shown; **and** the Profiles step's hints include `G Back` and `Q Quit` on the same line.
9. **Given** javaBench is queued and focused in the bench zone, **When** the user presses R, **Then** statuses show Loading and reload, and javaBench stays queued and focused in the same category and zone.
10. **Given** checks are running on any step, **When** the user presses Q, **Then** setup prints "Setup cancelled.", exits with status 130 within two seconds and leaves no check process running.

---

### User Story 4 - Use setup on narrow and short terminals (Priority: P2)

The person may run setup in a 36-column side pane, a standard 80×24 window or a wide terminal. Every step fits: no line is wider than the terminal, no frame is taller than a known terminal height, lists scroll inside their panels keeping the focused row visible, and the banner and category block shrink before anything important is lost.

**Why this priority**: The 84-column main screen overflowing narrower terminals is one of the problems this change exists to fix, and the 24-row default must show the nav, the focused row and the whole footer. It is P2 because the step model (US1) delivers value at roomy sizes first.

**Independent Test**: Render every step at 36, 60 and 87 columns × 24 rows, 40 rows and unknown height (plus 37×24, 80×24, 88×39, 88×40 and 120 columns) with all 12 benches catalogued and every status present, and measure line widths and frame heights.

**Acceptance Scenarios**:

1. **Given** each step at 36, 60 and 87 terminal columns with long names and every status present, **Then** no line is wider than the terminal.
2. **Given** a 120-column terminal, **Then** the frame is 87 columns wide.
3. **Given** a focused Workstation row whose explanation reads "Checking workstation readiness…", **Then** that line's right border lines up with the panel's other borders.
4. **Given** each step at 80×24 and 37×24 with all 12 benches catalogued, **Then** each frame has at most 24 lines and shows the nav bar, the focused row and the whole footer.
5. **Given** Benches at 80×24, **Then** the category block is one line naming the current category and the bench panel shows at least three bench rows.
6. **Given** Benches at 88×40 with Software Engineering current, **Then** every category has its own row and About shows between two and eight lines.
7. **Given** a panel with more rows than fit, **When** focus moves below the visible rows, **Then** the panel scrolls to keep the focused row visible and shows how many rows are hidden above and below.
8. **Given** the terminal height cannot be read, **Then** every row of the step (every category, every bench of the current category, the whole About text) is rendered and no `N more` row appears.
9. **Given** a terminal shorter than the tight layout needs, **Then** the frame drops lines from its top and is still no taller than the terminal.
10. **Given** an 88×40 terminal, **Then** the four-row wordmark is drawn; **given** 88×39, **Then** the banner is a single `Opensoft` line. Both forms put the product name and OS on a separate row below the logo.
11. **Given** WSL 2, Docker, Tools and Vault are Up and the user is signed out, **Then** the Workstation strip shows `REQUIREMENTS · 3/3 ready`, `WSL 2 Up`, `Docker Up`, `Tools Up` and `Vault Up [V Connect]`; **given** a 36-column frame, **Then** the strip wraps only between items and `[V Connect]` appears whole on one line.
12. **Given** a 40-column frame on Benches, **Then** each bench row shows checkbox, status symbol, name and queued action, with no tagline and no status label.
13. **Given** the full nav does not fit the frame, **Then** the nav is one line `Step N of 6 · <Name>` with one progress mark per step, the first being the Workstation readiness mark, and no queued counts.
14. **Given** any step, **Then** the frame starts with the Opensoft banner, a blank row, a row with `openBenches v1.7` at the left and the detected OS at the right, and the nav bar between full-width rules above and below. The selected step has a bold, light-background highlight, including in compact navigation. It has no per-step title or description sentence. The rows under the lower rule are the step selector area (after one blank row on Workstation and roomy Benches). Roomy Benches also separates categories, the bench panel and About with blank rows.
15. **Given** an 80-column terminal with two benches, one agent and one tool queued, **Then** the nav is one line naming all six steps with `Benches 2`, `Harness 1` and `Tools 1` joined by ` ─ `; **given** a 60-column terminal, **Then** the nav is the compact `Step N of 6 · <Name>` form.
16. **Given** the Benches bench zone in a 36×24 terminal, **Then** the hints take at most two lines listing Space, D, `←→`, Enter and Q (P, R and PgUp/PgDn are not listed but still work), and the footer divider ends with `Changes: N`, without a duplicate bench context line.

---

### User Story 5 - Every locked bench is offered and looked up safely (Priority: P2)

goBench, rustBench and 365Bench are locked in the release but missing from the catalog, so setup never offers them. They become installable, every catalogued bench carries the category and copy the Benches step shows, simBench stops claiming tools its image does not contain, and every script that reads the catalog resolves a bench by its exact name, so a digit-leading name such as 365Bench can never make setup act on the workBenches root.

**Why this priority**: Three benches become available and the catalog becomes the accurate source for the About panel. The safe-lookup and fail-closed parts are a precondition for offering 365Bench and must land with or before the catalog additions; they ship in the same pull request as US1 and US2.

**Independent Test**: Run the catalog test (schema, limits, release-lock coverage, simBench wording), the digit-leading fixture test against each catalog consumer, the static check for name-built lookups, the fail-closed apply test, and the maintenance-script fixture tests; none needs the wizard UI.

**Acceptance Scenarios**:

1. **Given** the catalog test loads the catalog, **Then** it finds the four category ids with a non-empty label, an integer order and a non-empty summary, every bench's category is one of them, Electrical Engineering has no benches and the other three have at least one.
2. **Given** the catalog test checks every bench, **Then** each has a category, a tagline of at most 35 characters, a description, and non-empty `usedFor` and `contains` lists of single-line strings without control characters or characters wider or narrower than one column; **given** a tagline containing a fullwidth or zero-width character, **Then** the test fails and names that bench; **given** a 36-character tagline, **Then** the test fails and names that bench; **given** a `contains` item `Go 1.26 toolchain`, **Then** the test fails and names the bench and the token, while `Microsoft 365` in 365Bench's tagline is accepted.
3. **Given** the catalog and the release lock, **Then** every locked bench repository has a catalog entry with the same path and URL, including goBench, rustBench and 365Bench, and every catalogued bench is locked (no local-only phpBench or opsBench).
4. **Given** a private selection file requests `bench_365Bench` with action `install`, **Then** it is accepted and the selection tool's `benches` command prints `sysBenches/365Bench`; **and** the credential requirements list goBench, rustBench and 365Bench as TUI options.
5. **Given** simBench's tagline, description and contents, **Then** they mention OpenMM and ESM and do not mention AlphaFold or ESMFold.
6. **Given** a fixture catalog with `365Bench` at `sysBenches/365Bench`, **When** each catalog consumer (setup status and apply, workspace setup, project update, bench launcher, and the Python selection, component, release and checkout-removal tools) looks it up, **Then** each resolves `sysBenches/365Bench` and, where it reads them, its description and URL.
7. **Given** the repository's shell scripts, **When** the static check runs, **Then** no catalog lookup is built from a bench or infrastructure name.
8. **Given** a selected bench whose path lookup returns nothing during apply, **Then** that bench is reported as failed, and no git fetch, pull or clone runs in the workBenches root and the root `setup.sh` is not run for it.
9. **Given** a catalog whose benches carry category, tagline, uses, contents and AI keywords, **When** the catalog regeneration script rewrites it, **Then** the categories and every one of those fields are unchanged; **when** the new-bench script adds a bench under `devBenches/`, **Then** the new entry has category `software-engineering`; **given** a local clone that the release lock does not record, **When** the regeneration script runs, **Then** it skips that clone with a warning and leaves it out of the catalog.

---

### User Story 6 - Setup paints immediately and updates in place (Priority: P2)

As today, setup draws its first frame before any slow check runs, shows blinking Loading states while checks finish, and updates only the lines that change, so the new, richer frames never feel slower than 1.7.

**Why this priority**: These are 1.7 guarantees that existing tests assert; the wizard's height budgeting and About wrapping add work on every frame, so the guarantees must be re-proven under the new layout.

**Independent Test**: Start setup with a Docker probe that blocks, and with `jq`, `python3`, `docker` and `git` replaced by recording stubs; check the first frame and the recorded calls; then change one status and inspect the bytes written.

**Acceptance Scenarios**:

1. **Given** setup starts while the Docker probe blocks, **Then** a frame containing `Navigation:` and `Loading` is drawn before the probe returns, and it contains the blink attribute sequence.
2. **Given** every step is rendered with `jq`, `python3`, `docker` and `git` replaced by recording commands, **Then** no call is recorded.
3. **Given** Docker's status changes from Loading to Up, **Then** the output contains no clear-screen sequence and does not rewrite the banner/brand or OS separator.
4. **Given** the frame is drawn twice with no state change, **Then** the second draw writes nothing; **given** the terminal height changes between draws, **Then** the second draw clears the screen and repaints the whole frame.
5. **Given** a bench still shows Loading, **When** the user presses Space on it, **Then** nothing is queued.
6. **Given** Benches at 87×40 with all 12 benches catalogued and long About text, **When** ↑, ↓, Tab and PgDn are replayed repeatedly, **Then** the median time from key to completed redraw is at most 100 ms.

---

### User Story 7 - Bench details arrive late, partly, or not at all (Priority: P3)

Bench and category details reach the screen from the background checks. Until they arrive the Benches step says it is loading; if some details are missing, benches still appear in a sensible category; if none arrive, every bench is still listed and selectable.

**Why this priority**: The normal path (US2) covers a healthy catalog. Degraded behaviour matters for robustness and safety (untrusted text must not drive the terminal) but affects few sessions.

**Independent Test**: Publish catalogs with no metadata, categories but no bench details, no bench list, a bench without a category, an unknown category id, invalid names, a bench removed on refresh, and catalog or status text containing escape sequences, and check the Benches step for each.

**Acceptance Scenarios**:

1. **Given** the background checks finish reading the catalog, **Then** Benches shows categories, taglines and About text without the foreground having run any catalog or discovery tool.
2. **Given** a bench description contains an escape sequence such as `ESC [2J`, **Then** the TUI shows the text without the escape character and the screen is not cleared.
3. **Given** Benches is shown before the catalog and its details are published, **Then** the step shows `Loading benches…` and no bench can be queued.
4. **Given** a catalogued bench at `sysBenches/testBench` has no category, **Then** it is listed under System Administration; **given** a bench names an unknown category id, **Then** that category is listed after the known ones with a label derived from its id.
5. **Given** checks finish and the catalog was published without any details, **Then** every bench is listed under `Other benches` with About text `No details for this bench yet.`, **and** Space still queues a bench that is not installed.
6. **Given** pyBench is focused in the bench zone, **When** refreshed details arrive, **Then** pyBench stays focused in the Software Engineering bench zone and queued changes are unchanged.
7. **Given** a status detail from the background checks or the identities summary contains `ESC [2J`, **Then** the TUI shows the text without the escape character and the screen is not cleared.
8. **Given** checks finish without publishing a bench list, **Then** Benches says the bench list could not be loaded and that R retries, and no bench can be queued.
9. **Given** categories were published but no bench details, **Then** each bench is listed under the category its path gives, with About text `No details for this bench yet.`; **given** a bench names the unknown id `quantum-computing`, **Then** it is listed under `Quantum Computing` after the known categories.
10. **Given** goBench is focused and queued for install, **When** a refreshed catalog no longer lists goBench, **Then** the category zone has focus on Software Engineering and goBench's queued change is gone.

---

### Edge Cases

- **Checks finish unresolved while the user is elsewhere** (Review, a bench zone, Profiles): setup jumps to Workstation, focuses the first required item not Up, shows the notice, and P returns to the exact prior focus. This happens after every completed check run, including runs started by R, as in 1.7.
- **Enter on Review while blocked**: nothing is applied; a blocker line names the reason (checks running, or requirements unresolved); the TUI stays open with every queued change intact.
- **Enter twice with nothing queued**: the first Enter opens Review ("no changes selected"), the second exits 0 without applying or building anything.
- **More queued changes than Review has rows**: hidden counts are shown and ↑/↓ scroll until every item has been displayed; Review is read-only, so changes are unqueued on their own steps.
- **Two-digit queued counts or a narrow frame**: the full nav is 79 columns with three single-digit counts and fits an 80-column terminal; a two-digit count (80 columns) or a narrower frame collapses it to the compact form.
- **Category with no benches** (Electrical Engineering): listed dim as `coming soon`, never focusable.
- **Bench without a category / unknown category id / partial or no details**: placed by path (outside the bench roots: `Other benches`); unknown ids listed after known categories, by id, with a title-cased label; categories without bench details still place benches by path; one `Other benches` group when nothing at all arrived; `No details for this bench yet.` when description, uses and contents are all missing — always still selectable.
- **No bench list at all** (checks finish or cannot start without one): Benches says the bench list could not be loaded and that R retries; nothing can be queued.
- **Catalog or other outside text with control or escape characters, or invalid bench names or category ids**: control characters become spaces in every text the TUI did not write; invalid names and ids are ignored; the terminal is never driven by outside text.
- **Wide, combining, zero-width or bidi characters in bench copy**: the catalog test rejects them.
- **A bench disappears from a refreshed catalog**: focus, and any return target naming it, fall back to the category zone on the same category (or the first category with benches); a queued change for that bench is dropped, so Review shows only what can apply; queued changes for benches still catalogued are kept (NB-5).
- **Regeneration on a workstation with local-only clones** (phpBench, opsBench): skipped with a warning, so they never enter the catalog.
- **Digit-leading bench name** (365Bench): resolves like any other name in every consumer; an unresolved or out-of-tree path fails that bench and never targets the workBenches root.
- **Version numbers in bench copy**: the catalog test rejects them in taglines, `usedFor` and `contains` (standalone or dotted numbers, `v<N>`, `version-<N>`), except allow-listed product names such as Microsoft 365.
- **Terminal resized mid-session**: the next draw clears and repaints the whole frame at the new size.
- **Height unknown**: nothing is clipped and no `N more` row appears.
- **Terminal shorter than the tight layout or narrower than 36 columns**: lines are dropped from the top of the frame so it is never taller than the terminal; below 36 columns (under the supported 36×24 minimum) setup still runs with its 36-column frame and lines may wrap.
- **Keys piped without a terminal** (keystroke-driven tests): interactive and selection-only runs load the same bench details synchronously, so tests see the same categories; apply-plan and dependencies-plan runs never draw or load them.
- **V while checks run, or V cancelled**: no action runs while loading; a cancelled Connect returns to the same step and focus with "Connection cancelled." and every queued change kept.
- **Profiles action before the workstation is ready, or cancelled**: refused with a notice; a cancelled action reports "Profile action cancelled; saved profiles kept." and keeps queued changes.
- **Q during loading**: exits 130 within two seconds, stops pending checks and removes their private status files.
- **Keys with no meaning on a step** (D on Workstation, D in the category zone, Space on Review, Tab outside Benches): nothing happens and nothing is queued.

## Requirements *(mandatory)*

### Functional Requirements

#### Steps and navigation

- **FR-001**: Setup MUST present one step per screen in the fixed order Workstation, Benches, Harness, Tools, Profiles, Review, and MUST NOT show benches, agents and tools side by side. The step offering AI coding assistants and spec tools (formerly "AI assistants") MUST be named Harness wherever a step is named: nav bar, Review step names, footer, hints and documentation.
- **FR-002**: Setup MUST open on the Workstation step.
- **FR-003**: → MUST move to the next step and ← to the previous step, without wrapping at Workstation or Review; ↑/↓ MUST move only within the current step (skipping separators), stopping at its first and last rows without wrapping (as in 1.7) except where the Benches zones define otherwise (FR-042, FR-043), and MUST NOT change step.
- **FR-004**: Arriving at a step by ← or → MUST focus that step's first row; arriving on Benches MUST focus the category zone on the first category that has benches. The focused row MUST be marked `›` on every step that has rows (on Benches only in the bench zone, FR-044), as in the design mockups.
- **FR-005**: A nav bar MUST show every step in order, marking steps before the current one `✓`, the current step with a highlighted `●` and later steps `○`, each followed by its number of queued changes when that number is not zero; Profiles, whose rows run actions immediately, never shows a count.
- **FR-006**: On every step, the nav bar's Workstation item MUST show readiness instead of a step mark: green `✓` when every required item is Up, yellow `⚠` when one is not, and a blinking `…` while checks run. When Workstation is the current step, its item takes the current-step highlight but keeps the readiness mark.
- **FR-007**: The nav bar MUST join the step names with short ` ─ ` connectors and MUST show this full form whenever it fits the frame; with three single-digit counts it is 79 columns including the current step's highlight, so it fits an 80-column terminal (79-column frame). Only when the full nav does not fit — for example at 60 columns, or at 80 columns with a two-digit count — MUST it collapse to one line, `Step N of 6 · <Name>`, with one progress mark per step, the first being the readiness mark, and no queued counts (the footer keeps the total).

#### Enter, Review and Apply

- **FR-008**: Enter MUST open the focused Profiles action on Profiles, apply the reviewed plan on Review, and open Review from every other step including Workstation. Selection keys MUST never apply changes.
- **FR-009**: Review MUST list every queued change under INSTALL, UPDATE and REMOVE groups, in step order, each item with the name of the step it belongs to; the REMOVE group MUST note that projects and credentials are kept; and Review MUST state "Nothing has changed yet. Enter applies these changes."
- **FR-010**: Review MUST show a yellow warning when Shell setup (replaces shell settings) or Org workspace (may create a GitHub repository) is queued.
- **FR-011**: With nothing queued, Review MUST state that no changes are selected and that Enter finishes without changes.
- **FR-012**: When the queued changes are taller than Review's rows, Review MUST show how many items are hidden above or below and ↑/↓ MUST scroll the list so every queued change can be displayed. Reached by Enter or by ←/→, Review MUST open at its first item; a P or G return MUST restore the remembered position, like any other focus. Review MUST be read-only: no key on Review queues or unqueues a change; that is done on the item's own step.
- **FR-013**: Review Apply MUST wait until checks finish. It MUST retain required-readiness gates for ordinary component work, while allowing explicitly selected missing prerequisites to be installed first and service-only removal plans to proceed without requiring the removed services Up. No service removal runs before successful component work; unsupported or unowned removals fail preflight before mutation.
- **FR-014**: Enter on Review with nothing queued MUST finish without changes under the same readiness gate as FR-013, as the previous TUI's empty Enter did: it MUST exit with status 0 without applying anything or building any image, and in a selection-only run it MUST first write a selection file with no components.
- **FR-015**: Existing mode names, schemaVersion 1 and old component payloads MUST remain compatible. The accepted setup-workstation-lifecycle extension adds wsl/docker/setup_tools/vault keys with install/uninstall actions and prerequisite-first/removal-last execution. Selection-only remains read-only and writes private JSON atomically without Python or following symlinks. Noninteractive apply/dependency modes draw no wizard frame.

#### Step content

- **FR-016**: Workstation MUST show one blank row after the navigation divider, its readiness heading and blank row, and one `Containers` panel listing WSL 2 on WSL, Docker, Tools and optional Vault in the existing service order. Rows MUST show selection boxes and installation/runtime status without an inline explanation. The title MUST show required readiness only; Vault MUST remain optional. Below the panel, an About panel MUST describe the focused service and its current check detail, using the shared About wrapping, paging, focus-reset and same-service refresh-clamping rules. With known height it uses two to eight spare content rows; with unknown height it shows all text. Roomy layouts separate Containers and About with one blank row. G Profiles MUST be advertised in the full Workstation footer. Account rows remain only on Profiles.
- **FR-017**: On Workstation, Space MUST queue/unqueue install/start, D MUST queue/unqueue uninstall for installed entries, and Enter MUST open Review. Loading or unverifiable rows MUST queue nothing. All four service entries are selectable under the lifecycle extension; WSL and Docker Desktop teardown require manual host steps and are not falsely reported complete.
- **FR-018**: Harness and Tools MUST retain their existing component IDs, install/apply order and selection rules. The Harness list MUST be titled Harnesses and browse CLI/TUI Agent Harnesses, GUI Agent Harnesses, IDE/Editor Extensions and Workflow & Specification Tools. Each step MUST show About for the selected category or item, using shared wrapping/paging/reset/clamping rules. Tools MUST browse IDEs & Editors, Terminals & Terminal Workspaces, Networking and Workstation setup categories, using the Benches category/list zones and keys. Reference entries are manual-only and cannot be queued. Categories show only their tools; category focus shows category About. Global tool indexes and queue keys MUST remain unchanged; loading/needs-check items remain unselectable, and Shell setup/Org workspace remain configuration-only.
- **FR-019**: The Profiles step MUST show the identities summary line, the rows Personal & companies, Workstation account and AI accounts, and an About panel explaining the focused row from fixed text, sized from spare rows (two to eight lines when the height is known) and scrolled with the keys, markers and reset rule of FR-046.
- **FR-020**: Enter or Space on a Profiles row MUST open that row's existing Profiles action; the action MUST be refused with a notice until every required workstation item is Up; returning from it MUST keep every queued change and show its result notice ("Profile action completed.", "Profile action cancelled; saved profiles kept." or, when it fails, "Profile action needs attention. Open it to retry.", as in 1.7).
- **FR-021**: Every step MUST end with a rule and that step's key hints. Except on Benches, a context line between them MUST show the focused item as `<Name> · <State>`, followed by `→ <action>` when one is queued; Review shows `Review · Nothing applied yet` and a Profiles row its name alone. Benches MUST omit the duplicate category/bench context line and put the queued total at the right of its footer rule instead. On other steps the total remains at the right of the context line. The total MUST read `Changes selected: N` at widths of 60 columns or more, and `Changes: N` below 60 columns; context text too long for the remaining width is cut with `…`.
- **FR-022**: Key hints MUST begin with `Navigation:` on every step (as in 1.7; acceptance suites wait on it), MUST be specific to the step, MUST advertise V only on Workstation, and on Profiles MUST include `G Back` and `Q Quit` on the same line. Below 60 columns the hints MUST take at most two lines, listing the step's own keys (on Profiles, `G Back`) plus `←→`, `Enter` and `Q`; P, G, R, V and PgUp/PgDn MUST keep working on every step but are listed only at 60 columns or more. At 60 columns or more the step's full hint list MUST be shown, wrapped over as many lines as it needs (two at 80 columns or more), within the height bounds of SC-002.

#### Jumps and global keys

- **FR-023**: P from any other step MUST show Workstation with its first row focused and remember that step and its exact focus (row; on Benches also zone, category and bench). P on Workstation MUST return to the remembered step and focus, or to the Benches category zone on the first category that has benches when none is remembered. Moving ← from Benches to Workstation and the readiness jump (FR-028) MUST remember focus the same way.
- **FR-024**: G from any other step MUST show Profiles with its first row focused and remember that step and its exact focus. G on Profiles MUST return to the step and focus remembered when Profiles was entered by G, by → from Tools or by ← from Review, or to the Benches category zone on the first category that has benches when none is remembered.
- **FR-025**: V MUST run the Vault action for its current state (Install, Start, Connect or Sign out) from every step without changing the step, the focus or the queued changes, and MUST show the result notice on the step where it was pressed; while checks run, V MUST run nothing and the step MUST say checks are still loading.
- **FR-026**: R MUST re-run readiness and component checks while keeping the current step, the focus (including the Benches zone, category and focused bench) and every queued change, except as FR-051 says for a bench that leaves the catalog.
- **FR-027**: Q MUST quit from every step, including while checks run: it MUST stop pending checks and remove their private status files, apply nothing, print "Setup cancelled." and exit with status 130 within two seconds.
- **FR-028**: When a check run finishes with a required workstation item not Up, setup MUST show the Workstation step, remember the previous step and focus for P, focus the first required item that is not Up, and show "Resolve workstation requirements to continue." This applies after every completed check run, including runs started by R. When Workstation is already shown, the remembered P target is kept, as in 1.7.

#### Frame layout

- **FR-029**: Every frame MUST begin with the Opensoft banner, one blank row, and a product/OS row showing `openBenches v1.7` at the left and the detected OS at the right. The nav bar MUST follow between full-width separator rules above and below. The selected step MUST use a bold, light-background highlight in full and compact navigation. There MUST be no per-step title line or step description line. The display brand does not change the repository VERSION or other product identifiers. This header layout reflects Brett's 2026-10-24 review.
- **FR-030**: The rows under the rule MUST be the step's selector area: the requirements strip after one blank row on Workstation only, the `CATEGORY` block on Benches, and on Profiles one line summarizing the cached personal and company identities, cut with `…` when wider than the frame. In the roomy layout, one blank row MUST separate the rule from the Benches category block; the tight layout omits that gap. Harness and Tools MUST start with their category blocks and Review with its instruction line.
- **FR-031**: Workstation MUST show REQUIREMENTS · R/N ready, or REQUIREMENTS · Loading… while checks run, followed by one blank row. Required readiness excludes optional Vault. Per-service information MUST appear in Containers with left selection boxes, right installation/runtime status and queued action where width permits; healthy running entries read Installed · Up. No Check button or duplicate service-information strip is shown.
- **FR-032**: A notice produced by the Vault action, a Profiles action, a blocked Apply or the readiness check MUST be shown on the current step, after its selector area, cut to the frame width. As in 1.7, a notice stays, on whichever step is current, until a later notice replaces it, a Workstation service action (V included) starts, or R clears it.
- **FR-033**: For terminals at least 36 columns wide, no rendered line MUST be wider than the terminal; the frame MUST be one column narrower than the terminal, clamped to 36–87 columns (as in 1.7), so it is never wider than 87 columns; and alignment MUST count characters, not bytes, so lines with multibyte text stay aligned. The minimum supported terminal size MUST be 36 columns by 24 rows; on narrower terminals setup MUST still run, drawing its 36-column frame, and lines may wrap.
- **FR-034**: When the terminal height is known, the frame MUST never be taller than the terminal. A tight layout — one blank row below the one-line banner, one blank row after the Workstation navigation divider, and no other blank spacer lines — MUST apply at 24 rows or fewer and whenever the roomy layout would not fit.
- **FR-035**: Lists that do not fit MUST scroll inside their panels with `▲ N more` and `▼ N more` rows, keeping the focused row visible.
- **FR-036**: When the terminal height is unknown, nothing MUST be clipped and no `N more` row shown; when the terminal is shorter than the tight layout needs, the frame MUST drop lines from its top rather than exceed the terminal height.
- **FR-037**: The four-row OpenSoft wordmark MUST be drawn only in the roomy layout (FR-034), when the frame is at least 43 columns wide and the height is unknown or at least 40 rows; otherwise a one-line `Opensoft` wordmark MUST be drawn. The product/OS row remains separate in both forms.
- **FR-038**: The first frame MUST be drawn before any Docker, catalog-parsing, Python, Git or network check runs, and rendering any step MUST read only in-memory state, never running a discovery command.
- **FR-039**: After the first paint, a status update or key press MUST rewrite only the lines that changed, and an unchanged frame MUST write nothing; the screen MUST be cleared only on the first paint, after an interactive helper returns, or when the terminal width or height changes.
- **FR-040**: An item whose state is not yet known MUST show `Loading` in the blinking loading style and MUST NOT be selectable until its state is known; an item whose check ends without a state is treated as needing a check (not selectable, FR-018), as in 1.7.
- **FR-060**: The median time from a key press to the completed redraw MUST be at most 100 ms, measured over repeated key-driven redraws of any step at 87×40 on a developer workstation (the timing test uses the Benches step, the most expensive frame).

#### Benches step

- **FR-041**: The Benches step MUST list every catalog category in catalog order (by `order`, then id) under a `CATEGORY` label with a `Tab ⇄ benches` hint, marking the current category `●` and the others `○`, each followed by `N benches · I installed · Q queued` with zero parts omitted and `bench` for one, where a bench counts as installed when Space would queue an update rather than an install (status `installed`, `needs creds` or `image only`, as 1.7 treats them); a category with no benches MUST be shown dim as `coming soon` and MUST NOT be focusable.
- **FR-042**: In the category zone, ↑/↓ MUST change the current category among those that have benches and show its benches without highlighting a bench row; Tab, Shift+Tab, Space, or ↓ on the last focusable category MUST move to the bench zone on that category's first bench; Space MUST NOT queue anything there and D MUST do nothing.
- **FR-043**: In the bench zone, ↑/↓ MUST move only within the current category's benches; ↑ on the first bench, Tab or Shift+Tab MUST return to the category zone with the same category current; Space and D MUST queue and unqueue changes by the same rules as before this change.
- **FR-044**: The bench panel MUST be titled with the current category and `I of N installed` (installed as in FR-041; `Loading…` while any of its statuses is unknown) and MUST show one row per bench, in catalog-name order (code-point order of the bench names, as 1.7 lists them, so 365Bench precedes cloudBench), with checkbox, status symbol, name, tagline, status label and queued action. Below 70 columns it MUST drop the tagline and below 50 columns the status label; the focused row MUST be marked `›` only in the bench zone; when rows do not fit, the panel MUST show `▲ N more` / `▼ N more` and keep the focused row visible. In roomy layouts, one blank row MUST separate the category block from this panel and another MUST separate this panel from About. Tight layouts omit those two gaps to preserve the bench/About budget.
- **FR-045**: The About panel MUST describe the current focus: in the bench zone, titled `ABOUT <BENCH>`, the bench's description, then a `Use it for` list and a `Contains` list; in the category zone, titled `ABOUT <CATEGORY>`, the category summary and the names of its benches.
- **FR-046**: When the About text is longer than its window, the panel MUST show `a–b of n` in its top border, `▼ more` on the last visible line while text remains below, `▲ more` on the first visible line once scrolled, and a `PgUp/PgDn scroll` hint in its bottom border; PgUp/PgDn and `[`/`]` MUST scroll by the window height less one line, clamped to the text; the offset MUST return to the first line whenever the zone, category or focused bench changes, and MUST be kept, clamped to the new text, when the same bench's details are refreshed; text that fits MUST show no range, marker or hint.
- **FR-047**: With a known height, the Benches step MUST give rows first to the category block, then to at least three bench rows (or all when fewer), then to between two and eight About lines; rows left over MUST go first to more bench rows, up to every bench of the current category, and then to About, up to eight lines; when the minimums do not fit, the category block MUST collapse to one line naming the current category; with an unknown height nothing MUST be clipped.
- **FR-048**: Bench and category details MUST be published by the background status checks beside the bench list, each published file complete before it becomes visible; the foreground MUST read them without running external tools, MUST ignore bench names and category ids that fail validation, and MUST replace control characters (U+0000–U+001F and U+007F–U+009F, including ESC and tab) with spaces. The same replacement MUST apply to every other text the TUI shows but did not write itself: status details from the background checks, the identities summary and the results of interactive helpers.
- **FR-049**: Until the bench list and its details have arrived, or checks have finished without the details (FR-050), the Benches step MUST show `Loading benches…` and no bench MUST be queueable. When checks finish, or cannot start, without publishing a bench list, the step MUST instead say that the bench list could not be loaded and that R retries, and no bench MUST be queueable.
- **FR-050**: A bench without a category MUST be placed by its path (`devBenches/` → Software Engineering, `bioBenches/` → Science, `sysBenches/` → System Administration, any other path → `Other benches`); an unknown category id MUST be listed after the known categories, ordered by id, with a label made by title-casing the id's hyphen-separated words (`quantum-computing` → `Quantum Computing`); when categories arrive without per-bench details, benches MUST still be placed by path into them. A bench MUST show the detail fields that exist, and About MUST read `No details for this bench yet.` when its description, uses and contents are all missing. When checks finish without any details (neither categories nor bench details), every catalogued bench MUST be listed in one `Other benches` group with that About text; in the category zone, `Other benches` About MUST list its bench names. Every such bench MUST remain selectable.
- **FR-051**: When the catalog or its details arrive or are refreshed, the Benches step MUST keep the focused bench (matched by name), the zone, the current category and every queued change; a bench remembered by the P or G return target is kept by name the same way. When the focused or a remembered bench is no longer catalogued, that focus MUST fall back to the category zone on the same category (or the first category that has benches), and the bench's queued change MUST be dropped, so Review lists only changes that can apply. When the bench list first arrives while Benches shows `Loading benches…`, focus MUST go to the category zone on the first category that has benches, as on arrival (FR-004).

#### Bench catalog

- **FR-052**: The bench catalog MUST define the categories `software-engineering`, `science`, `system-administration` and `electrical-engineering`, each with a label, an integer order and a one-line summary; every bench's category MUST name a defined id; Electrical Engineering MUST have no benches and the other three at least one each.
- **FR-053**: Every catalogued bench MUST have a category, a tagline of at most 35 characters, a non-empty description, and non-empty `usedFor` and `contains` lists of single-line strings, none containing control characters (as defined in FR-048); a violation MUST fail the catalog test and name the bench. These fields, and each category's label and summary, MUST contain only single-column printable characters: the catalog test MUST also reject East Asian wide or fullwidth characters, combining marks, and zero-width or bidi formatting characters, naming the bench or category. Taglines, `usedFor` and `contains` MUST NOT name version numbers: the catalog test MUST reject a version-like token — a standalone number, dotted or not, or a number prefixed by `v` or `version-` — except numbers on an allow-list of product names (`Microsoft 365`, `Dynamics 365`), naming the bench and the token. A number is standalone when it is not joined to a letter, so names such as `ARM64`, `MMseqs2`, `py3Dmol` and `m365` in the draft are accepted. The copy for all 12 benches MUST start from the evidence-based draft (`bench-copy-draft.json`, versions removed), and Brett MUST approve it, or have his edits applied, in the running TUI before the pull request merges; that approval is a recorded merge gate (who, date and commit, recorded in this feature).
- **FR-054**: The catalog MUST contain an entry, with matching path and URL, for every bench repository recorded in the release lock, including goBench (`devBenches/goBench`), rustBench (`devBenches/rustBench`) and 365Bench (`sysBenches/365Bench`); each entry MUST be offered by setup, accepted in selection files, and listed as a TUI option in the credential requirements. The catalog MUST NOT contain a bench the release lock does not record, such as the local-only phpBench and opsBench clones.
- **FR-055**: Catalog text MUST describe only what a bench's image provides; simBench MUST be described as molecular simulation and protein structure work with OpenMM and ESM on CPU PyTorch, and its tagline, description and contents MUST NOT claim bundled AlphaFold or ESMFold models or weights.
- **FR-056**: Every script that looks a bench (or infrastructure entry) up in the catalog MUST pass the name as data and index by it, never building the lookup expression from the name text, so names beginning with a digit resolve correctly in every consumer (setup status and apply, workspace setup, project update, bench launcher).
- **FR-057**: An automated check MUST fail when any shell script builds a bench or infrastructure catalog lookup from a variable, and a behaviour test with a digit-leading fixture bench MUST prove that each consumer resolves the right directory: the four shell consumers of FR-056 and the four Python consumers (`setup_selection.py`, `setup-components.py`, `release-workbenches.py`, `remove-bench-checkout.py`).
- **FR-058**: When a selected bench's catalog path cannot be resolved to a relative path that starts with `devBenches/`, `sysBenches/` or `bioBenches/` and has no `..` segment (the rule the selection tool already applies), setup MUST report that bench as failed, like any other failed component, MUST NOT run git, a clone or a setup script for it, and MUST never use the workBenches root as a bench directory.
- **FR-059**: The catalog regeneration and new-bench scripts MUST keep the top-level categories and every existing per-bench field when they rewrite the catalog, and a bench they add MUST receive a category derived from its path. The regeneration script MUST skip, with a warning, any bench the release lock does not record, so local-only clones never enter the catalog; the new-bench script still adds its entry, and the bench-creation documentation MUST say that a new bench needs a release-lock entry and its copy (tagline, description, uses, contents) before the catalog test passes.

### Key Entities

- **Wizard step**: one of Workstation, Benches, Harness, Tools, Profiles, Review; has a fixed position, a selector area, its own key hints, and a count of queued changes (Workstation shows readiness instead).
- **Queued change**: a component and an action (install, update or remove; Shell setup and Org workspace are configured through an install action and listed under INSTALL) that belongs to one step; nothing is applied until Enter on Review.
- **Workstation readiness**: the required services (WSL 2 on WSL, Docker, Tools) and optional Vault, each Loading, Up or not Up with an `[Action]`; ready when every required service is Up. Gates Apply and Profiles actions.
- **Focus**: the current step and row, plus on Benches the zone (category or bench), the current category and the About scroll offset.
- **Return target**: a remembered step and focus, one for P (Workstation) and one for G (Profiles); defaults to the Benches category zone on the first category that has benches.
- **Bench category**: id, label, order and one-line summary; holds zero or more benches; "coming soon" when empty.
- **Catalogued bench**: name, path, URL, description, category, tagline (≤ 35 characters), uses (`usedFor`), contents (`contains`), plus existing AI keywords and project scripts.
- **Release lock**: the bench repositories pinned for a release; the catalog must cover every one of them.
- **Selection file**: `schemaVersion` 1 with `components` of `key` and `action`; written by selection-only runs and read by apply-plan runs; unchanged by this feature.

### OpenSpec Traceability

Every OpenSpec requirement in the change maps to at least one FR, and every FR derives from one of these requirements (45/45 covered; no FR without an OpenSpec source). FR-053's copy-approval merge gate also traces to OpenSpec `tasks.md` 7.2 and design D18.

| OpenSpec capability | Requirement | FRs |
|---|---|---|
| setup-wizard-flow | Guided wizard steps | FR-001, FR-002 |
| setup-wizard-flow | Step navigation | FR-003, FR-004 |
| setup-wizard-flow | Top nav bar | FR-005, FR-006, FR-007 |
| setup-wizard-flow | Enter opens Review | FR-008 |
| setup-wizard-flow | Review lists every queued change | FR-009, FR-010, FR-011, FR-012 |
| setup-wizard-flow | Apply from Review | FR-013, FR-014 |
| setup-wizard-flow | Workstation jump | FR-023 |
| setup-wizard-flow | Profiles jump | FR-024 |
| setup-wizard-flow | Vault action from any step | FR-025, FR-022 |
| setup-wizard-flow | Refresh keeps state | FR-026 |
| setup-wizard-flow | Quit from any step | FR-027 |
| setup-wizard-flow | Readiness jump | FR-028 |
| setup-wizard-flow | Workstation step | FR-016, FR-017 |
| setup-wizard-flow | Profiles step | FR-019, FR-020 |
| setup-wizard-flow | Harness and Tools steps | FR-018 |
| setup-wizard-flow | Footer context and hints | FR-021, FR-022 |
| setup-wizard-flow | Setup contracts unchanged | FR-015 |
| setup-wizard-layout | Frame head | FR-029 |
| setup-wizard-layout | Step selector area | FR-030 |
| setup-wizard-layout | Requirements strip | FR-031 |
| setup-wizard-layout | Notices on the current step | FR-032 |
| setup-wizard-layout | Width bounds | FR-033 |
| setup-wizard-layout | Height bounds | FR-034, FR-035, FR-036 |
| setup-wizard-layout | Banner collapse | FR-037 |
| setup-wizard-layout | First paint without discovery | FR-038 |
| setup-wizard-layout | Partial redraw | FR-039 |
| setup-wizard-layout | Key response time | FR-060 |
| setup-wizard-layout | Loading indicators | FR-040 |
| setup-bench-browser | Category block | FR-041 |
| setup-bench-browser | Category zone | FR-042 |
| setup-bench-browser | Bench zone | FR-043 |
| setup-bench-browser | Bench panel | FR-044 |
| setup-bench-browser | About panel content | FR-045 |
| setup-bench-browser | About scrolling | FR-046 |
| setup-bench-browser | Height-aware Benches layout | FR-047 |
| setup-bench-browser | Metadata delivery without discovery | FR-048, FR-049 |
| setup-bench-browser | Degraded metadata | FR-050 |
| setup-bench-browser | Focus survives catalog updates | FR-051 |
| bench-catalog | Bench categories | FR-052 |
| bench-catalog | Bench presentation fields | FR-053 |
| bench-catalog | Complete catalog | FR-054 |
| bench-catalog | Accurate bench descriptions | FR-055 |
| bench-catalog | Name-safe catalog lookups | FR-056, FR-057 |
| bench-catalog | Unresolved bench paths fail closed | FR-058 |
| bench-catalog | Maintenance scripts preserve metadata | FR-059 |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In keystroke tests covering every step and both Benches zones, 100% of queued changes appear on Review before Apply, and no key other than Enter on Review (or a Workstation/Profiles row action) installs, updates, removes or writes a selection file.
- **SC-002**: Across the render matrix — all six steps at 36, 60 and 87 columns × 24 rows, 40 rows and unknown height, plus 37×24 and 80×24 with all 12 benches catalogued — zero lines are wider than the terminal, zero frames are taller than a known height, and every 24-row frame shows the nav bar, the focused row and the whole footer; at 80 columns the full nav naming all six steps fits with three single-digit counts.
- **SC-003**: 12 of 12 benches in the release lock are offered by setup, each under a category with a tagline and About text, and each is accepted in a selection file; 0 catalogued benches lie outside the release lock.
- **SC-004**: Zero shell catalog lookups are built from a bench or infrastructure name (static check), 8 of 8 catalog consumers (four shell, four Python) resolve a digit-leading fixture bench to its own directory, and an unresolved bench path causes zero git, clone or setup-script runs in the workBenches root.
- **SC-005**: With a Docker probe that blocks, the first frame (containing `Navigation:` and `Loading`) is visible before the probe returns, and rendering any step invokes zero discovery tools.
- **SC-006**: The median time from a key press to the completed redraw is at most 100 ms (repeated key-driven redraws at 87×40 on a developer workstation), so navigation feels immediate despite height budgeting and About wrapping.
- **SC-007**: Q exits with status 130 within two seconds from every step, including while checks run, leaving no check process running.
- **SC-008**: P and G round trips restore exactly the same step and focus (row, zone, category, bench) from 100% of tested starting positions; R and catalog refreshes keep 100% of queued changes for benches still catalogued and the focused bench when it is still catalogued.
- **SC-009**: For the same queued changes, selection files written by the wizard contain exactly the components the 1.7 TUI writes; apply-plan and dependencies-plan runs draw zero wizard frames.
- **SC-010**: Every outcome asserted by the existing setup suites (workstation and WSL workstation acceptance, component lifecycle, tools runtime, async loading, requirements, profiles, guided flow, cancel) still holds with updated keystrokes — zero asserted outcomes removed — and the real-host acceptance suites pass on the candidate commit on a native and a WSL workstation, including a TUI install of 365Bench on a disposable workstation.
- **SC-011**: With bench details missing, partial or hostile (escape sequences, invalid names), 100% of catalogued benches remain listed and selectable, and the terminal is never cleared or restyled by catalog text or by any other text the TUI did not write (status details, identities summary, helper results).
- **SC-012**: A person setting up a fresh workstation can go from the first screen to a completed apply using only the on-screen nav and hints, with every queued change visible on Review first (Brett confirms on a real host during release QA, recorded with the real-host results in this feature).
- **SC-013**: Bench copy contains zero version-like tokens in taglines, `usedFor` and `contains`, and Brett's approval of the copy for all 12 benches, given in the running TUI, is recorded in this feature (who, date and commit) before the pull request merges.

## Assumptions

- **Release target**: workBenches 1.7 (`release/1.7.0`, `VERSION` `1.7.0-dev.1`); if 1.7 freezes first the same pull request retargets to 1.8 with unchanged requirements. 1.6 is frozen and out of scope.
- **Users and terminals**: people running `./setup.sh` interactively in Windows Terminal, the VS Code terminal or Linux terminals with UTF-8; only single-column glyphs are used, and Windows Terminal and the VS Code terminal are checked by hand during release QA, with the result recorded with the real-host acceptance results in this feature (OpenSpec `tasks.md` 5.3).
- **Approved scope** is "look only, same behavior" plus three deliberate changes: Enter → Review → Apply, category and About browsing on Benches, and the catalog additions needed to offer every locked bench.
- **Unchanged**: setup modes and selection-file JSON, apply and plan semantics, Docker/Tools/Vault service behaviour, Profiles internals, immediate first paint, partial redraw, blinking Loading, the status polling cadence, Q exiting 130, and interrupt handling (Ctrl+C exits 130, termination 143).
- **No data migration**: catalog fields are additive; Python consumers already index by name and ignore unknown fields (the digit-leading fixture test of FR-057 proves the name handling); existing selection files stay valid.
- **The readiness jump** keeps 1.7's timing: it fires whenever a check run finishes unresolved, including runs started by R.
- **Key-response budget**: 100 ms per key press at 87×40, measured on a developer workstation; the timing test runs locally rather than as a hard CI gate, where shared runners make timings noisy.
- **Bench copy** is the evidence-based draft for 12 benches (`bench-copy-draft.json` beside this spec, version numbers removed); Brett approves or edits it in the running TUI before merge.
- **Naming**: the step formerly called AI assistants is Harness; the Profiles row "AI accounts" keeps its name because it is about accounts, not the step.
- **The prototype** branch `prototype/tui-guided-wizard` (built on `origin/main` `9441dc8`, before Profiles) is a behaviour and test-impact reference only, not code to port.
- **Rollback** is a revert; benches installed from the new catalog entries keep their checkouts and images.
- **Out of scope**: the disabled OpenTUI app; Profiles internals and manager screens; new Electrical Engineering, chemistry or physics benches; automated installers for new Harness/Tools reference entries; Science sub-groups until chemistry or physics benches exist; cataloguing local-only benches such as phpBench and opsBench.
- **Dependencies**: the background status checks running inside Tools; the release lock as the source of truth for which benches exist; the credential requirements catalog; the existing acceptance suites and real-host QA workstations.


## Accepted refinement 029-A06 (2026-10-23)

FR-018 is extended to give Harness the Benches category/list pattern: TUI AI Tools, GUI AI Tools, IDE extensions, Workflow. About follows category or item focus, panel title is Harnesses with its category, and only members of that category appear. Tools Editors becomes Editors & IDEs. See amendment 029-A06 for the exact initial catalog. New reference entries are manual-only, clearly lack action checkboxes, show setup sources and optional read-only presence evidence, and never enter Review or plans. Existing managed IDs/order/actions remain stable. Presence never implies login. Both steps preserve category/zone/item/list/About state through P/G and refresh, and use builtins-only responsive rendering.


## Accepted product catalog extension (2026-10-23)

OpenSpec setup-agent-tool-catalog extends FR-018 display/catalog scope using Brett's supplied taxonomy and product inventory. Harness contains GUI Agent Harnesses, CLI/TUI Agent Harnesses, IDE/Editor Extensions, Workflow & Specification Tools. Tools contains IDEs & Editors, Terminals & Terminal Workspaces, Networking and Workstation setup. CLI groups distinguish ownership/region from provider policy. Structured About metadata qualifies user-provided vs documented capabilities, with interoperability fields rather than a category. All new entries remain manual references; managed IDs/plans remain unchanged. F optionally selects a CLI ownership group without altering existing Tab-to-list behavior. P/G/refresh preserve group, category, zone, item and scroll state.


## Accepted faceted-filter extension (2026-10-23)

FR-018 is extended by setup-harness-filters: replace the single F group picker with independent Frontier/Region/Access/Native/Via/Group facets, OR within each dimension and AND across active dimensions. Frontier means an editable curated lab set; native and integrated capabilities are separate and provenance-bearing. Unknown is explicit. Preserve queues and exact P/G/refresh state, support clear/empty results safely, and retain responsive builtins-only rendering and unchanged install plans.

## Four-column Harness filters

Brett's 2026-10-23 follow-up supersedes T039K's six-row checkbox UI: expose only Type, Region, Access and Native as single-choice columns above live results. New sessions default Type to Frontier and others to All; C clears all to All. In filter focus Left/Right or Tab chooses a column and Up/Down cycles values immediately; F returns to results. Type Open/Closed records supported model weight availability, never the harness source license. Preserve qualified native/routed evidence in About, queue safety, empty guards and navigation state. See `openspec/changes/setup-harness-filters/design.md` and T039L.
