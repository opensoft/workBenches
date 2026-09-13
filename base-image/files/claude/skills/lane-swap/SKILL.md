---
name: lane-swap
description: "/lane-swap (alias /swap) prepares this lane for a usage reset or profile switch. It fixes the identity triple, refreshes the handoff, polls the writers, writes the swap record with the window, the lane's directory and the profile, and prints the one restart command (lane-collision-protocol Amendment 8(a), amended by Amendment 11)."
---

<!-- PROMPTS TO THE PERSON: 1 — step 3, and only when a writer still holds
     unpushed work and has not replied, and only on the MANUAL path. It was 3
     before A8 Addendum 2 (R-A8-7): the identity fix, the row's leading state
     word and the restart command are all DERIVED here now, and step 5 prints
     one command, never a menu. If a step below cannot derive something, it
     stops and says so — it does not ask. Under the AUTOMATIC swap the count is
     0: Amendment 11(4) fires this act at 95% of the 5-hour window, where there
     is no operator to ask, so step 3's wait is BOUNDED instead of asked. -->

<!-- THIS COPY IS TRANSITIONAL, AND ITS SUCCESSOR IS NAMED — A11 Addendum 4
     ruling 10, RATIFIED by Brett Heap 2026-09-13T21:08:26Z, verbatim
     "a11 addendum 4 yes" (brettheap/new-workstation#20
     issuecomment-5656154524, the rulings at issuecomment-5656076583). The `/lane-swap` skill that SURVIVES
     is `opensoft/openRepoTools#26`'s, placed by `openRepoTools --install`;
     Amendment 9 act 4b (`opensoft/workBenches#74`) deletes THIS vendored copy
     and the loop in `scripts/setup-claude-profiles.sh` that installs it.

     SO THE SIX BEHAVIOURS BELOW ARE THE HANDOVER, and ruling 10 requires #26's
     copy to absorb them BEFORE #74 removes this one. They are listed here, in
     this file, because this is the file the next writer reads:

     (Named by STEP and never by line number, for the reason the launcher's own
     `act1_compose_child_command` now gives: a line number is a citation that
     rots, and this file is about to be edited by somebody else.)

       1. step 4's `^@[0-9]+$` shape check on the window id — and its twin, the
          `^.+:[0-9]+$` check on `<session>:<index>`, made on the tmux read AND
          on the env fallback, which this round added;
       2. step 4's no-worktree `dir` rungs: the launcher's exported word first,
          then the LIVE SESSION's own harness record; `git rev-parse
          --show-toplevel` and `$PWD` are GONE and the comment says why;
       3. step 4's refusal of `, `, ` — ` and `"` in `dir` — PLUS `; `, which
          SPEC rev 6 §5 added this round, and which `window` deliberately does
          NOT take (widening A8(b)'s list would be a seventh in-force edit where
          the ratified count is six);
       4. step 4's missing `dir` is SAID, not guessed;
       5. the closing `/rename <lane>` act of step 5 — CARRIED WITH THE PREMISE
          `CF2-W1` CORRECTED HERE, not as it stood at `fa0230d`: `lane-start`
          names every branch it launches since adoption act 0 merged at
          `3719d97`, so the line is for the session that came up WITHOUT
          `lane-start`, and no act is scheduled to remove it;
       6. `/swap` in the description above.

     A copy of #26's that lacks any of the six is a REGRESSION on the day #74
     lands, which is why the list is contract and not a courtesy. -->

# `/lane-swap` (alias `/swap`) — pause this lane for a reset or profile switch

Lane-collision-protocol Amendment 8(a), amended by Amendment 11. Run every step, in order, before telling
the operator it is safe to reset usage or switch profiles. `/swap` is an alias and nothing else: it is a
command file that invokes this skill, so that the act has one text and not two copies of one that must stay
byte-equal (Amendment 11, SPEC §9). `$L` below is the symlink Amendment 5 left in place; every command is
copy-pasteable as written once `lane` is derived in step 1.

