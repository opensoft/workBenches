# Guided setup wizard

`./setup.sh` opens a six-step wizard in this order:

| Step | Purpose |
|---|---|
| Workstation | Check WSL 2 when applicable, Docker and Tools; manage optional Vault. |
| Benches | Browse categories, inspect each bench and queue changes. |
| Harness | Browse Harnesses, inspect About and queue coding CLI/specification-tool changes. |
| Tools | Browse tool categories, inspect About and queue changes. |
| Profiles | Manage personal/company identities, the workstation account and AI accounts. |
| Review | Inspect the complete queue before applying it. |

Setup opens on Workstation. Its navigation mark blinks while checks run, becomes
`✓` when required services are Up, and `⚠` when they need attention. Benches,
Harness and Tools show their queued counts. Profiles has no queued count because
its rows open actions immediately. A narrow frame uses `Step N of 6` and six
progress marks instead of the full navigation line.

The header shows **openBenches v1.7** beside the Opensoft logo. The detected OS
is at the right of the divider below navigation. Narrow or short terminals use
the compact logo so both brand and navigation fit.

## Review before Apply

Space queues an install, or an update for an installed component. D queues a
removal where supported. Repeat the same action to unqueue it. Unknown/Loading
items cannot be selected; Shell setup and Org workspace cannot be removed.

**Enter opens Review; only Enter on Review applies.** Review groups every queued
change under INSTALL, UPDATE and REMOVE, with its step name. Removal preserves
projects and credentials. Warnings explain that Shell setup replaces shell
settings and Org workspace may create a GitHub repository. Review is read-only;
return to an item's step to edit its action.

Apply waits until checks finish. Component work requires every required service
Up. When prerequisites are missing, apply a service-only install plan first,
then reopen setup for components. Service-only removal does not require the
services being removed to be Up.
An empty Review finishes without component changes. In selection-only mode the
applying Enter writes the private selection file; dependency-plan and apply-plan
modes retain their existing non-interactive contracts and draw no wizard.

Profiles rows open their action immediately on Enter/Space and require readiness.
Workstation uses the same selection and Review pattern as Benches: Space selects
install/start, D selects uninstall, and Enter opens Review. V remains the explicit
Vault account shortcut.

## Workstation containers

A blank line below the navigation divider separates the Workstation content.
The Requirements count is followed by a blank row above one **Containers** panel containing WSL 2
where applicable, Docker, Tools and optional Vault. About follows the selected
service and shows its purpose and current check details. Long About text uses
the same paging keys as Benches. Rows show selection boxes and states such as
**Installed · Up**, with no Check buttons. Selected prerequisites install first;
removals run after successful component work. Docker Desktop and in-distro WSL
removal require manual host steps and are not automatically performed.

## Benches and About

The CATEGORY block lists Software Engineering, Science, System Administration
and Electrical Engineering, with bench, installed and queued counts. Empty
categories say `coming soon` and cannot receive focus. Choose a category first;
Tab, Shift+Tab or Space enters its bench list without selecting an install.

The bench zone shows names, states, queued actions and taglines where space
permits. About describes the focused bench, its uses and contents. In the category
zone it describes that category and lists its benches. Long About text pages
inside its panel; changing the focus resets its position. Missing details leave
benches usable with a fallback description; R retries an unavailable catalog.

## Agent harnesses and tools

Harness and Tools use the same category → list → About pattern as Benches.
The navigation step stays **Harness**; its panel is **Harnesses** with the active
category. Up/down chooses a category; Tab, Shift+Tab or Space enters its list
without queuing anything. Tab/Shift+Tab or up on the first item returns to
categories. About describes the focused category, group or item.

