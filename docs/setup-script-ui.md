# Guided setup wizard

`./setup.sh` opens a six-step wizard in this order:

| Step | Purpose |
|---|---|
| Workstation | Check WSL 2 when applicable, Docker and Tools; manage optional Vault. |
| Benches | Browse categories, inspect each bench and queue changes. |
| Harness | Queue coding CLI and specification-tool changes. |
| Tools | Queue desktop tools, Shell setup and Org workspace changes. |
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

## Keys

| Key | Action |
|---|---|
| ← / → | Previous/next step; stop at the ends. |
| ↑ / ↓ | Move within the step; scroll Review. In Benches, move within the current zone. |
| Tab / Shift+Tab | Switch Benches category/list zones. ↑ on the first bench returns to categories. |
| Space / D | Queue/unqueue install or update / removal; Space opens Profiles actions. |
| Enter | Open Review, apply from Review, or open a Profiles row. |
| P | Visit Workstation and return to the remembered step and focus. |
| G | Visit Profiles; G Back restores the remembered step and focus. |
| V | Run Vault's current action from any step; advertised on Workstation. |
| R | Refresh checks while preserving focus and queued changes. |
| PgUp / PgDn, [ / ] | Page About on Workstation, Benches and Profiles. |
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