```sh
L=~/projects/xFactory/lanes-edit.sh
# THE WORKSTATION, DERIVED ONCE AND NEVER FROM `hostname` INSIDE A CONTAINER (Evidence 6,
# new-workstation#20 2026-09-13T17:57:45Z). The register is keyed on it: `swapped <ws>` answers with the
# rows that workstation wrote, and this lane's own records say `Eagle`. Inside a bench container
# `hostname -s` is the container id — `0e7d1a79a07e`, as measured — so a record written from one names a
# machine that will not exist tomorrow, and the forked orchestrator of Evidence 6 wrote exactly that into
# the log. `LANES_WORKSTATION` is the estate's own word and is honoured everywhere; `hostname` stands as it
# was, but only where this is NOT a container; inside one with nothing configured there is NO answer, and
# every use below REFUSES rather than guessing. `$L` and `$ws` are the two values the later steps reuse.
# THE LAUNCHER SETS IT (`R-A11-14`, A11 Addendum 3, ratified 2026-09-13 "a11 addendum 3 yes"): `pclaude`
# resolves the workstation on the host and exports LANES_WORKSTATION into every session it starts, and
# `wave-container-shell.sh` carries the same value through `docker exec` into a bench container. So a
# session that reaches step 4 without one was started around those two, and that is what its refusal says.
ws="${LANES_WORKSTATION:-}"
if [[ -z "$ws" && ! -e /.dockerenv && ! -e /run/.containerenv && -z "${container:-}" ]]; then
  ws="$(hostname -s 2>/dev/null || true)"
fi
printf 'ws=%s\n' "${ws:-<none: LANES_WORKSTATION is unset and this is a container; pclaude exports it from the host, and step 4 refuses without it>}"
```

## 1. Usage, then the identity triple — derived, not asked

```bash
claude-usage
window="$(tmux display-message -p '#W')"                     # Amendment 8(b): the window IS the lane
win_ref="$(tmux display-message -p '#S:#I' 2>/dev/null || true)"
win_id="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
lane="$window"
LANES_NO_FETCH=1 "$L" register-row "$lane" >/dev/null 2>&1 || lane=""
if [[ -z "$lane" ]]; then
  # THE RECORD FOR *THIS* WINDOW — the step Amendment 11 inserted BETWEEN the
  # window's name and the workstation's newest swap, read through the helper
  # (`window-lane`, SPEC §11) exactly as the launcher and `/restart` read it.
  # The `<@id>` is asked about first and the `<session>:<index>` second. This
  # step exists for one case — a window whose NAME is gone but whose record
  # names it — and a skill that skipped it would disagree with the launcher in
  # precisely that case. A helper predating Amendment 11 has no such
  # subcommand: it says so and exits 2, which is not an answer and not a fault.
  for ref in "$win_id" "$win_ref"; do
    [[ -n "$ref" && -z "$lane" ]] || continue
    candidate="$(LANES_NO_FETCH=1 "$L" window-lane "$ref" 2>/dev/null)" || candidate=""
    candidate="${candidate%%$'\n'*}"
    [[ "$candidate" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] && lane="$candidate"
  done
fi
if [[ -z "$lane" ]]; then
  # The swap record, read exactly as the launcher reads it: the STATUS decides
  # whether there is an answer at all, and the contract is the tab. A row that
  # printed before a failed read, or one with no tab, is not a record row —
  # `cut -f 1` would hand back the whole line, lane-shaped and wrong.
  # NO WORKSTATION, NO READ (Evidence 6): `swapped` with nothing would let the helper derive one from the
  # same `hostname` the preamble refused, and `swapped <container id>` asks about a machine that is not
  # this one. Either way the answer is not this workstation's, so the step answers nothing and says why.
  if [[ -n "$ws" ]]; then
    rows="$(LANES_NO_FETCH=1 "$L" swapped "$ws" 2>/dev/null)" || rows=""
  else
    rows=""
    printf 'NO workstation: this is a container and LANES_WORKSTATION names none, so the swap records were not read (Evidence 6); set LANES_WORKSTATION=<workstation> — pclaude exports it from the host into every session and container it starts (`R-A11-14`).\n'
  fi
  first="$(printf '%s\n' "$rows" | head -n 1)"
  if [[ -n "$rows" && "$first" == *$'\t'* ]]; then
    candidate="${first%%$'\t'*}"
    [[ "$candidate" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] && lane="$candidate"
  fi
fi
printf 'lane=%s\n' "${lane:-<none>}"
```

The window name answers first; the record for THIS window answers second; the workstation's newest swap
answers third — the launcher's own order, all three steps of it, so the skill and the launcher never
disagree about which lane this is. Then make the other two names match it, mechanically:

- window name ≠ lane → `tmux rename-window "$lane"`;
- Claude session name ≠ lane → type `/rename <lane>` (Amendment 2: the session name is the lane's
  messaging address).

