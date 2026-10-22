# Spec Delta: setup-wizard-flow

## Purpose

Defines the interactive setup TUI as a guided wizard: its steps and their order,
the top nav bar, step and jump keys, the Enter→Review→Apply flow, the content of
the Workstation, Harness, Tools, Profiles and Review steps, readiness
handling, and the setup contracts the wizard must leave unchanged.

## ADDED Requirements

### Requirement: Guided wizard steps
The interactive setup TUI SHALL present one step per screen in this fixed order: Workstation, Benches, Harness, Tools, Profiles, Review. The step that offers AI coding assistants and spec tools SHALL be named Harness wherever the step is named (nav bar, Review step names, footer, hints and documentation). The TUI SHALL open on the Workstation step and SHALL NOT show benches, agents and tools side by side.

#### Scenario: Startup opens on Workstation
- **WHEN** `./setup.sh` starts the interactive TUI on a terminal
- **THEN** the first frame shows the Workstation step
- **AND** the nav bar lists Workstation, Benches, Harness, Tools, Profiles and Review in that order

#### Scenario: One step per screen
- **WHEN** any step is displayed
- **THEN** the frame shows only that step's content, with no three-column component screen

### Requirement: Step navigation
→ SHALL move to the next step and ← to the previous step without wrapping, and ↑/↓ SHALL move only within the current step, stopping at its first and last rows without wrapping, as in 1.7 (the Benches zones define their own moves between zones). Arriving at a step by ← or → SHALL focus that step's first row; on Benches it SHALL focus the category zone on the first category that has benches. The focused row SHALL be marked `›` on every step that has rows (on Benches only in the bench zone).

#### Scenario: Next and previous step
- **WHEN** the Tools step is shown and the user presses →
- **THEN** the Profiles step is shown
- **AND** pressing ← shows the Tools step again with its first row focused

#### Scenario: No wrap at either end
- **WHEN** the user presses ← on Workstation or → on Review
- **THEN** the step does not change

#### Scenario: Vertical keys stay within the step
- **WHEN** the user presses ↓ repeatedly on Harness
- **THEN** focus moves through its rows, skipping the separator, and stops at the last row without changing step

#### Scenario: Arriving on Benches
- **WHEN** the user presses → on Workstation
- **THEN** Benches is shown with the category zone focused on the first category that has benches

### Requirement: Top nav bar
The nav bar SHALL show every step in order by name, joined by short ` ─ ` connectors, marking steps before the current one `✓`, the current step a highlighted `●` and later steps `○`, each followed by its number of queued changes when that number is not zero. Profiles rows run their actions immediately, so Profiles SHALL never show a count. The full nav SHALL be shown whenever it fits the frame width; with three single-digit counts it is 79 columns including the current step's highlight, so it fits an 80-column terminal. The compact form used when it does not fit SHALL show no queued counts; the footer keeps the total. The Workstation item SHALL show readiness in place of its step marker: a green `✓` when every required item is Up, a yellow `⚠` when one is not, and a blinking `…` while checks run. When Workstation is the current step, its item takes the current-step highlight and keeps the readiness mark.

#### Scenario: Queued counts per step
- **WHEN** two benches and one agent are queued and nothing else
- **THEN** the nav shows `Benches 2` and `Harness 1`
- **AND** Tools, Profiles and Review show no count

#### Scenario: Full nav on an 80-column terminal
- **WHEN** the terminal is 80 columns wide and two benches, one agent and one tool are queued
- **THEN** the nav is one line naming all six steps, with `Benches 2`, `Harness 1` and `Tools 1`, joined by ` ─ `

#### Scenario: Readiness on every step
- **WHEN** checks are running
- **THEN** the Workstation item shows a blinking `…` on every step
- **AND** when checks finish with Docker Down it shows a yellow `⚠`, and when every required item is Up it shows a green `✓`

#### Scenario: Compact nav on a narrow terminal
- **WHEN** the full nav does not fit the frame width, as at 60 columns, or at 80 columns with a two-digit count
- **THEN** the nav is one line naming the current step as `Step N of 6 · <Name>` with one progress mark per step, the first being the Workstation readiness mark, and no queued counts

### Requirement: Enter opens Review
Enter SHALL run the focused row's action when the focus is a Workstation service row (WSL 2, Docker, Tools, Vault) or a Profiles row. Everywhere else Enter SHALL open the Review step without applying, installing or removing anything.

#### Scenario: Enter on a component opens Review
- **WHEN** Codex CLI is queued for update and the user presses Enter on the Harness step
- **THEN** the Review step is shown
- **AND** nothing is installed or updated and the queued change is unchanged

