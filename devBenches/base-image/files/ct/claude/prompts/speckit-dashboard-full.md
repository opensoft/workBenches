# CTA Speckit Dashboard Mode

You are running under the `cta` launcher in a tmux session that already has a
right-side dashboard pane. The normal Claude pane is for conversation, findings,
commands, questions, and decisions only.

## Session Dashboard — write to a file every turn

At the end of every response, write the Session Dashboard to
`.claude/dashboard.md` in the project root, creating `.claude/` if missing and
overwriting the file each turn. Do this on every turn, including short,
conversational, or trivial replies.

Do not print the dashboard in your chat reply. Do not append a dashboard footer
to chat responses. The separate tmux pane renders `.claude/dashboard.md` with
`~/.claude/speckit-dashboard.sh --loop`, including color and foldable sections.
Your reply should end normally, with no dashboard and no mention of it unless
the user asks about the dashboard itself.

Write `.claude/dashboard.md` with exactly this layout. The file itself has no
surrounding Markdown code fences:

```text
══════════════════════════════════════════════════════════════
 Speckit Dashboard
══════════════════════════════════════════════════════════════
 RECENT ACTIVITY             latest: implement T012
   15  /speckit.analyze     clean
   16  /speckit.implement   T011
   17  /speckit.implement   T012 🔵 just ran
   ↻ reruns:  implement ×2
──────────────────────────────────────────────────────────────
 SPEC KIT WORKFLOW           ▶ implement 71%
      command                %done  runs
   🟢 /speckit.constitution    100%   1
   🟢 /speckit.specify         100%   1
   🟢 /speckit.clarify         100%   1
   🟢 /speckit.checklist       100%   1   (pre-plan)
   🟢 /speckit.plan            100%   1
   🟢 /speckit.checklist       100%   1   (post-plan)
   🟢 /speckit.tasks           100%   1
   🟢 /speckit.checklist       100%   1   (post-tasks)
   🟢 /speckit.analyze         100%   1
   ○  /speckit.checklist         0%   0   (post-analyze)
   🔵 /speckit.implement        71%   2   ◀ just ran ✅
──────────────────────────────────────────────────────────────
 TASKS                                          12/17 done · 71%
   ▰▰▰▰▰▰▰▱▱▱
   ○  T013   Wire empty-state handling
   ○  T014   Add integration coverage
   … +3 more open
   🟢 done:  T001-T012   (12)
──────────────────────────────────────────────────────────────
 PHASES — Feature 003                        12/17 · 71%
   🎯 MVP ──────────────────────────────────────  12/15
   🟢 Setup         ▰▰▰  3/3
   🟢 Foundational  ▰▰▰  3/3
   🔵 US1           ▰▰▰▰▰▰▱  6/7  ◀ next
   ○  US2           ▱▱  0/2
   🛡 Post-MVP ─────────────────────────────────  0/2
   ○  Polish        ▱▱  0/2
──────────────────────────────────────────────────────────────
 LAST COMMAND                🟢 implement T012
   🟢 /speckit.implement T012 — clean
──────────────────────────────────────────────────────────────
 NEXT COMMANDS               ⭐ implement T013
   ⭐ /speckit.implement T013   next open task
      /speckit.analyze          rerun after implementation
      git push                  2 commits unpushed
──────────────────────────────────────────────────────────────
 LAST 3 PROMPTS              latest: implement T012
   1. /speckit.implement T012
   2. /speckit.implement T011
   3. /speckit.analyze
══════════════════════════════════════════════════════════════
```

Keep the horizontal rules and headers exactly as shown. Do not add a right-side
border. The box rule lines are 62 columns wide; keep every content line within
that same 62-column width so nothing overhangs the box. The pane renderer
prepends a 4-column fold marker (`▾ N `) to each section header, so section
header lines must stay within 58 columns. Truncate with `…` if needed. Emoji
count as two columns wide.

Every section header must carry a one-glance summary because folded dashboard
sections show only the header line. Use this pattern:

- `RECENT ACTIVITY             latest: <last action>`
- `SPEC KIT WORKFLOW           ▶ <current gate> <pct>%`
- `TASKS                       <done>/<total> done · <pct>%`
- `PHASES — <feature name>     <done>/<total> · <pct>%`
- `LAST COMMAND                <severity dot> <command summary>`
- `NEXT COMMANDS               ⭐ <best next step>`
- `LAST 3 PROMPTS              latest: <newest prompt summary>`

### Color Legend

Use these status markers consistently:

- 🟢 done / passed / clean / all-good
- 🔵 in progress / current / just ran
- ○ not started / not run yet — a hollow ring
- 🔴 high or critical severity / blocked / failed
- 🟠 medium severity
- 🟡 low severity
- ⭐ recommended next step
- ↻ rerun

`○` is a single-width text character, not an emoji. Wherever it stands in for a
status dot, follow it with one extra space so its row stays aligned with
double-width emoji dots.

### History Log

Maintain a running log at `.claude/speckit-history.md` in the project root.
Every time a `/speckit.*` command or another significant action runs, append one
line:

```text
NN  /speckit.command   short note (e.g. "R2", "aborted — missing tasks.md")
```

`NN` is a zero-padded sequence number that always increments, even for reruns
and aborted runs. Never rewrite or collapse past lines.

### Filling RECENT ACTIVITY

- Show the last three log entries, newest at the bottom.
- Mark the newest entry `🔵 just ran`.
- Add one `↻ reruns:` summary line when any command ran more than once, including
  counts and a flag for aborted runs.
- Omit the reruns line if nothing was rerun.
- The header always points to the full log file.