If `lane` is empty, **nothing binds this window**. Stop, and print the command FILLED IN — the repo and
the number are the window's own name split on its last `-` (clause (e) does the same, for the same reason:
nobody should have to translate a placeholder at the one moment they are trying to get back to work):

```bash
case "$window" in
  *-[0-9]*) printf 'run: lane-start --no-launch %s %s\n' "${window%-*}" "${window##*-}" ;;
  *)        printf 'run: lane-start --no-launch REPO N; this window is named "%s", which is not a lane name, so the repo and the number have to come from the operator\n' "$window" ;;
esac
```

Only the second branch leaves anything blank, and it leaves it blank because nothing here knows it.

## 2. Refresh the handoff

The handoff path is the row's own handoff column. Derive it; do not guess it — and read the row FETCHED,
because this decides state (Amendment 7's read-after-fetch rule governs it; step 1's window/record probe is
the only no-fetch read this skill makes):

```sh
row="$("$L" register-row "$lane" 2>/dev/null | grep '^|' | tail -n 1)"
# The handoff path is the row's SIXTH column: awk field 7, because $1 is the empty string before the
# leading pipe — lanes-edit.sh's own row_cell/handoff_of_lane convention. NEVER count back from NF: this
# lane's own row alone carries 27 fields today, every extra one of them in the state history to the RIGHT
# of the handoff column, so `$(NF-2)` landed on the empty string and this step used to `git add ""` and
# commit nothing — silently, in the one step Amendment 6(e) exists for.
handoff="$(printf '%s' "$row" | awk -F'|' '{print $7}' | awk '{$1=$1};1')"
uuid="$(printf '%s' "$row" | awk -F'|' '{print $3}' \
  | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | tail -n 1)"
printf 'handoff=%s\nuuid=%s\n' "${handoff:-<none>}" "${uuid:-<none>}"
```

If `$handoff` came back empty, **stop here** — this row does not split the way `row_cell` expects, a
`git add ""` below commits nothing while looking like it worked, and Amendment 6(e) exists for exactly this
step. Read the row's own text by hand and take its handoff token; do not guess one.

`$uuid` is the **last** id in the session cell — this session, and the only one Amendment 6(b) calls the
lane's. Rewrite the handoff's state line, **every word given and not yet executed**, and the resume prompt;
a stale handoff is how given words die with the session (Amendment 6(e)). Commit with an explicit pathspec
and the Rule 5 `Lane:` trailer, then pull-rebase and push:

```sh
cd ~/projects/brett-wip
git add "$handoff"
git commit -m "handoff(<lane>@<ws>): PAUSED, <one-line state>" -m "Lane: <lane>"
git pull --rebase && git push
```

On a rebase conflict: abort, leave the tree clean, report it, and never force.

## 3. Subagents and worktrees — the one question

Run `ListAgents`, then send each running subagent one `SendMessage`: "Swap imminent: commit and push what
you have now, with the usual trailers and explicit pathspecs; reply with the sha or 'nothing to push'."
For every worktree an agent named (or found under the scratchpad) — `$worktree` below is each of those
paths in turn — report both:

```bash
git -C "$worktree" status --short              # dirty files
git -C "$worktree" log '@{u}..' --oneline      # unpushed commits
```

**Ask the operator exactly one question, and only if a writer still has unpushed work and has not replied:**
*"<agent> has unpushed work and has not replied — wait, or swap now?"* Everything else here is a report, not
a question. Never move on to step 4 with an unanswered writer unless the operator said so.

**That is the MANUAL path. Under the AUTOMATIC swap there is no operator to ask, so the wait is BOUNDED
instead** (Amendment 11(4), SPEC §9). The tell is the usage guard's own 95% directive, which says in as many
words that nobody is being asked — the one fact this skill cannot derive from inside a session, which is why
the hook states it. On that path do not ask the question; send the same message, then re-read every writer's
worktree twice, about a minute apart, and proceed. The amendment fixes only that there IS a bound; two polls
is this skill's own number, and a swap that stalls at 95% is waiting on a subagent that is about to die with
the session anyway. A writer still holding unpushed work when the bound elapses is **named in the handoff** —
the agent, its worktree, and its `git log '@{u}..' --oneline` shas — which means going back to step 2's file
for a second, small commit and push, because step 2's commit is already made. Then the swap proceeds. It
still kills nothing and still pushes nobody's work: an unpushed commit in a worktree survives the swap
untouched, and naming it in the handoff is what tells the next session where it is.

