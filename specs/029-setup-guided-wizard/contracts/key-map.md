# Contract: key map

**Source**: OpenSpec `design.md` › Key Map and Focus Model; spec FR-003–FR-028, FR-041–FR-046. This file restates them as the input contract `handle_input` implements, plus the byte sequences and return codes. Suites drive the TUI with these bytes.

## Byte sequences

| Key | Bytes | Notes |
|---|---|---|
| ↑ ↓ → ← | `ESC [A`, `ESC [B`, `ESC [C`, `ESC [D` | two bytes read after `ESC` with a 0.1 s timeout (1.7) |
| Tab | `\t` | |
| Shift+Tab | `ESC [Z` | |
| PgUp / PgDn | `ESC [5~` / `ESC [6~` | the trailing `~` is read and consumed |
| `[` / `]` | `[` / `]` | About scroll, same as PgUp / PgDn |
| Space | ` ` | |
| Enter | `\r`, `\n` or empty read | as 1.7 |
| D, P, G, V, R, Q | either case | as 1.7 |
| anything else | — | ignored; nothing queued |

## Behaviour by step

| Key | Workstation | Benches: category zone | Benches: bench zone | Harness, Tools | Profiles | Review |
|---|---|---|---|---|---|---|
| ← / → | previous / next step; no wrap at Workstation or Review | same | same | same | same | same |
| ↑ / ↓ | move between service rows; stop at ends | change current category among those with benches (preview; no row mark); ↓ on the last focusable category enters the bench zone | move within the category; ↑ on the first bench returns to the category zone (same category); ↓ on the last bench does nothing | move; skip the separator; stop at ends | move; stop at ends | scroll the list when it does not fit; otherwise nothing |
| Tab / Shift+Tab | — | enter the bench zone on the category's first bench | return to the category zone | — | — | — |
| Space | queue/unqueue install/start | enter the bench zone (queues nothing) | queue/unqueue install or update | queue/unqueue install or update | open the row | — |
| D | queue/unqueue uninstall | — | queue/unqueue removal | queue/unqueue removal | — | — |
| Enter | open Review | open Review | open Review | open Review | open the row | apply (gated) |
| PgUp/PgDn, `[` / `]` | scroll About | scroll About | scroll About | — | scroll About | — |
| P | return to the remembered step and focus (default: Benches category zone, first category with benches) | go to Workstation, remember focus | same | same | same | same (remembers the Review offset) |
| G | go to Profiles, remember focus | same | same | same | return to the remembered step and focus (same default) | go to Profiles, remember the offset |
| V | Vault action (advertised) | Vault action | Vault action | Vault action | Vault action | Vault action |
| R | re-run checks; step, focus, zone, category, bench and queued changes kept | same | same | same | same | same |
| Q | quit: stop checks, remove status files, print "Setup cancelled.", exit 130 | same | same | same | same | same |

Arrival rules: ←/→ focus the step's first row; arriving on Benches focuses the category zone on the first category that has benches; Review opens at its first item. → from Tools writes the G target; ← from Review writes the G target; ← from Benches writes the P target.

Gates (unchanged from 1.7):

- A row whose state is `loading` runs nothing on Space or Enter; the step says checks are still loading. V while checks run does the same.
- Profiles actions are refused with a notice until every required workstation item is Up.
- Apply (Enter on Review) is refused while checks run or a required item is not Up; Review shows the blocker line and the TUI stays open.
- Items in `loading` or `needs check` are not selectable; `host_shell` and `workspace_repo` cannot be removed.

## `handle_input` return codes

| Code | Meaning | Main loop |
|---:|---|---|
| 0 | key handled (or ignored) | poll, redraw if the signature changed |
| 1 | Enter on Review passed the gate | `--select-only`: `save_selection`; interactive: `ensure_selected_dependencies`, `process_selections`; then leave the loop |
| 2 | Q, or input closed (EOF) | "Setup cancelled.", exit 130 |
| 3 | no key: read timeout while checks run, or a resize signal interrupted `read` | poll, redraw if needed |

A `read` interrupted by `SIGWINCH` (status > 128 with `setup_ui_size_stale` set) returns 3, never 2 (research R5).

## Hints (footer)

Every hint block begins with `Navigation:`. V is listed only on Workstation. Profiles lists `G Back` and `Q Quit` on the same line.

| Width | Lines | Content |
|---|---|---|
| 80+ columns | 2 | the step's full list |
| 60–79 columns | as many as needed | the step's full list, wrapped between hints |
| below 60 columns | at most 2 | the step's own keys plus `←→`, `Enter` and `Q`; P, G, R, V and PgUp/PgDn still work but are not listed |

Full lists (from the approved Benches mockup and the illustrative Workstation, Review and Profiles mockups; Harness and Tools follow the Benches bench-zone pattern without Tab and About):

```text
Workstation   Navigation: ↑↓ Move  Space Select  D Remove  PgUp/PgDn About
                          ←→ Steps  Enter Review  P Back  G Profiles  V Vault  R Refresh  Q Quit
Benches       Navigation: ↑↓ Move  Tab Category  Space Select  D Remove  PgUp/PgDn About
                          ←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit
Harness/Tools  Navigation: ↑↓ Move  Space Select  D Remove
                          ←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit
Profiles      Navigation: ↑↓ Move  Enter Open  PgUp/PgDn About
                          ←→ Steps  G Back  P Workstation  R Refresh  Q Quit
Review        Navigation: ↑↓ Scroll  ← Back  Enter Apply  P Workstation  R Refresh  Q Quit
```

`<Action>` is the focused service row's action (Check, Start, Install, Configure, Connect, Sign out). In the category zone the Benches line reads `Tab Benches` instead of `Tab Category`. Below 60 columns, for example on the Benches bench zone: `Navigation: Space Select  D Remove` and `←→ Steps  Enter Review  Q Quit` (US4-16).

## Context line (footer)

Benches omits the duplicate category/bench context line. Its queued total is at the right of the footer divider, followed directly by navigation hints. The following context-line rules apply to the other steps.

`<Name> · <State>[ → <action>]` with the queued total at the right: `Changes selected: N` at 60+ columns, `Changes: N` below 60 (the left part cut with `…`). Special cases: Review → `Review · Nothing applied yet`; Profiles → the row name. Removal and the Shell setup / Org workspace explanations keep 1.7's wording.
