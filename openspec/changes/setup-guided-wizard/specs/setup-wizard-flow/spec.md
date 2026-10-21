# Spec Delta: setup-wizard-flow

## Purpose

Defines the interactive setup TUI as a guided wizard: its steps and their order,
the top nav bar, step and jump keys, the Enter→Review→Apply flow, the content of
the Workstation, AI assistants, Tools, Profiles and Review steps, readiness
handling, and the setup contracts the wizard must leave unchanged.

## ADDED Requirements

### Requirement: Guided wizard steps
The interactive setup TUI SHALL present one step per screen in this fixed order: Workstation, Benches, AI assistants, Tools, Profiles, Review. It SHALL open on the Workstation step and SHALL NOT show benches, AI assistants and tools side by side.

#### Scenario: Startup opens on Workstation
- **WHEN** `./setup.sh` starts the interactive TUI on a terminal
- **THEN** the first frame shows the Workstation step
- **AND** the nav bar lists Workstation, Benches, AI assistants, Tools, Profiles and Review in that order

#### Scenario: One step per screen
- **WHEN** any step is displayed
- **THEN** the frame shows only that step's content, with no three-column component screen

### Requirement: Step navigation
→ SHALL move to the next step and ← to the previous step without wrapping, and ↑/↓ SHALL move only within the current step. Arriving at a step by ← or → SHALL focus that step's first row; on Benches it SHALL focus the category zone on the first category that has benches.

#### Scenario: Next and previous step
- **WHEN** the Tools step is shown and the user presses →
- **THEN** the Profiles step is shown
- **AND** pressing ← shows the Tools step again with its first row focused

#### Scenario: No wrap at either end
- **WHEN** the user presses ← on Workstation or → on Review
- **THEN** the step does not change

#### Scenario: Vertical keys stay within the step
- **WHEN** the user presses ↓ repeatedly on AI assistants
- **THEN** focus moves through its rows, skipping the separator, and stops at the last row without changing step

#### Scenario: Arriving on Benches
- **WHEN** the user presses → on Workstation
- **THEN** Benches is shown with the category zone focused on the first category that has benches

### Requirement: Top nav bar
The nav bar SHALL show every step in order, marking steps before the current one `✓`, the current step a highlighted `●` and later steps `○`, each followed by its number of queued changes when that number is not zero. The Workstation item SHALL show readiness in place of its step marker: a green `✓` when every required item is Up, a yellow `⚠` when one is not, and a blinking `…` while checks run.

#### Scenario: Queued counts per step
- **WHEN** two benches and one AI assistant are queued and nothing else
- **THEN** the nav shows `Benches 2` and `AI assistants 1`
- **AND** Tools, Profiles and Review show no count

#### Scenario: Readiness on every step
- **WHEN** checks are running
- **THEN** the Workstation item shows a blinking `…` on every step
- **AND** when checks finish with Docker Down it shows a yellow `⚠`, and when every required item is Up it shows a green `✓`

#### Scenario: Compact nav on a narrow terminal
- **WHEN** the full nav does not fit the frame width
- **THEN** the nav is one line naming the current step as `Step N of 6 · <Name>` with one progress mark per step, the first being the Workstation readiness mark

### Requirement: Enter opens Review
Enter SHALL run the focused row's action when the focus is a Workstation service row (WSL 2, Docker, Tools, Vault) or a Profiles row. Everywhere else Enter SHALL open the Review step without applying, installing or removing anything.

#### Scenario: Enter on a component opens Review
- **WHEN** Codex CLI is queued for update and the user presses Enter on the AI assistants step
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
The Review step SHALL list every queued change under INSTALL, UPDATE and REMOVE groups, each item with the step it belongs to, and SHALL state that nothing has changed yet and that Enter applies the changes. It SHALL show a yellow warning when Shell setup (replaces shell settings) or Org workspace (may create a GitHub repository) is queued, and SHALL let the user see every item even when the list is taller than its rows.

#### Scenario: Grouped changes
- **WHEN** rustBench is queued for install, javaBench and Codex CLI for update, and pyBench for removal
- **THEN** Review shows rustBench under INSTALL with step Benches, javaBench (Benches) and Codex CLI (AI assistants) under UPDATE, and pyBench under REMOVE
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