## 4. Write the swap record

First sanitize the operator's words **once**: replace every ` — ` with `; `. Amendment 7(b)/R26 refuses any
payload or free text containing ` — ` (exit 2), because that separator is what divides a line's fields from
its free text.

```sh
# (0) the refs the record carries, derived ONCE so that (a) and (c) cannot disagree about the window. The
# `window` sub-field is TWO space-separated refs, `<session>:<index> <@id>` (Amendment 11, SPEC §5); the id
# is written where one is knowable and the sub-field is `<session>:<index>` alone where it is not, because a
# record with no id is still complete — the NAME is the key and the id is only information.
# BOTH REFS ARE SHAPE-CHECKED, and for one reason. A tmux too old to know a format prints the FORMAT BACK,
# and a shim on PATH may print anything at all; recording that string would put a lie in an append-only log.
# That argument never depended on which of the two formats was asked for, and until now only the id carried
# the check. A `<session>:<index>` is a session name, a colon and digits — `^.+:[0-9]+$`, the same shape
# `claude-profile` validates this same value against (`lane_window_ref`), so the reader and the writer agree
# on what a ref is. The ENV fallback is checked too: it is a value from another process and this writer has
# no more reason to trust it unread.
win="$(tmux display-message -p '#S:#I' 2>/dev/null || true)"
[[ "$win" =~ ^.+:[0-9]+$ ]] || win=""
[[ -n "$win" ]] || win="${WORKBENCHES_CLAUDE_WINDOW_REF:-}"
[[ "$win" =~ ^.+:[0-9]+$ ]] || win=""
win_id="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
# An id is `@<digits>` and nothing else, by the same rule.
[[ "$win_id" =~ ^@[0-9]+$ ]] || win_id="${WORKBENCHES_CLAUDE_WINDOW_ID:-}"
[[ "$win_id" =~ ^@[0-9]+$ ]] && win="${win:+$win }$win_id"
# `dir` is the LANE'S CHECKOUT (Amendment 11, SPEC §4) — NEVER a worktree, and never whatever this shell
# happens to stand in (RV-W6, A11 Addendum 2 `R-A11-11`). TWO SOURCES, and both are RECORDS rather than
# derivations: the launcher's own word, exported only where the directory order's rungs 1-3 answered; then
# THE LIVE SESSION'S OWN RECORD, which is what SPEC §4 and clause (c) name as the writer's source — the
# harness writes `"cwd"` beside `"tmux"` in `$CLAUDE_CONFIG_DIR/sessions/<pid>.json`, keyed by `sessionId`,
# and that is this session's directory as the harness itself keyed it (it is also the directory whose
# CLAUDE.md and memory the session loaded, Evidence 3).
# `git rev-parse --show-toplevel` and `$PWD` were the next two rungs and are GONE. On rung 4 — every lane on
# the estate until a record carries a `dir` — they record the git toplevel of wherever the shell stands,
# which in a subagent's scratchpad worktree is that worktree. A record with NO `dir` is complete in the same
# way SPEC §5 says a record with no `@id` is; a record with the WRONG one is not, because `lane-start` writes
# the lane's home from that tree's `origin` and every `#n` after it inherits that.
dir="${WORKBENCHES_CLAUDE_LANE_DIR:-}"
if [[ -z "$dir" && -n "${CLAUDE_CODE_SESSION_ID:-}" && -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  dir="$(jq -r --arg id "$CLAUDE_CODE_SESSION_ID" \
    'select((.sessionId // "") == $id) | .cwd // empty' \
    "$CLAUDE_CONFIG_DIR"/sessions/*.json 2>/dev/null | head -n 1)"
fi
# An ABSOLUTE path or nothing at all: a relative one has no meaning without the writer's cwd, which no
# reader of the log has, and `~` is the writing shell's.
[[ "$dir" == /* ]] || dir=""
# A `window` or `dir` carrying `, ` or ` — ` is REFUSED, not appended: those two separators are what divide a
# record's fields from its free text and a row stamp's facts from each other, so the parser could not read
# the line back (Amendment 8(b)'s refusal, extended to `dir` by Amendment 11, SPEC §5). Drop the sub-field,
# keep the line — the PAUSED line is what the launcher restarts from — and report what was dropped.
#
# AND `dir` ALSO REFUSES `; ` — SPEC rev 6 §5. `; ` is the separator BETWEEN payload sub-fields, so
# `dir /a; b` reads back as a `dir` of `/a` followed by a sub-field `b` no reader knows: the same lost fact
# one level down that `, ` causes one level up. `profile` takes the same rule and needs no token for it —
# its shape check below is `^[A-Za-z0-9._-]+$`, which admits neither `;` nor a space, so a name carrying
# either is already omitted rather than written.
#
# `window` IS NOT WIDENED, and that is the ruling rather than an oversight (SPEC rev 6 §5): its list is
# Amendment 8(b)'s, narrowing it would be a SEVENTH edit to in-force text where the ratified count is six
# (`R-A11-15`), and a `window` value is a launcher-built session name, an index and an `<@id>`. The residue
# is named rather than hidden: a tmux session name containing `; ` would split the payload the same way, and
# that is A8(b)'s list to widen on the day something can produce such a name.
refused=""
case "$win" in *', '*|*' — '*) refused="$refused window=$win"; win="" ;; esac
case "$dir" in *', '*|*' — '*|*'; '*|*'"'*) refused="$refused dir=$dir"; dir="" ;; esac
# A SPACE IS QUOTED, NOT REFUSED (SPEC §5). Amendment 7(b) makes the space the separator between several
# refs inside one sub-field — which is exactly what `window`'s two refs rely on — so an unquoted
# `dir /home/b/my projects/x` parses as two refs and every reader hands back a truncated path. Quoting makes
# it ONE ref under 7(b)'s own grammar, and every reader takes a value opening with `"` as running to its
# closing `"` and strips both. A path carrying a `"` of its own joins the two separators in the refusal
# above, for the reason the whole rule has: the writer will not write a line its own parser cannot read back.
case "$dir" in *' '*) dir="\"$dir\"" ;; esac
[[ -z "$refused" ]] || printf 'REFUSED sub-field (dropped, not appended):%s\n' "$refused"
# A MISSING `dir` IS SAID, not guessed at. Where neither source answered there is no sub-field, and the
# reader of this record is told which fact it will not carry rather than handed a plausible wrong one.
[[ -n "$dir" ]] || printf 'NO dir sub-field: neither the launcher nor this session record names the lane checkout, so the record is written without one (SPEC §5).\n'
# `profile <name>` — A11 Addendum 2 `R-A11-10`, added by this PR now whether or not decision 7's listing
# halves are taken. The record is what a restart reads, and `restart <lane>` has to know WHICH ACCOUNT to
# hand `pclaude --lane <lane> <profile>`: a lane's name says nothing about the profile it runs under, and
# the wrong one is a login prompt in place of a session. `CLAUDE_PROFILE_NAME` is exported by the launcher
# on every `run`, so this is the live session's own word and not a lookup. A profile name is a manifest key
# — letters, digits, `.`, `_`, `-` — and anything else is not one, so the sub-field is OMITTED rather than
# written: a record with no `profile` is complete, one naming a profile `pclaude list` does not print is not.
profile_name="${CLAUDE_PROFILE_NAME:-}"
[[ "$profile_name" =~ ^[A-Za-z0-9._-]+$ ]] || profile_name=""
payload="swap"
[[ -z "$win" ]] || payload="$payload; window $win"
[[ -z "$dir" ]] || payload="$payload; dir $dir"
[[ -z "$profile_name" ]] || payload="$payload; profile $profile_name"
# `workstation <ws>` is $ws and never `hostname` (Evidence 6): the sub-field is what `swapped <ws>` keys
# on, so a record carrying a container id is a record no restart of this workstation will ever find — and
# it is a lie in an append-only log, which is the half that cannot be taken back. It is NOT omitted the way
# `dir` and `profile` are, and that is the difference `R-A11-14` settles: those two say something about the
# lane, and this one is the KEY the records are filed under, so a record without it is not incomplete — it
# is unfindable, and the write is refused instead (below).
[[ -z "$ws" ]] || payload="$payload; workstation $ws"
# AND WITHOUT ONE THIS WRITER REFUSES — `R-A11-14` (A11 Addendum 3, ratified by Brett Heap 2026-09-13
# "a11 addendum 3 yes"), which is clause (k) rule (d) and SPEC §16(d) in their own words: a writer inside a
# container with no configured value refuses and names LANES_WORKSTATION — SPEC rev 5 §7 puts the same
# refusal on BOTH halves of the session field and says R-A11-11 is a rule about which LINES are written and
# never a licence to invent a value for one — because both lane logs are
# append-only and a workstation that is not a workstation is wrong for ever. The cost is stated rather than
# hidden — until the value is configured, every lane write from a container stops — and it is stated in ONE
# line that also names the act that fixes it, because the variable now has an owner: the launcher sets it.
# What is NOT done here is invent a third option. `@unknown-workstation` was one: a word that is plainly not
# a hostname, in the position `swapped <ws>` keys on, which `append-line` does not validate and no reader
# would ever catch. (c) below still runs, so the row IS flipped to PAUSED and A8(a) step 4 keeps its
# substance; the gap is named in the handoff, exactly as the missing-uuid case already names its own.
ws_write_refused=""
if [[ -z "$ws" ]]; then
  ws_write_refused=1
  printf 'REFUSED: no workstation for this lane, so (a) the object-log line and (b) the register line are NOT written — LANES_WORKSTATION names the workstation, nothing here may guess one (`hostname` in a container is the container id, Evidence 6), and both logs are append-only; the launcher owns the value, so `pclaude` exports it from the host into every session and `wave-container-shell.sh` into every container it opens: set LANES_WORKSTATION=<workstation> in this session and run step 4 again. (c) below still runs, so the row is still flipped to PAUSED, and step 2 names the gap in the handoff (`R-A11-14`).\n'
fi
# (a) the Amendment 7 object-log PAUSED line — the record `swapped` reads. The uuid is checked BEFORE the
# write: `unknown` is not a transcript uuid and the object log is append-only, so a line written wrong there
# is wrong for ever (Amendment 11, SPEC §7). `lanes-edit.sh`'s own session_for() substitutes that literal
# when LANES_SESSION is unset and the row yields nothing, and it has already done so four times in two
# lanes. Refuse it here, before anything is written, and pass the uuid explicitly so the writer never guesses.
if [[ -z "${uuid:-}" ]]; then
  printf "REFUSED: no transcript uuid for this session, so nothing is written to the object log — (b) and (c) below still run, with the gap named.\n"
  printf "It is Amendment 6(c)'s session-cell append that supplies one: lane-start writes it at start, and /restart step 4 writes it for a session that started bare. Run that act, re-read the row in step 2, then come back.\n"
elif [[ -n "$ws_write_refused" ]]; then
  printf 'NOT WRITTEN: (a) carries `workstation <ws>` in its payload, and this session has none (refused above).\n'
else
  LANES_LANE="$lane" LANES_SESSION="$uuid" "$L" log PAUSED "lane:$lane" \
    → "$payload" \
    "on <operator>'s word: <sanitized verbatim>"
fi
# (b) the LANES.md file-level line, the shape every prior PAUSED/RESUMED used — AND IT IS WRITTEN OUTSIDE
# THE UUID GUARD (RV-W1, A11 Addendum 2 `R-A11-11`). SPEC §7 and clause (e) rule it in the same words: only
# a lane that has never had a session recorded at all reaches the refusal, "where the swap writes the
# register's file-level PAUSED line and the row's state cell and names the gap in the handoff". That is the
# whole of how A8(a) step 4's "never left unwritten" is preserved, so (b) and (c) survive a refusal that (a)
# does not. The two are not the same act and the difference is the file: the OBJECT LOG is append-only and a
# wrong session id there is wrong for ever, while this line is the register's own and its session position
# SAYS in words that none was recorded — a reader is told the gap instead of being handed silence.
# The session position is `session <uuid>@<workstation>` — ONE transcript uuid and ONE workstation, which is
# Amendment 7(b):137 — and where there is no uuid THE FIELD IS LEFT OUT and the gap is said in the line's own
# free text, which is free text by that grammar. `none recorded` was two tokens with a space inside a field
# the grammar gives one uuid: a reader splitting on `, ` gets `session none recorded@...`, which no parser of
# this grammar reads back, and A7(b):140 has a line the parser cannot read REPORTED as `unreadable:
# <file>:<n>` — the skill writing its own unreadable line. `@unknown-workstation` is gone for the reason one
# field along: `append-line` validates neither half, so it would land and nothing on the estate would ever
# notice (`R-A11-14`, CF-W2). No workstation is not a value to write here; it is the refusal above.
session_field=""
session_gap=" NO session recorded for this lane — Amendment 6(c)'s session-cell append supplies one;"
if [[ -n "${uuid:-}" ]]; then
  session_field="session $uuid@$ws, "
  session_gap=""
fi
if [[ -n "$ws_write_refused" ]]; then
  printf 'NOT WRITTEN: (b) carries the workstation in its session position, and this session has none (refused above).\n'
else
  "$L" append-line "PAUSED — lane $lane, ${session_field}$(date -u +%Y-%m-%dT%H:%M:%SZ), on <operator>'s word \"<sanitized verbatim>\";${session_gap} <what's open, or NOTHING CLAIMED>; handoff refreshed"
fi
# (c) the row: flip its leading state word, DERIVED from the row itself. row_write_refused is what step 5
# reads: empty on success, "1" the moment either write below does not. Its tail restates the record's own
# two facts for a person (SPEC §5), out of `$payload`, so the two writes cannot drift apart.
state="$(printf '%s' "$row" | grep -o '| [A-Z][A-Z]* ·' | head -n 1)"   # e.g. '| LIVE ·'
row_write_refused=""
"$L" replace-in-row "$lane" "$state" "| PAUSED ·" "swap" || row_write_refused=1
if [[ -z "$row_write_refused" ]]; then
  "$L" append-row-status "$lane" "PAUSED — $payload" || row_write_refused=1
fi
```

If (a) still exits 2, re-run it with the free-text argument **dropped entirely** and say so in the report:
the PAUSED line is what the launcher reads on restart, and step 4 is never left unwritten. The **one**
exception is the missing uuid, and it is an exception to **(a) alone**: there, not writing the object-log
line is the point, because an `unknown` in an append-only log cannot be taken back and a wrong session id is
worse for the next restart than no line at all. **(b) and (c) still run** — the register's file-level `PAUSED`
line with the session field LEFT OUT and the gap said in its own free text, and the row's state cell — because SPEC §7 and clause (e)
say the swap writes them and names the gap, which is how A8(a) step 4's *"never left unwritten"* survives a
lane that has never had a session recorded (RV-W1, `R-A11-11`). Name that gap in the handoff too: step 2's
file is the one a reader meets first, so its state line says the record carries no session id and names the
act that supplies one. **A missing WORKSTATION is the other refusal, and it is (a) and (b) together**
(`R-A11-14`): LANES_WORKSTATION has an owner now — `pclaude` exports it from the host into every session it
starts and `wave-container-shell.sh` into every bench container — so a session without one was started
around them, and the answer is to set it and run step 4 again, never to write a placeholder into an
append-only log. (c) still runs there too, so the row is flipped and the handoff carries the gap. Report it, name the act that supplies the uuid, and do not work around it. If `$state` came
back empty, re-read the row and take the first `| WORD ·` in it — `replace-in-row` requires exactly one
occurrence and exits 2 on a guess. If (c) is still refused after that re-read — a rebase conflict, a push
race, anything `replace-in-row`/`append-row-status` themselves report — leave `row_write_refused` set and
say so in the report; step 5 reads it, because a restart cannot resolve this lane from a record that was
never flipped to `PAUSED`.

## 5. Print the restart command — one command, no menu

```sh
if [[ -n "${row_write_refused:-}" ]]; then
  restart_cmd="pclaude --lane $lane ${CLAUDE_PROFILE_NAME:-<profile>}"
  restart_note=' (row write was refused; the lane must be named explicitly)'
else
  restart_cmd="pclaude ${CLAUDE_PROFILE_NAME:-<profile>}"
  restart_note=''
fi
printf 'READY TO SWAP — restart with: %s%s\n' "$restart_cmd" "$restart_note"
lane-start --help 2>/dev/null | grep -q -- '--confirm' \
  && echo 'restart stamps: written by lane-start (Amendment 8(d))' \
  || echo 'restart stamps: MANUAL, as the next session first act (Rule 3 / Amendment 6(c))'
# AND THE NAME THE NEXT SESSION COMES UP WITH — `R-A11-16` (A11 Addendum 3, ratified 2026-09-13 "a11
# addendum 3 yes"), which is CF-W5. THE ACT STAYS AND ITS PREMISE HAS MOVED, because the estate overtook
# it: `lane-start` names EVERY session it launches. Adoption act 0 merged as `opensoft/brett-wip#5` at
# `3719d97` on 2026-09-13 — "--name on every launch" — and at that commit `lanes/lane-start:846`, `:855`
# and `:866` ALL carry `--name "$LANE"`: the two branches that RESUME as well as the one that CREATES.
# That is the act SPEC rev 5 §13 act 0 item 2 assigns, and it is act 0's rather than the tooling round's.
# So a restart that reaches `lane-start` comes up named for the lane, and this line says nothing there —
# it is fenced on `if its name is not the lane`, and that test is the whole of it.
#
# WHAT IT IS STILL FOR is the session that comes up WITHOUT `lane-start`: the launcher's own two
# documented degradations — no `lane-start` on PATH (Evidence 5) and a `lane-start` that refused, both of
# which start bare Claude in the same window — and a `claude` typed by hand. And one more the amendment
# names in the same breath: a workstation whose `lane-start` PREDATES `3719d97`, because the fix is in a
# checkout and not in the air ("on a workstation carrying that helper the resume case no longer needs it
# either" — the qualifier is the point). Those come up with the name
# the harness derived (`openrepoproject-b9`, Evidence 4), and a lane whose messaging address (Amendment 2)
# is a derived name is a lane nobody can address. Step 1 says this for the session running the skill; this
# says it for the one that comes next.
#
# WHICH ACT REMOVES THIS LINE: none is scheduled, and that is exactly why it is printed CONDITIONALLY
# rather than always. There is no API to rename a running session from inside, so wherever a session comes
# up outside `lane-start` the operator's `/rename <lane>` is the only act there is — the amendment says the
# same at clause (i) point 2, where a `/restart` in a session already running "needs it always".
echo 'then, in the session that comes up: if its name is not the lane, type /rename <lane> (lane-start names every session it launches, the resume branches included, since adoption act 0 landed as opensoft/brett-wip#5 @3719d97; a session that came up WITHOUT it — a missing or refusing lane-start, or a bare claude — carries the name the harness derived, and no API renames one from inside)'
```

That one command is the whole restart: bare `pclaude <profile>` resolves this lane from the window name,
from the swap record step 4 just wrote when the window is gone, and from that record's `<@id>` when the
window outlived its name (Amendment 8(c), plus Amendment 11's new zero-question step). **`run` is gone from
it**: the verb was always optional, `pclaude <profile>` and `pclaude run <profile>` build the same argv, and
after Amendment 11(1) the short form is the one every surface prints — the guard's automatic-swap directive
included, so the two cannot disagree about what the operator re-runs. The profile argument is the only part
the operator changes, and only when switching accounts. **`--lane <lane>` is printed only where step 4's row
write was refused** — the row was never flipped to `PAUSED`, so a restart cannot resolve this lane from it
and the operator must name it explicitly. `--lane` is a **leading** option to `claude-profile`, read before
the action and before the profile, and after Amendment 11(1) `--dir <path>` is one too; so it goes FIRST,
never after the profile: `pclaude <profile> --lane <lane>` would be handed to Claude itself, not to the
launcher. The capability probe above decides whether the RESUMED stamps are `lane-start`'s act or the next
session's — do not assert either from memory.

**The session that comes up after the restart IS named by `lane-start` — on every branch it has.** Adoption
act 0 (`opensoft/brett-wip#5`, merged 2026-09-13 at `3719d97`) put `--name "$LANE"` on all three launch
branches, the two that RESUME included (`lanes/lane-start:846`, `:855`, `:866`), which is what SPEC rev 5
§13 act 0 item 2 gives it. An earlier revision of this step handed that to the tooling PR and said act 0 had
left it open; both were false at the commit they cited, and the correction is recorded here rather than
quietly made. So the third leg of the identity triple — Amendment 2's messaging address — is the lane
wherever the restart reaches `lane-start`. What is left is the session that does NOT reach it: a launcher
that found no `lane-start` (Evidence 5) or one that refused, both of which start bare Claude in the same
window, and a `claude` typed by hand. There the name is whatever the harness derived, and `/rename <lane>`
typed in that session is the only act that fixes it, because there is no API to rename a running session
from inside. Step 5 therefore prints the act CONDITIONALLY — *if its name is not the lane* — which is why it
needs no expiry: it is silent on every path `lane-start` named (`R-A11-16`, CF-W5).

**`/resume` and `claude --resume <title>` are not lane surfaces** (A8 Addendum 2, R-A8-6): a lane is entered
through `pclaude` or `lane-start`, and by no other door. Do not offer either as a fallback.
