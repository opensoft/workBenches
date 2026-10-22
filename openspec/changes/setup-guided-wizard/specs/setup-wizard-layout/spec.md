# Spec Delta: setup-wizard-layout

## Purpose

Defines how every wizard frame is composed and bounded: the head, the per-step
selector area, notices, width and height limits, banner collapse, first paint
without discovery, partial redraw, key response time and loading indicators.

## ADDED Requirements

### Requirement: Frame head
Every wizard frame SHALL begin with the Opensoft banner and `openBenches v1.7` to its right on the same row, one blank row, the nav bar and one separator rule with the detected OS right-aligned within it. There SHALL be no separate version/OS row, per-step title or description sentence. This display brand SHALL NOT change the repository VERSION or other product identifiers.

#### Scenario: Head order
- **WHEN** any step is displayed
- **THEN** `openBenches v1.7` appears beside the logo, followed by one blank row, the nav bar and a single rule with the detected OS at its right

#### Scenario: No step titles
- **WHEN** any step is displayed
- **THEN** the frame contains no `STEP n OF m` title and no per-step description sentence

### Requirement: Step selector area
The rows under the rule SHALL be the current step's selector area: the requirements strip on Workstation, the CATEGORY block on Benches and the identities summary line on Profiles. Harness and Tools SHALL start directly with their panels, and Review SHALL start with its instruction line.

#### Scenario: Strip only on Workstation
- **WHEN** Workstation is shown
- **THEN** the first row under the rule begins with `REQUIREMENTS ·`
- **AND** when Benches, Harness, Tools, Profiles or Review is shown, no `REQUIREMENTS ·` strip appears

#### Scenario: Category block on Benches
- **WHEN** Benches is shown after the catalog has loaded
- **THEN** the category block begins with `CATEGORY`, after one blank row in the roomy layout and directly under the rule in the tight layout

#### Scenario: Identities line on Profiles
- **WHEN** Profiles is shown
- **THEN** the first row under the rule is one line summarizing the cached personal and company identities, cut with `…` when it is wider than the frame

### Requirement: Requirements strip
The Workstation strip SHALL read `REQUIREMENTS · R/N ready`, where R of the N required services are Up and optional Vault is not counted (as in 1.7), or `REQUIREMENTS · Loading…` while checks run, followed by each required service and Vault with its state, with Vault followed by `[V <Action>]`. Items SHALL be green when Up, yellow otherwise and blinking while loading, and the strip SHALL wrap only between items so Vault's action is never split.

#### Scenario: Ready strip on WSL
- **WHEN** WSL 2, Docker, Tools and Vault are Up and the user is signed out
- **THEN** the strip shows `REQUIREMENTS · 3/3 ready`, `WSL 2 Up`, `Docker Up`, `Tools Up` and `Vault Up [V Connect]`

#### Scenario: Narrow strip
- **WHEN** the frame is 36 columns wide
- **THEN** the strip wraps between items and `[V Connect]` appears whole on one line

### Requirement: Notices on the current step
A notice produced by the Vault action, a Profiles action, a blocked Apply or the readiness check SHALL be shown on the current step, after its selector area, cut to the frame width. As in 1.7, a notice SHALL stay, on whichever step is current, until a later notice replaces it, a Workstation service action (V included) starts, or R clears it.

#### Scenario: Notice after V on Harness
- **WHEN** the user presses V on Harness and the action reports that Vault needs attention
- **THEN** the notice appears on the Harness step below the rule and no wider than the frame

### Requirement: Width bounds
The minimum supported terminal size SHALL be 36 columns by 24 rows. For terminals at least 36 columns wide, no rendered line SHALL be wider than the terminal; the frame SHALL be one column narrower than the terminal, clamped to 36–87 columns (as in 1.7), and padding SHALL be computed from character counts, not bytes. Narrower terminals are below the supported size: setup SHALL still run there, drawing its 36-column frame, and lines MAY wrap.

#### Scenario: Width matrix
- **WHEN** each step is rendered at 36, 60 and 87 terminal columns, with long names and every status present
- **THEN** no line is wider than the terminal

#### Scenario: Wide terminal
- **WHEN** the terminal is 120 columns wide
- **THEN** the frame is 87 columns wide