#### Scenario: Enter in the Benches category zone opens Review
- **WHEN** the Benches category zone has focus and the user presses Enter
- **THEN** the Review step is shown

#### Scenario: Enter on a service row acts immediately
- **WHEN** the Docker row on Workstation offers Start and the user presses Enter on it
- **THEN** the Docker Start action runs at once
- **AND** queued changes are unchanged and Review is not opened

### Requirement: Review lists every queued change
The Review step SHALL list every queued change under INSTALL, UPDATE and REMOVE groups, in step order, each item with the step it belongs to, with the REMOVE group noting that projects and credentials are kept, and SHALL state that nothing has changed yet and that Enter applies the changes. It SHALL show a yellow warning when Shell setup (replaces shell settings) or Org workspace (may create a GitHub repository) is queued, and SHALL let the user see every item even when the list is taller than its rows. Reached by Enter or by ←/→, Review SHALL open at its first item; a P or G return SHALL restore the remembered position. Review SHALL be read-only: no key on Review queues or unqueues a change, which is done on the step the item belongs to.

#### Scenario: Grouped changes
- **WHEN** rustBench is queued for install, javaBench and Codex CLI for update, and pyBench for removal
- **THEN** Review shows rustBench under INSTALL with step Benches, javaBench (Benches) and Codex CLI (Harness) under UPDATE, and pyBench under REMOVE
- **AND** it shows the line "Nothing has changed yet. Enter applies these changes."

#### Scenario: Risky optional changes are flagged
- **WHEN** Shell setup and Org workspace are queued
- **THEN** Review shows yellow warnings that Shell setup replaces shell settings and that Org workspace may create a GitHub repository

#### Scenario: Nothing queued
- **WHEN** no change is queued and Review is shown
- **THEN** Review states that no changes are selected and that Enter finishes without changes

#### Scenario: Long list stays readable
- **WHEN** more changes are queued than Review has rows for
- **THEN** Review shows how many items are hidden above or below
- **AND** ↑/↓ scroll the list so every queued item can be displayed

#### Scenario: Review opens at the top
- **WHEN** more changes are queued than Review has rows and the user presses Enter on Benches
- **THEN** Review shows its first item at the top of the list

### Requirement: Apply from Review
Enter on Review SHALL apply the queued changes, or with `--select-only` write the selection file, only when no readiness checks are running and every required workstation item is Up. Otherwise it SHALL apply nothing, and while Apply is blocked Review SHALL show a yellow blocker line saying why Apply is waiting. With nothing queued the same gating applies, and Enter on Review finishes without changes, exiting with status 0 (with `--select-only`, after writing a selection file with no components), as the previous TUI's empty Enter did.

#### Scenario: Apply when ready
- **WHEN** every required item is Up, checks have finished, Codex CLI is queued for update and the user presses Enter on Review
- **THEN** setup applies exactly the queued changes, as Enter did before this change

#### Scenario: Blocked while checks run
- **WHEN** checks are still running and the user presses Enter on Review
- **THEN** nothing is applied, Review shows that Apply is waiting for checks, and the TUI stays open

#### Scenario: Blocked by unresolved requirements
- **WHEN** checks have finished with Docker Down and the user presses Enter on Review
- **THEN** nothing is applied and Review shows that workstation requirements must be resolved first

#### Scenario: Selection-only run
- **WHEN** `setup.sh` runs the TUI with `--select-only` and the user presses Enter on Review with two changes queued
- **THEN** the selection file is written with `schemaVersion` 1 and exactly those two `{key, action}` components

#### Scenario: Finish without changes
- **WHEN** nothing is queued and the user presses Enter on Review
- **THEN** setup exits with status 0 without applying anything or building any image

### Requirement: Workstation jump
P SHALL move from any other step to Workstation, focusing its first row and remembering that step and its exact focus (row, and on Benches the zone, category and bench). P on Workstation SHALL return to the remembered step and focus, or to the Benches category zone on the first category that has benches when none is remembered. Moving ← from Benches to Workstation and the automatic readiness jump SHALL remember focus the same way.

#### Scenario: Round trip from the bench zone
- **WHEN** javaBench is focused in the Software Engineering bench zone and the user presses P, then P again
- **THEN** Workstation is shown, and then Benches is shown again with javaBench focused in the bench zone

#### Scenario: Default return after startup
- **WHEN** the TUI has just opened on Workstation and the user presses P
- **THEN** Benches is shown with the category zone focused on its first category

#### Scenario: Return after moving left
- **WHEN** the user moves ← from Benches with Science focused in the category zone and then presses P
- **THEN** Benches is shown with Science focused in the category zone