### Requirement: Apply from Review
Enter on Review SHALL apply the queued changes, or with `--select-only` write the selection file, only when no readiness checks are running and every required workstation item is Up. Otherwise it SHALL apply nothing and show on Review why Apply is waiting.

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
P SHALL move from any other step to Workstation, remembering that step and its exact focus (row, and on Benches the zone, category and bench). P on Workstation SHALL return to the remembered step and focus, or to the Benches category zone when none is remembered. Moving ← from Benches to Workstation and the automatic readiness jump SHALL remember focus the same way.

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
G SHALL move from any other step to Profiles, remembering that step and its exact focus. G on Profiles SHALL return to the step and focus remembered when Profiles was entered by G, by → from Tools or by ← from Review, or to the Benches category zone when none is remembered.

#### Scenario: Round trip from AI assistants
- **WHEN** Codex CLI is focused on AI assistants and the user presses G, then G again
- **THEN** Profiles is shown, and then AI assistants is shown again with Codex CLI focused

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
R SHALL re-run readiness and component checks while keeping the current step, the focus (including the Benches zone, category and focused bench) and every queued change.

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
When background checks finish with a required workstation item not Up, the TUI SHALL show the Workstation step, remember the previous step and focus for P, focus the first required item that is not Up, and show "Resolve workstation requirements to continue.".

#### Scenario: Docker down after loading
- **WHEN** the user is in the Benches bench zone while checks finish with Docker Down
- **THEN** Workstation is shown with the Docker row focused and the notice displayed
- **AND** pressing P returns to the same bench in the bench zone

### Requirement: Workstation step
The Workstation step SHALL show, below its requirements strip, a REQUIRED SOFTWARE panel and an OPTIONAL VAULT panel whose rows show each service's state and `[Action]` button, with an explanation under the focused row only. Space and Enter SHALL run the focused row's action, and D SHALL do nothing.

#### Scenario: Service panels
- **WHEN** Workstation is shown on WSL with every service Up and the user signed out
- **THEN** REQUIRED SOFTWARE lists WSL 2, Docker and Tools with `Up  [Check]`
- **AND** OPTIONAL VAULT lists Vault with `Up · Signed out  [Connect]`

#### Scenario: Space acts like Enter on a service row
- **WHEN** the Tools row offers Start and the user presses Space on it
- **THEN** the Tools Start action runs and queued changes are unchanged

### Requirement: Profiles step
The Profiles step SHALL show the identities summary line, the rows Personal & companies, Workstation account and AI accounts, and an About panel for the focused row. Enter or Space SHALL open the focused row's existing Profiles action; that action SHALL be refused with a notice until every required workstation item is Up, and returning from it SHALL keep every queued change.

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

### Requirement: AI assistants and Tools steps
The AI assistants and Tools steps SHALL offer the same items, order and selection rules as before this change: Space SHALL queue or unqueue install (or update, when installed), D SHALL queue or unqueue removal of an installed item, items still loading or needing a check SHALL NOT be selectable, and Shell setup and Org workspace SHALL only be configurable, never removable.

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
Every step SHALL end with a rule, a context line and the key hints for that step. The context line SHALL show the focused item as `<Name> · <State>` followed by `→ <action>` when one is queued (or the category summary when the Benches category zone has focus) and the total number of queued changes as `Changes selected: N` at widths of 60 columns or more.

#### Scenario: Context for a queued update
- **WHEN** javaBench is installed, queued for update and focused, with two changes queued in total
- **THEN** the context line reads `javaBench · Ready → update` with `Changes selected: 2` at its right

#### Scenario: Profiles hints
- **WHEN** the Profiles step is shown
- **THEN** its hints include `G Back` and `Q Quit` on the same line

### Requirement: Setup contracts unchanged
The wizard SHALL leave the `setup.sh` modes `--select-only`, `--dependencies-plan` and `--apply-plan`, the selection-file JSON (`schemaVersion` 1 with `components` of `key` and `action`) and the apply and plan semantics unchanged, and the non-interactive modes SHALL NOT draw the wizard.

#### Scenario: Same selection, same file
- **WHEN** the user queues pyBench for install and Codex CLI for update and confirms on Review in a `--select-only` run
- **THEN** the selection file contains exactly `bench_pyBench`/`install` and `codex_cli`/`update`, as the previous TUI would have written

#### Scenario: Apply plan without drawing
- **WHEN** `interactive-setup.sh --apply-plan <file>` runs with a valid selection file
- **THEN** it applies the selection without drawing any wizard frame