| Step | Category | Contents |
|---|---|---|
| Harness | GUI Agent Harnesses | Codex GUI, OpenCode GUI, Qwen Code Desktop, Kimi Code Desktop, ZCode, Claude Desktop |
| Harness | CLI/TUI Agent Harnesses | 77 terminal products from the supplied inventory, with ownership groups below |
| Harness | IDE/Editor Extensions | GitHub Copilot, Cline, Continue and Codex integrations targeting the local VS Code CLI default profile |
| Harness | Workflow & Specification Tools | spec-kit, OpenSpec, Omnigent, AgentTower; tags distinguish specification/planning/review from orchestration |
| Tools | IDEs & Editors | VS Code, Cursor, Kiro IDE, Antigravity IDE, Comate IDE, Neovim, AbacusAI Editor |
| Tools | Terminals & Terminal Workspaces | Warp, Wave, Herder, Foot, tmux |
| Tools | Networking | AmneziaVPN, 0dcloud VPN |
| Tools | Workstation setup | Shell setup, Org workspace, mise |

A terminal/workspace hosts the agent; the agent works on the project and tools.
Products spanning roles carry multiple tags. Codex GUI and its terminal/editor
surfaces have distinct entries. The current ChatGPT desktop app can provide the
Codex GUI surface; app presence alone does not establish feature/account access.
CLI interactive/headless modes are fields of one product. Kimi Code and legacy
Kimi CLI remain distinct, as do international Qoder/Bright Zenith and Qoder CN/
Alibaba Cloud. DeepSeek Harness lists dsh-TUI as an optional frontend plugin,
rather than duplicating the harness for each execution mode.

### CLI filters

The four columns stay above the result list. A new session starts with Type
**Frontier** and the other values **All**:

```text
FILTERS                                      16/77 F/C
›Type           │Region        │Access        │Native
Frontier        │All           │All           │All
```

Press **F** to focus the filters. **Left/Right** (or Tab/Shift+Tab) wraps between
columns; **Up/Down** wraps through the current column's choices and updates the
list immediately. Space also advances a value. F returns to results. **C** sets
all four columns to All and keeps queued actions. Outside filter focus,
Left/Right still changes steps; Enter still opens Review. Compact labels such
as Subscr. and Class. keep all four columns visible at 36 columns.

| Filter | Choices and meaning |
|---|---|
| Type | Frontier, Open, Closed, All, Unknown. Frontier is curated lab ownership, not a performance ranking. Open/Closed describe supported model weight availability, not the harness source license. A harness can match both Open and Closed, and either can overlap Frontier. The initial 12-lab set is listed in filter About and the catalog. |
| Region | All, USA, China, Other, Unknown, using qualified developer-region metadata. |
| Access | All, Subscription, API, Local, Unknown. A product can support several methods, but the column chooses one at a time; account entitlement is not probed. |
| Native | All, LLM, Image, Video, Voice, Classifier, Unknown. Image/video can mean input or generation; inspect About for direction. Classifier requires a documented workflow, not general LLM potential. |

Each column has one choice and columns combine with **AND**. Unknown includes
partial metadata; missing tags do not establish absence. Model-weight tags
record supported routes, not the installed or currently active model. Positive
tags carry source/basis/date and scope notes. All coding-harness entries have
a user-inventory LLM baseline; additional tags need evidence. Separately routed
model/plugin capabilities and ownership groups remain in About/catalog data;
they are no longer additional filter controls.

The strip shows the match count and highlights the focused column. Live results
retain the selected product when possible, otherwise focus the first match.
Each result set keeps its own scroll window. Zero results have an explicit empty
state; Space/D cannot change an old hidden product. Queued changes remain in
Review even when filtered out. P/G preserves values, column focus and list/About
state; refresh and ordinary step navigation retain filters.

### About metadata and evidence

The canonical inventory is [setup-tool-catalog.json](../config/setup-tool-catalog.json),
108 entries with one home category and multiple tags/additional surfaces. About
records developer relationship/region, model policy, interface modes, execution
location, product status, lineage, model support, autonomy and permissions.
Interoperability has separate fields for invoking another agent and its
mechanism, external invocation, delegation, state exchange and parallelism.
Launching another CLI is not evidence of structured messaging or live-session
transfer. Unknown is explicitly **Not yet verified**, never unavailable.

