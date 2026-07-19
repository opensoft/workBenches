# Asynchronous Clarify Protocol

A custom clarify step for [GitHub Spec Kit](https://github.com/github/spec-kit) +
Claude Code. It fans question generation out across reviewer angles, logs the questions
to a file, and finishes clarify **automatically** once they are answered — no manual
re-running.

## Why

Spec Kit's stock `/speckit.clarify` is synchronous: it asks, you answer, all in one
sitting. Real clarification has human latency — a domain expert may take a day to answer
a compliance question. This protocol decouples **question generation** (cheap, parallel,
done by AI) from **answering** (slow, human) from **application** (one edit to `spec.md`),
and uses a polling loop so the loop, not you, watches for completion.

## The four files

| File | Role |
|------|------|
| `.claude/commands/openClarify.md` | Orchestrator. Resolves the feature dir, initializes the log, triggers the generation fan-out, registers the poll loop. Never answers questions. |
| `.claude/commands/openClarify-resume.md` | Poll tick. Reads the log and branches cheaply; only the all-answered tick edits `spec.md`. Enforces the critical-class human gate. |
| `templates/clarify-log.template.md` | The log schema: two top-of-file sentinels + per-question blocks. |
| `PROTOCOL.md` | This document. |

## Data flow

```
/openClarify [feature-dir]
   ├─ verify spec.md exists
   ├─ init clarify-log.md from template   (GENERATION: PENDING, CLARIFY: IN_PROGRESS)
   ├─ workflow: fan out reviewer angles ──┐
   │     data-model ┐                     │ each appends OPEN question blocks
   │     edge-cases ┤                     │ merge + dedupe, cap 25
   │     security-compliance ┤            │ then flip GENERATION: COMPLETE
   │     testability ┤                    │
   │     integration ┘                    │
   └─ register  /loop 10m /openClarify-resume <dir>

   ... humans answer blocks in clarify-log.md over time ...

/openClarify-resume <dir>   (every 10 min)
   ├─ log missing?           → no-op
   ├─ CLARIFY: COMPLETE?     → no-op, stop loop
   ├─ GENERATION != COMPLETE → no-op           (sentinel guard: no early firing)
   ├─ any status: OPEN?      → no-op           (still waiting)
   ├─ critical answered by architect-ai? → no-op (human escalation)
   └─ all answered, criticals human-signed → edit spec.md, CLARIFY: COMPLETE, stop loop
```

## The log schema

Two **sentinels** at the top of `clarify-log.md` are the entire coordination contract:

- `GENERATION: PENDING | COMPLETE` — set `COMPLETE` only when the fan-out has written
  every question. Until then the poller refuses to act.
- `CLARIFY: IN_PROGRESS | COMPLETE` — set `COMPLETE` only after answers are applied to
  `spec.md`.

Each question is a block:

```
## Q3
- id: q3
- status: OPEN            # OPEN | ANSWERED
- class: normal          # normal | critical
- agent: security-compliance   # which reviewer angle raised it
- question: How long is PHI retained after account deletion?
- answer:
- answered_by:           # human | architect-ai
- ts:
```

## Three design guarantees

1. **Sentinel guard against early firing.** The poller treats `GENERATION: COMPLETE` as a
   precondition. A log that is mid-generation can momentarily show "zero OPEN questions"
   simply because no questions have been written yet — the guard stops the poller from
   misreading that as "all answered" and prematurely editing `spec.md`.

2. **Critical-class human escalation.** A `class: critical` question (clinical / regulated /
   safety-impacting) answered by `architect-ai` does **not** clear. Completion blocks until
   a human re-answers or confirms it. The AI can draft; only a human signature releases the
   gate.

3. **Cheap read-and-branch ticks.** Nearly every poll tick just greps the sentinels and a
   handful of `status:` lines, then exits. Exactly one tick — the one that sees everything
   answered and all criticals human-signed — does the expensive `spec.md` edit. Polling
   every 10 minutes is therefore nearly free.

## Relationship to stock `/speckit.clarify` — audit pass

This protocol **does the clarification work**, then stock `/speckit.clarify` runs **after**
as an **audit**, not as the primary clarifier.

Because `/openClarify-resume` writes answers in stock's canonical shape — a
`## Clarifications` section with `### Session YYYY-MM-DD` and `- Q: … → A: …` bullets, plus
the answer folded into the relevant spec section — a subsequent stock run sees those points
as already resolved. Stock decides what to ask by scanning **spec sections** against its
coverage taxonomy (Clear / Partial / Missing), so the folding in §3b is what actually makes
the audit quiet, not the log bullets.

**How to use the audit:** after our protocol marks `CLARIFY: COMPLETE`, run stock
`/speckit.clarify` (the `speckit-clarify` skill) a few times.

- **No new questions** → our five reviewer angles covered the spec to stock's standard. Proceed to `/speckit.plan`.
- **New questions** → a real coverage gap. Most will land in taxonomy categories our angles
  don't target: **functional scope & behavior, interaction/UX flow, non-functional
  (performance, scalability, reliability, observability), constraints & tradeoffs, and
  terminology consistency**. Our angles cover data-model, edge-cases, security/compliance,
  testability, and integration — so those five categories are the expected blind spots.

Treat stock's output as a **regression check on our generation coverage**. If a category
keeps surfacing, add a reviewer angle for it to the fan-out in `/openClarify`.

> Note: in this environment stock clarify is overridden (see `~/.claude` global config) to
> ask up to **25** questions in **block form**, written to `<FEATURE_DIR>/clarify-questions.md`
> — so the audit produces a diffable file rather than a one-at-a-time interactive loop.

```
/openClarify  →  (async answers)  →  resume applies + canonical format  →  CLARIFY: COMPLETE
                                                                                      │
                                                                          /speckit.clarify  ×N   (audit)
                                                                                      │
                                                          new questions? → new clarify cycle ; else → /speckit.plan
```

## Known gaps / operational notes

- **Generation script is authored on first run.** The `workflow` keyword lets the Claude
  Code runtime author the fan-out's internal script the first time `/openClarify`
  runs. **Save that run as `/openClarify-generate`** so subsequent features reuse it
  instead of re-authoring the fan-out each time.

- **`/loop` is session-scoped with a 3-day cap.** It only survives while the session is
  alive and stops after ~3 days. For human turnaround longer than that, swap the in-session
  loop for an external scheduler:

  ```
  cron + claude -p /openClarify-resume <dir>
  ```

  e.g. a crontab entry running `claude -p "/openClarify-resume specs/my-feature/"` every
  15 minutes, which survives restarts and arbitrary human latency.

## Usage

```
# 1. start (defaults to specs/<current-branch>/)
/openClarify

# 2. humans edit clarify-log.md, filling answer / answered_by / status: ANSWERED

# 3. nothing else to do — the loop applies answers to spec.md and stops itself
```