#### Scenario: Multibyte text stays aligned
- **WHEN** a focused Workstation row's explanation reads "Checking workstation readiness…"
- **THEN** that line's right border is in the same column as the panel's other borders

### Requirement: Height bounds
When the terminal height is known, the frame SHALL never be taller than the terminal. A tight layout with one blank row below the one-line banner and no other blank spacer lines SHALL apply at 24 rows or fewer and whenever the roomy layout would not fit. Lists SHALL scroll inside their panels with `▲ N more` and `▼ N more` rows, keeping the focused row visible, and when the height is unknown nothing SHALL be clipped.

#### Scenario: Standard 24-row terminal
- **WHEN** each step is rendered at 80×24 and 37×24 with all 12 benches catalogued
- **THEN** each frame has at most 24 lines and shows the nav bar, the focused row and the whole footer

#### Scenario: Long list scrolls
- **WHEN** a panel has more rows than fit and focus moves to a row below the visible ones
- **THEN** the panel scrolls so the focused row is visible and shows how many rows are hidden above and below

#### Scenario: Unknown height
- **WHEN** the terminal height cannot be read
- **THEN** every row of the step is rendered and no `N more` row appears

#### Scenario: Below the supported height
- **WHEN** the terminal is shorter than the tight layout needs
- **THEN** the frame drops lines from its top and is still no taller than the terminal

### Requirement: Banner collapse
Every banner/brand block SHALL be followed by one blank row before navigation.

The four-row OpenSoft wordmark SHALL be drawn only in the roomy layout, when the frame is at least 59 columns wide so the brand fits beside it and the terminal height is unknown or at least 40 rows; otherwise a one-line `Opensoft` banner with `openBenches v1.7` to its right SHALL be drawn.

#### Scenario: Tall terminal
- **WHEN** the terminal is 88×40
- **THEN** the four-row wordmark is drawn

#### Scenario: Shorter terminal
- **WHEN** the terminal is 88×39
- **THEN** one line shows `Opensoft` with `openBenches v1.7` beside it

### Requirement: First paint without discovery
The first frame SHALL be drawn before any Docker, jq, Python, Git or network check runs, and rendering any step SHALL read only in-memory state, never running a discovery command.

#### Scenario: First paint with a slow Docker probe
- **WHEN** setup starts while the Docker probe blocks
- **THEN** a frame containing `Navigation:` and `Loading` is drawn before the probe returns

#### Scenario: Rendering runs no tools
- **WHEN** every step is rendered with `jq`, `python3`, `docker` and `git` replaced by commands that record any call
- **THEN** no call is recorded

### Requirement: Partial redraw
After the first paint, a status update or key press SHALL rewrite only the lines that changed. The screen SHALL be cleared only on the first paint, after an interactive helper returns, or when the terminal width or height changes.

#### Scenario: Status update
- **WHEN** Docker's status changes from Loading to Up
- **THEN** the output contains no clear-screen sequence and does not rewrite the banner/brand or OS separator

#### Scenario: Unchanged state
- **WHEN** the frame is drawn twice with no state change
- **THEN** the second draw writes nothing

#### Scenario: Resize
- **WHEN** the terminal height changes between two draws
- **THEN** the second draw clears the screen and repaints the whole frame

### Requirement: Key response time
The median time from a key press to the completed redraw SHALL be at most 100 ms, measured over repeated key-driven redraws of any step at 87×40 on a developer workstation.

#### Scenario: Benches at 87×40
- **WHEN** a test renders the Benches step at 87×40 with all 12 benches catalogued and long About text, and replays ↑, ↓, Tab and PgDn repeatedly
- **THEN** the median time from key to completed redraw is at most 100 ms

### Requirement: Loading indicators
An item whose state is not yet known SHALL show the word `Loading` in the blinking loading style, and SHALL NOT be selectable until its state is known. An item whose check ends without a state SHALL be treated as needing a check and stay unselectable, as in 1.7.

#### Scenario: First frame while loading
- **WHEN** the first frame is drawn
- **THEN** it contains `Loading` and the blink attribute sequence `ESC [5m`

#### Scenario: Loading item cannot be queued
- **WHEN** a bench still shows Loading and the user presses Space on it
- **THEN** nothing is queued