### Requirement: Profiles jump
G SHALL move from any other step to Profiles, focusing its first row and remembering that step and its exact focus. G on Profiles SHALL return to the step and focus remembered when Profiles was entered by G, by → from Tools or by ← from Review, or to the Benches category zone on the first category that has benches when none is remembered.

#### Scenario: Round trip from Harness
- **WHEN** Codex CLI is focused on Harness and the user presses G, then G again
- **THEN** Profiles is shown, and then Harness is shown again with Codex CLI focused

#### Scenario: Return to Tools after moving right
- **WHEN** the user moves → from Tools to Profiles and presses G
- **THEN** Tools is shown with the row that was focused before

### Requirement: Vault action from any step
V SHALL run the Vault service action for its current state (Install, Start, Connect or Sign out) from every step without changing the step, the focus or the queued changes. Only the Workstation step SHALL advertise V, and the action's result notice SHALL be shown on the step where V was pressed.

#### Scenario: Connect from Benches
- **WHEN** the Vault action is Connect, a bench is queued, and the user presses V on Benches and cancels the browser approval
- **THEN** the TUI returns to Benches with the same focus and the bench still queued
- **AND** Benches shows "Connection cancelled."

#### Scenario: Vault while checks run
- **WHEN** checks are still running and the user presses V
- **THEN** no Vault action runs and the current step shows that checks are still loading

#### Scenario: Advertised only on Workstation
- **WHEN** any step other than Workstation is shown
- **THEN** no `V` hint or `[V <Action>]` button appears on it

### Requirement: Refresh keeps state
R SHALL re-run readiness and component checks while keeping the current step, the focus (including the Benches zone, category and focused bench) and every queued change, except for a bench that leaves the catalog (setup-bench-browser › Focus survives catalog updates).

#### Scenario: Refresh on Benches
- **WHEN** javaBench is queued and focused in the bench zone and the user presses R
- **THEN** statuses show Loading and then reload
- **AND** javaBench stays queued and focused in the same category and zone

### Requirement: Quit from any step
Q SHALL quit from every step, including while checks run, SHALL stop pending checks and remove their private status files, SHALL apply nothing and SHALL exit with status 130.

#### Scenario: Quit during loading
- **WHEN** checks are running on any step and the user presses Q
- **THEN** setup prints "Setup cancelled.", exits with status 130 within two seconds, and leaves no check process running

### Requirement: Readiness jump
When a run of background checks finishes with a required workstation item not Up, including a run started by R, the TUI SHALL show the Workstation step, remember the previous step and focus for P, focus the first required item that is not Up, and show "Resolve workstation requirements to continue.". When Workstation is already shown, the remembered P target SHALL be kept.

#### Scenario: Docker down after loading
- **WHEN** the user is in the Benches bench zone while checks finish with Docker Down
- **THEN** Workstation is shown with the Docker row focused and the notice displayed
- **AND** pressing P returns to the same bench in the bench zone

### Requirement: Workstation step
The Workstation step SHALL show, below its requirements strip, a REQUIRED SOFTWARE panel and an OPTIONAL VAULT panel whose rows show each service's state and `[Action]` button, with an explanation under the focused row only. The OPTIONAL VAULT panel SHALL list Vault alone and SHALL show `G Profiles` at the right of its title, as in 1.7, pointing to the Profiles step; the workBenches account and AI accounts rows SHALL appear only on Profiles. Space and Enter SHALL run the focused row's action, and D SHALL do nothing; while the focused row is still Loading, no action SHALL run and the step SHALL say checks are still loading, as in 1.7.

#### Scenario: Service panels
- **WHEN** Workstation is shown on WSL with every service Up and the user signed out
- **THEN** REQUIRED SOFTWARE lists WSL 2, Docker and Tools with `Up  [Check]`
- **AND** OPTIONAL VAULT lists Vault with `Up · Signed out  [Connect]`, shows `G Profiles` in its title, and lists no account rows

#### Scenario: Space acts like Enter on a service row
- **WHEN** the Tools row offers Start and the user presses Space on it
- **THEN** the Tools Start action runs and queued changes are unchanged

### Requirement: Profiles step
The Profiles step SHALL show the identities summary line, the rows Personal & companies, Workstation account and AI accounts, and an About panel for the focused row, from fixed text, sized and scrolled like the Benches About panel. Enter or Space SHALL open the focused row's existing Profiles action; that action SHALL be refused with a notice until every required workstation item is Up, and returning from it SHALL keep every queued change.