User-supplied claims are identified at the start of About and retain source
qualification. Documentation-backed capabilities link primary evidence and do
not certify the installed version. Reference installation detection is independent
of ownership/capability verification. GUI presence is separate from CLI presence;
Kimi Code requires its package identity (including a matching exported payload for mise/pnpm wrappers), and ambiguous/unintegrated SKUs require
manual checking. VS Code extension status applies only to its local default
profile. Windows/WSL references remain Check manually. No status implies login.

Existing managed entries keep Space/D → Review → Apply. Shell setup and Org
workspace remain configuration-only. Other entries are **Manual setup**:
they have a dot instead of a checkbox, cannot be queued, and show publisher/setup
sources when verified. Unknown publisher links are explicitly pending. No new
installers, credential options or selection-plan keys are added.

The compiler validates metadata and generates static Bash/Python snapshots:
`python3 scripts/setup-tool-catalog.py --write`; `--check` rejects drift.
Rendering uses only cached data/Bash builtins, with no runtime JSON parsing.
PgUp/PgDn or [/] pages About. P/G restores category, CLI filter values/column, zone, item and
list/About offsets. Refresh retains these and every queued change. Narrow frames
use four compact filter columns, visible focus and compact manual-status labels so names stay
readable. Large lists reserve room for capability About text (at least five lines in an 87×40 frame). Lists scroll while retaining the focused row and About/footer.

## Keys

| Key | Action |
|---|---|
| ← / → | Previous/next step; in CLI filter focus, choose the previous/next column. |
| ↑ / ↓ | Move within the step; scroll Review; in CLI filters, cycle the focused value. |
| Tab / Shift+Tab | Switch category/list zones; in CLI filters, choose the next/previous column. |
| F | Move focus between CLI filter columns and results. |
| C | Set all CLI filter columns to All without changing queued actions. |
| Space / D | Queue/unqueue install or update / removal; in CLI filters Space cycles the value and D does nothing. Space opens Profiles actions. |
| Enter | Open Review, apply from Review, or open a Profiles row. |
| P | Visit Workstation and return to the remembered step and focus. |
| G | Visit Profiles; G Back restores the remembered step and focus. |
| V | Run Vault's current action from any step; advertised on Workstation. |
| R | Refresh checks while preserving focus and queued changes. |
| PgUp / PgDn, [ / ] | Page About on Workstation, Benches, Harness, Tools and Profiles. |
| Q | Cancel without applying; stop pending checks and remove their private snapshots. |

The footer shows the focused item and total changes. Below 60 columns it uses
`Changes: N` and at most two hint lines. Unlisted global keys continue to work.

## Terminal sizes and updates

The minimum supported terminal is **36×24**. The frame is one column narrower
than the terminal, clamped to 36–87 columns. Lists scroll with hidden-row counts;
short frames collapse the banner and category block before clipping from the top.
Unknown height shows all rows. Below 36 columns the wizard still runs with a
36-column frame, which may wrap.

The first frame appears before discovery checks. Rendering uses cached state;
updates rewrite only changed lines. A resize or returning helper triggers a full
repaint. The four-line wordmark appears only when width and height permit it.

For a selection-only preview, run:

```bash
scripts/interactive-setup.sh --select-only /tmp/wizard-preview.json
```

This runs readiness checks and may start managed Tools. Service/profile actions
still run when explicitly opened; Q cancels the preview without applying a queue.

Managed terminal entries use the normal Space/D action queue. Review shows the
workstation plus benches queued for install/update as their exact targets. See
[managed CLI harnesses](managed-cli-harnesses.md); pending stopped targets retain
rebuild intent and do not count as a successful live install.
