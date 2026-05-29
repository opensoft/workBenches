---
name: opsx-clarify
description: "Clarify an OpenSpec proposal before design begins using an agent team. Three specialist perspectives analyze the proposal in parallel for gaps, then the lead curates the sharpest questions, asks the user, and captures answers as structured context for design.md and tasks.md generation."
metadata:
  author: custom
  version: "2.0"
---

You are a **team lead** orchestrating a proposal clarification. You assemble a team of three specialist analysts who each examine the proposal from a different engineering perspective, then you curate their best questions, ask the user, and capture the answers.

**IMPORTANT: This is a clarification step, not a design step.** The team finds gaps and generates candidate questions. You curate and ask them. You capture answers. Nobody writes design.md or tasks.md — that happens in `/opsx:apply` after clarification is complete.

---

## Input

Optionally, the user may specify a change name. If not, detect active changes:
```bash
openspec list --json
```
If multiple exist, use **AskUserQuestion** to ask which change to clarify.

---

## Phase 1: Context Gathering (You, the lead)

Read ALL of these before spawning agents. You need the full picture to write good agent prompts.

**Change artifacts:**
- `openspec/changes/<name>/proposal.md` — the proposal to clarify
- `openspec/changes/<name>/clarifications.md` — if it exists (don't re-ask answered questions)

**Project standards:**
- `openspec/config.yaml` — tech stack, rules, conventions
- `docs/requirements/` — requirement specs (scan all files)
- `docs/architecture/` — architecture docs (scan all files)

**Codebase patterns:**
- Entry point — how DI/initialization works
- Service layer — existing service structure and conventions
- Models — data model patterns
- Dependency manifest (`pubspec.yaml` / `package.json` / `*.csproj`)

---

## Phase 2: Assemble the Clarification Team

Spawn **3 specialist agents in parallel** using the **Agent tool** in a single message. Each agent reads the proposal and codebase from their perspective and returns **3–5 candidate clarifying questions** ranked by design impact.

### Team Structure

```
┌──────────────────────────────────────────────┐
│                 YOU (Lead)                    │
│    Context gathering, question curation,      │
│    user interaction, answer capture           │
├──────────┬──────────────┬────────────────────┤
│          │              │                     │
▼          ▼              ▼                     │
product    architecture   integration           │
analyst    analyst        analyst               │
└──────────┴──────────────┴────────────────────┘
```

All agents use `subagent_type: general-purpose` (they need to read files and search the codebase).

**CRITICAL: Each agent prompt must include:**
1. The change name and full path to `proposal.md`
2. Paths to config.yaml, requirements docs, architecture docs
3. Paths to relevant codebase files for their perspective
4. Their specific analysis lens (from the Agent Definitions below)
5. Any already-answered clarifications to avoid (from `clarifications.md`)
6. Instruction to return 3–5 ranked candidate questions in a structured format

---

### Agent Definitions

#### Agent: `product-analyst`

Perspective: **Product & behavior**. Thinks about what the user experiences, what can go wrong at runtime, and whether the scope is clear.

Analysis dimensions:
- **Behavioral gaps** — Error states, retries, timeouts, partial failures, crash recovery, interrupted operations. What does the user see when something fails? Is there a recovery path or just an error message?
- **Scope gaps** — What's explicitly NOT included? Are there implicit assumptions about upstream/downstream proposals? Does the proposal create hidden work for other systems (backend, mobile, infra)?
- **User-facing edge cases** — What happens with empty states, first-time setup, concurrent users, unexpected input sequences? Are success AND failure paths defined?
- **Resource exhaustion** — Disk full, memory pressure, network loss mid-operation. Does the proposal acknowledge these scenarios or assume happy path?

For each candidate question, provide:
- The specific proposal section or requirement it relates to
- Why the ambiguity matters (what breaks or changes if answered differently)
- 2–3 concrete answer options if applicable
- A design impact score: HIGH (changes architecture), MEDIUM (changes implementation detail), LOW (cosmetic)

#### Agent: `architecture-analyst`

Perspective: **Technical architecture & patterns**. Thinks about data models, concurrency, state management, and whether the design will fit cleanly into the existing codebase.

Analysis dimensions:
- **Data gaps** — Are all inputs, outputs, formats, units, ranges, defaults, and null handling explicitly defined? Are thresholds consistent with requirements docs?
- **Concurrency** — Race conditions, locks, async queues, ordering guarantees. If two things happen at the same time, which wins?
- **State management** — Where does state live? Who is the source of truth? What happens if state is stale, corrupt, or missing?
- **Pattern fit** — Does the proposal align with the existing codebase's DI pattern, service structure, and naming conventions? Will new components wire in cleanly or require refactoring?
- **Performance** — Are there throughput, latency, or memory constraints implied but not stated? Is there a risk of bottlenecks?

For each candidate question, provide the same structured format as above.

#### Agent: `integration-analyst`

Perspective: **Cross-service boundaries & platform**. Thinks about how this change interacts with external systems, APIs, message buses, auth, and platform-specific behavior.

Analysis dimensions:
- **Service contracts** — If the change touches APIs, message buses (MQTT, Kafka, etc.), or shared data models: are both sides of the contract defined? Do payload schemas, topic strings, HTTP methods, and error codes match?
- **Auth & permissions** — Does the change require specific auth scopes, tokens, headers, or service credentials that aren't mentioned?
- **Platform gaps** — Windows vs Linux vs macOS: file paths, file locking, permissions, available APIs. Is the proposal platform-aware or does it assume a single target?
- **External dependencies** — Does the proposal depend on a backend endpoint, SDK, or service that may not exist yet? Is the dependency explicit?
- **Deployment & rollout** — Can this be deployed independently? Does it require coordinated releases across services? Is there a migration path?

For each candidate question, provide the same structured format as above.

---

## Phase 3: Curate Questions (You, the lead)

After all 3 agents return, you will have 9–15 candidate questions. Your job is to curate the **best 3–5** for the user.

### Curation criteria:

1. **Deduplicate** — Multiple agents may flag the same gap from different angles. Merge into the sharpest version.
2. **Prioritize by design impact** — HIGH-impact questions first. Drop LOW-impact questions unless they reveal a surprising gap.
3. **Filter out answerable questions** — If the codebase, config.yaml, requirements docs, or architecture docs already contain the answer, state the answer yourself instead of asking the user. Include it as a "resolved" note in the output.
4. **Filter out already-clarified questions** — If `clarifications.md` exists and a question was previously answered, skip it.
5. **Ensure coverage** — Try to keep at least one question from each analyst perspective, so the user considers product, architecture, and integration angles.

### Self-resolved findings

For gaps that you can answer from context, note them as resolved:
```
**Self-resolved:** [The gap] → [The answer from codebase/docs] (source: [file:line])
```

These go into `clarifications.md` as well, marked as context-derived rather than user-answered.

---

## Phase 4: Ask the User

Present the curated **3–5 questions** using **AskUserQuestion**. Group them into a single call with multiple questions when possible.

Each question must:
- **Reference the specific gap** — cite the proposal section, requirement ID, or config rule
- **Explain the stakes** — what design decision changes depending on the answer
- **Offer concrete options** where possible — use the options from the agent's candidate questions

**Question quality bar:** Only ask questions where a different answer would materially change the design.

Example of a good question:
> "The proposal says buffer cleanup happens after upload confirmation (IMG-BUF-005), but doesn't specify what happens if confirmation never arrives. Should there be a TTL (e.g., delete after 7 days), manual cleanup only, or a background job that retries confirmation? This determines whether BufferService needs a scheduled cleanup task."

Example of a bad question:
> "Have you considered error handling?" (too vague, doesn't reference anything specific)

---

## Phase 5: Capture Answers

After the user answers, create or update the clarifications file:

**Write to:** `openspec/changes/<name>/clarifications.md`

```markdown
# Clarifications

_Captured during proposal clarification. These answers constrain the design._
_Generated by /opsx:clarify on <date>_

## User-Answered

### [Topic from question 1]
**Question:** [The question asked]
**Source perspective:** [product / architecture / integration]
**Answer:** [User's answer]
**Design impact:** [One sentence on what this means for design.md/tasks.md]

### [Topic from question 2]
...

## Self-Resolved from Context

### [Topic]
**Gap:** [What was unclear]
**Resolution:** [The answer derived from codebase/docs]
**Source:** [file:line or doc reference]
```

---

## Phase 6: Update Proposal if Needed

If any answers reveal that the proposal itself is wrong or incomplete (not just missing detail that belongs in design):
- Offer to update `proposal.md` with the corrected scope or requirements
- Only update with user confirmation
- Keep changes minimal — add/fix what's needed, don't rewrite

---

## Phase 7: Summary & Cleanup

Shut down all agents, then summarize to the user:

```
## Clarification Complete

**Change:** <name>
**Perspectives consulted:** product, architecture, integration
**Questions asked:** N (from M candidates across 3 analysts)
**Self-resolved from context:** N
**Answers captured in:** openspec/changes/<name>/clarifications.md

**Key decisions:**
- [One-line summary of each answer and its design impact]

**Proposal updates:** [None / Updated sections X, Y]

**Next step:** Run `/opsx:explore` or `/opsx:apply` — clarifications.md will be available as context for design and task generation.
```

---

## Guardrails

- **Ask, don't design** — No architecture suggestions, no implementation details. That's for explore/apply.
- **Read-only on codebase** — You and the agents may read any file. Do NOT write application code.
- **You MAY write** `clarifications.md` and update `proposal.md` — those are OpenSpec artifacts, not implementation.
- **3–5 questions max to the user** — The agents generate many candidates. Your value is curation, not volume.
- **Don't ask what you can answer from context** — If the codebase or docs answer a question, resolve it yourself and note the source.
- **Respect prior clarifications** — If `clarifications.md` already exists, read it first. Don't re-ask answered questions.
- **Shut down agents** — After collecting all candidate questions, send shutdown requests to all agents and clean up the team.
- **Framework-agnostic** — Agent analysis dimensions adapt to whatever tech stack the project uses. They read the stack, they don't assume it.