#### Scenario: Open AI accounts
- **WHEN** every required item is Up and the user presses Enter on AI accounts
- **THEN** the existing AI account setup opens
- **AND** on return Profiles shows "Profile action completed." with queued changes unchanged

#### Scenario: Refused until ready
- **WHEN** Docker is Down and the user presses Enter on Personal & companies
- **THEN** no Profiles action opens and the step shows a notice to resolve workstation requirements first

#### Scenario: Cancelled action
- **WHEN** the user cancels a Profiles action
- **THEN** Profiles shows "Profile action cancelled; saved profiles kept." and queued changes are unchanged

### Requirement: Harness and Tools steps
The Harness and Tools steps SHALL offer the same items, order and selection rules as before this change: Space SHALL queue or unqueue install (or update, when installed), D SHALL queue or unqueue removal of an installed item, items still loading or needing a check SHALL NOT be selectable, and Shell setup and Org workspace SHALL only be configurable, never removable.

#### Scenario: Queue an update
- **WHEN** Codex CLI is installed and the user presses Space on it
- **THEN** Codex CLI is queued for update and its row shows `→ Update`

#### Scenario: Removal needs an installed item
- **WHEN** an item is not installed and the user presses D on it
- **THEN** nothing is queued

#### Scenario: Loading item
- **WHEN** an item still shows Loading and the user presses Space on it
- **THEN** nothing is queued

### Requirement: Footer context and hints
Every step SHALL end with a rule and the key hints for that step; all steps except Benches SHALL retain the context line between them; the hints SHALL begin with `Navigation:`, as in 1.7. The context line SHALL show the focused item as `<Name> · <State>` followed by `→ <action>` when one is queued; where nothing is focused or the row has no state, `Review · Nothing applied yet` on Review, the row name alone on Profiles. Benches SHALL omit the duplicate focused-bench/category context line and show the total number of queued changes at the right of its footer rule; other steps SHALL show that total at the right of the context line: `Changes selected: N` at widths of 60 columns or more, and `Changes: N` below 60 columns, where a context line too long for the remaining width SHALL be cut with `…`. Below 60 columns the hints SHALL take at most two lines, listing the step's own keys (on Profiles, `G Back`) plus `←→`, `Enter` and `Q`; P, G, R, V and PgUp/PgDn SHALL keep working on every step but SHALL be listed only at 60 columns or more. At 60 columns or more the step's full hint list SHALL be shown, wrapped over as many lines as it needs (two at 80 columns or more), within the frame's height bounds.

#### Scenario: No duplicate bench context
- **WHEN** javaBench is installed, queued for update and focused, with two changes queued in total
- **THEN** its status and queued action appear in the bench list, the footer rule ends with `Changes selected: 2`, and no context line repeats the bench below About

#### Scenario: Context without a focused item
- **WHEN** Review is shown with four changes queued
- **THEN** the context line reads `Review · Nothing applied yet` with `Changes selected: 4` at its right

#### Scenario: No duplicate category context
- **WHEN** Science is current in the Benches category zone and has two benches, one installed
- **THEN** the category block shows those counts and no footer context line repeats them

#### Scenario: Narrow Benches total
- **WHEN** the frame is 36 columns wide and javaBench is installed, queued for update and focused, with four changes queued in total
- **THEN** the footer rule ends with `Changes: 4` and no focused-bench context line is drawn

#### Scenario: Narrow hints
- **WHEN** the Benches bench zone is shown in a 36×24 terminal
- **THEN** the hints take at most two lines and list Space, D, `←→`, Enter and Q
- **AND** P, R and PgUp/PgDn are not listed, and pressing P still shows Workstation

#### Scenario: Profiles hints
- **WHEN** the Profiles step is shown
- **THEN** its hints include `G Back` and `Q Quit` on the same line

### Requirement: Setup contracts unchanged
The wizard SHALL leave the `setup.sh` modes `--select-only`, `--dependencies-plan` and `--apply-plan`, the selection-file JSON (`schemaVersion` 1 with `components` of `key` and `action`), how the selection file is written (private to the user, never through a symlink) and the apply and plan semantics unchanged, and the non-interactive modes SHALL NOT draw the wizard.

#### Scenario: Same selection, same file
- **WHEN** the user queues pyBench for install and Codex CLI for update and confirms on Review in a `--select-only` run
- **THEN** the selection file contains exactly `bench_pyBench`/`install` and `codex_cli`/`update`, as the previous TUI would have written

#### Scenario: Apply plan without drawing
- **WHEN** `interactive-setup.sh --apply-plan <file>` runs with a valid selection file
- **THEN** it applies the selection without drawing any wizard frame