### Filling SPEC KIT WORKFLOW

Render this as an 11-row table, one row per Spec Kit gate in workflow order:
constitution, specify, clarify, checklist (pre-plan), plan, checklist
(post-plan), tasks, checklist (post-tasks), analyze, checklist (post-analyze),
implement.

`/speckit.checklist` appears four times. Each checklist row carries a trailing
stage tag so the four are distinguishable, and its dot, percent, and run count
reflect only that stage's gate.

The columns are status dot, command, percent done, and run count.

- Status dot: 🟢 done, 🔵 in progress, ○ not started.
- Command: the full command path, e.g. `/speckit.constitution`.
- Percent done: `100%` once that gate is complete; the live task percentage for
  `implement`; `0%` if it has not run.
- Runs: how many times that command has been invoked at that stage, counted from
  `.claude/speckit-history.md`.

On the row of the most recently executed command, append ` ◀ just ran ✅` if the
command completed successfully, or ` ◀ just ran ❌` if it errored or was
aborted. A command that completes cleanly is ✅ even if it surfaced findings; ❌
is only for errored or aborted runs. The `just ran` annotation does not choose
the status dot; completion state still wins.

Detect status from the repo, not memory:

- constitution: `.specify/memory/constitution.md` exists and is non-empty.
- specify: `spec.md` exists in the active feature folder (`specs/NNN-*/`).
- clarify: `spec.md` contains a `## Clarifications` section.
- plan: `plan.md` exists in the active feature folder.
- tasks: `tasks.md` exists in the active feature folder.
- analyze: `/speckit.analyze` completed successfully this session.
- checklist: the feature folder has a non-empty `checklists/` directory.
- implement: 🔵 while some `tasks.md` tasks are done but not all; 🟢 once every
  task is checked off; ○ if none are done. This completion rule overrides the
  `just ran` legend: a fully complete implement row is
  `🟢 /speckit.implement  100%  N  ◀ just ran ✅`, never 🔵.

The active feature is the `specs/NNN-*/` folder matching the current git branch,
or the most recently modified one. If `.specify/` does not exist, replace the
table with: `   Spec Kit not initialized in this repo — run: specify init`

### Filling TASKS

Source: the `tasks.md` of the active feature folder. `- [ ]` means open.
`- [x]` or `- [X]` means done.

- Header: `<done>/<total> done · <pct>%`.
- Progress bar: 10 cells on its own line, `▰` times round(done/total×10), then
  `▱` for the rest.
- List every open and in-progress task, one per line: 🔵 if being worked this
  session, 🔴 if blocked, ○ otherwise.
- Show `Txxx` plus a trimmed title.
- Cap at five open task lines; if more remain, add `   … +N more open`.
- Collapse completed tasks into one line: `🟢 done:  <id ranges>   (N)`.
- If there is no `tasks.md`, show:
  `   (no tasks.md yet — run /speckit.tasks)`.

### Filling PHASES

Include a `PHASES` section below `TASKS` only when the active feature's
`tasks.md` is organized into phases or user stories. Omit it for a flat feature.

Source: the phase and user-story headings in `tasks.md`: Setup, Foundational,
User Story 1…N, Polish. Count `- [x]` / `- [X]` done tasks and total tasks under
each heading.

- Section header: `PHASES — <feature name>` plus overall
  `<done>/<total> · <pct>%`.
- Group dividers: two rows split phases by scope:
  - `🎯 MVP`, subtotaled with `<done>/<total>`
  - `🛡 Post-MVP`, subtotaled with `<done>/<total>`
- Setup, Foundational, and every priority-P1 user story are MVP.
- P2 user stories and Polish are Post-MVP.
- Render one row per phase in `tasks.md` order.
- Phase row status dot:
  - 🟢 all tasks done
  - 🔵 current or next phase
  - ○ not started
- Phase row body: phase name, proportional bar, `done/total`, and `◀ next` on
  the next phase to work.
- Under each phase row, include one indented task detail line per task in that
  phase: six spaces, status marker, `Txxx`, and a trimmed title. The side-pane
  renderer hides these lines until the user clicks the phase row.
- Proportional bar: one cell per task, `▰` for done and `▱` for remaining. If
  the largest phase exceeds 24 tasks, scale every bar so the largest is 24.

### Filling LAST COMMAND

Show the most recent `/speckit.*` command or significant action. Prefix it with
the worst severity marker: 🟢 clean/no issues, 🟡 low, 🟠 medium, 🔴 high or
critical. For `/speckit.analyze`, include its severity tally and short finding
labels. If none yet, show: `   (none yet this session)`.

### Filling NEXT COMMANDS

List two to four actionable next steps. Mark exactly one best next action with
⭐ and give a one-line reason.

Default recommendation order:

- no constitution -> ⭐ `/speckit.constitution`
- constitution, no spec -> ⭐ `/speckit.specify`
- spec, no `## Clarifications` -> ⭐ `/speckit.clarify`
- spec clarified, no plan -> ⭐ `/speckit.plan`
- plan, no tasks -> ⭐ `/speckit.tasks`
- tasks, not yet analyzed -> ⭐ `/speckit.analyze`
- analyze surfaced findings -> ⭐ apply the fixes before continuing
- tasks analyzed and clean, open tasks remain -> ⭐ `/speckit.implement <next task>`

Include `/speckit.taskstoissues` as an option once `tasks.md` exists.

### Filling LAST 3 PROMPTS

Show the user's last three messages, most recent first, each trimmed to one line
around 60 characters. Show fewer if the session has fewer than three.

Remember: the side pane owns every dashboard element. The normal Claude pane must
not contain the dashboard.
