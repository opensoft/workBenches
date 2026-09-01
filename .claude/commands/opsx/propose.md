---
name: "OPSX: Propose"
description: Propose a new change with alignment review and council debate before generating design and tasks
category: Workflow
tags: [workflow, artifacts, experimental, teams]
---

Propose a new change. After drafting the proposal, two review gates run before design/tasks are generated:

1. **Alignment Review** — An architect and QA lead verify the proposal against your architecture docs and requirements docs, fixing mismatches before anyone debates the proposal.
2. **Council Debate** — Three agents argue about the *aligned* proposal from product, architecture, and adversary perspectives.

Only after both gates does the lead generate design.md and tasks.md — built on a proposal that's both doc-aligned and battle-tested.

```
Flow:
  User describes idea → create change → generate proposal.md
    → ALIGNMENT REVIEW (2 agents: architect + QA lead)
    → fix mismatches in proposal
    → COUNCIL DEBATES THE ALIGNED PROPOSAL (3 agents in parallel)
    → resolve verdicts → update proposal / create clarifications.md
    → generate design.md → generate tasks.md
    → "Ready for implementation!"
```

---

**Input**: The argument after `/opsx:propose` is the change name (kebab-case), OR a description of what the user wants to build.

---

## Phase 1: Scaffold the Change

1. **If no input provided, ask what they want to build**

   Use the **AskUserQuestion tool** (open-ended, no preset options) to ask:
   > "What change do you want to work on? Describe what you want to build or fix."

   From their description, derive a kebab-case name (e.g., "add user authentication" → `add-user-auth`).

   **IMPORTANT**: Do NOT proceed without understanding what the user wants to build.

2. **Create the change directory**
   ```bash
   openspec new change "<name>"
   ```

3. **Get the artifact build order**
   ```bash
   openspec status --change "<name>" --json
   ```
   Parse `applyRequires` and `artifacts` list.

---

## Phase 2: Generate the Proposal

Generate `proposal.md` first, before any other artifact.

1. Get instructions:
   ```bash
   openspec instructions proposal --change "<name>" --json
   ```

2. Read project context:
   - `openspec/config.yaml` — tech stack, rules, conventions
   - `docs/requirements/` — existing requirements
   - `docs/architecture/` — architecture docs
   - Relevant codebase files (entry point, services, models)

3. Create `proposal.md` using the template from instructions. Apply context and rules as constraints — do NOT copy them into the file.

4. Announce: "Proposal drafted. Running alignment review..."

---

## Phase 3: Alignment Review

Before the council debates the proposal's *merit*, two specialists verify it's *consistent* with existing project docs and architecture. This catches factual mismatches (wrong thresholds, stale requirement IDs, pattern violations) so the council can focus on judgment calls instead of clerical errors.

### Team Structure

```
┌─────────────────────────────────────────────────────┐
│                    YOU (Lead)                        │
│            Apply alignment fixes to proposal         │
├─────────────────────────┬───────────────────────────┤
│                         │                            │
▼                         ▼                            │
stack-architect           qa-lead                      │
└─────────────────────────┴───────────────────────────┘
```

Spawn 2 agents **in a single message** (parallel) using the **Agent tool** with `subagent_type: general-purpose`.

---

#### Agent: `stack-architect`

> You are the **Stack Architect** reviewing a proposal for alignment with the project's architecture and tech stack conventions.
>
> **Read these files:**
> - Proposal: `openspec/changes/<name>/proposal.md`
> - Config: `openspec/config.yaml` (especially `tech_stack` and `rules.design`)
> - Architecture docs: all files in `docs/architecture/`
> - Codebase: entry point, service layer (`lib/services/`), models (`lib/models/`), controllers, dependency manifest (`pubspec.yaml` / `package.json` / `*.csproj`)
>
> **Check these dimensions:**
>
> 1. **Pattern alignment** — Does the proposal's approach match how existing services are structured? Check DI patterns, service instantiation, state management, naming conventions. If the proposal introduces a new pattern that deviates from the codebase, flag it.
> 2. **Tech stack accuracy** — Does the proposal reference the correct packages, frameworks, and versions from config.yaml? Are there assumptions about available libraries that don't match the dependency manifest?
> 3. **Architecture doc consistency** — Does anything in the proposal contradict the architecture docs? Are referenced components (services, models, APIs) described accurately?
> 4. **Integration surface** — If the proposal touches existing services or models, does it accurately describe their current interface? Check method signatures, data types, constructor parameters against the actual code.
> 5. **Config rule compliance** — Check every rule in `config.yaml` `rules.proposal` and `rules.design` sections. Does the proposal comply?
>
> **For each finding, provide:**
> - **Finding**: One sentence
> - **Source**: The doc/file/line that the proposal conflicts with
> - **Proposal reference**: Which section of the proposal is wrong
> - **Fix**: Exact correction (specific wording, not vague advice)
> - **Severity**: MISMATCH (factually wrong) or DRIFT (technically works but doesn't match conventions)
>
> Return all findings. If a dimension is clean, say so briefly.

#### Agent: `qa-lead`

> You are the **QA Lead** reviewing a proposal for alignment with the project's requirements documentation.
>
> **Read these files:**
> - Proposal: `openspec/changes/<name>/proposal.md`
> - Config: `openspec/config.yaml`
> - Requirements docs: all files in `docs/requirements/`
> - Existing specs: `openspec/specs/` (if any exist)
> - Existing change specs: `openspec/changes/<name>/specs/` (if any exist)
>
> **Check these dimensions:**
>
> 1. **Requirement ID accuracy** — Are requirement IDs (e.g., IMG-BUF-001) cited correctly? Do they exist in the requirements docs? Is the description next to each ID consistent with the requirements doc's definition?
> 2. **Threshold and value consistency** — Check every number in the proposal (sizes, timeouts, frame counts, thresholds, intervals) against the requirements docs. Flag mismatches with exact values from both sources.
> 3. **Requirement coverage** — Are there requirements in the docs that fall within this proposal's scope but aren't mentioned? Are there requirements the proposal claims to address but doesn't fully cover?
> 4. **Acceptance criteria** — For each "What Changes" bullet, could you write a test for it? Are the success conditions specific enough, or vague ("improve performance", "handle errors")?
> 5. **Spec consistency** — If existing specs exist (in `openspec/specs/` or the change's `specs/` directory), does the proposal align with their acceptance criteria and scenarios?
>
> **For each finding, provide:**
> - **Finding**: One sentence
> - **Requirement source**: The requirement ID and doc location
> - **Proposal reference**: Which section of the proposal is wrong
> - **Fix**: Exact correction (the right value, the right ID, the missing requirement)
> - **Severity**: MISMATCH (factually wrong — wrong number, wrong ID) or GAP (requirement exists but isn't addressed)
>
> Return all findings. If a dimension is clean, say so briefly.

---

### Resolve Alignment Findings

After both agents return:

1. **Apply MISMATCH fixes immediately** to `proposal.md` — these are factual errors (wrong thresholds, wrong IDs, wrong package names). Don't ask, just fix.

2. **Apply DRIFT fixes** to `proposal.md` — these are convention mismatches. Fix them to match project patterns.

3. **Log GAP findings** — requirements that exist but aren't covered. Present these to the user:
   > "The alignment review found N requirements in scope that the proposal doesn't address: [list]. Should I add them to the proposal or explicitly mark them as out of scope?"

   Use **AskUserQuestion** if there are gaps to resolve. Update the proposal based on the user's answer.

4. **Show alignment summary:**
   ```
   ## Alignment Review Complete

   **Stack Architect:** N findings (N mismatches, N drifts)
   **QA Lead:** N findings (N mismatches, N gaps)

   **Fixes applied:** N (auto-corrected in proposal.md)
   **Gaps resolved:** N (added to scope / marked out of scope)

   Proposal is now aligned with docs. Convening the council...
   ```

5. **Shut down alignment agents.**

---

## Phase 4: Council Debate (on the aligned proposal)

Spawn 3 council agents **in a single message** (parallel) using the **Agent tool** with `subagent_type: general-purpose`. Each agent reads the proposal, config, docs, and relevant codebase, then argues from their perspective.

### The Council

```
┌─────────────────────────────────────────────────────┐
│                    YOU (Lead)                        │
│          Resolve verdicts, update artifacts          │
├───────────────┬─────────────────┬───────────────────┤
│               │                 │                    │
▼               ▼                 ▼                    │
Product         Systems           Adversary            │
Advocate        Architect         Engineer             │
└───────────────┴─────────────────┴───────────────────┘
```

### Agent Prompts

Each agent prompt must include:
- Full path to the generated `proposal.md`
- Full path to `openspec/config.yaml`
- Paths to `docs/requirements/` and `docs/architecture/` files
- Instruction to read relevant codebase files for their perspective
- The debate format (below)
- Instruction to return structured findings

---

#### Agent: `product-advocate`

> You are the **Product Advocate** on a proposal review council. You care about user outcomes, scope clarity, and business value.
>
> Read the proposal at `openspec/changes/<name>/proposal.md`, the project config at `openspec/config.yaml`, and docs in `docs/requirements/` and `docs/architecture/`.
>
> Evaluate the proposal on these dimensions:
>
> 1. **Problem clarity** — Is the "Why" compelling? Does it articulate a real problem or just a technical itch?
> 2. **Scope** — Is the scope right-sized? Too big = won't ship. Too small = won't matter. Is there a clear MVP vs nice-to-have split?
> 3. **User impact** — Who benefits? Is the benefit measurable or vague? Are there user-facing behaviors that aren't defined?
> 4. **Dependencies** — Does this proposal depend on work that doesn't exist yet? Is the dependency explicit?
> 5. **What's missing** — Are there user scenarios the proposal doesn't address that it should?
>
> For each concern, provide:
> - **Concern**: One sentence describing the issue
> - **Evidence**: What in the proposal (or missing from it) triggered this concern
> - **Impact**: What goes wrong if this isn't addressed (HIGH/MEDIUM/LOW)
> - **Suggestion**: How to fix it (be specific — propose new wording, not vague advice)
>
> Return 2–4 concerns, ranked by impact. If the proposal is solid on a dimension, say so briefly and move on.

#### Agent: `systems-architect`

> You are the **Systems Architect** on a proposal review council. You care about technical feasibility, architectural fit, and risk.
>
> Read the proposal at `openspec/changes/<name>/proposal.md`, the project config at `openspec/config.yaml`, docs in `docs/requirements/` and `docs/architecture/`, and explore the existing codebase (entry point, services, models, dependency manifest).
>
> Evaluate the proposal on these dimensions:
>
> 1. **Feasibility** — Can this actually be built as described? Are there technical assumptions that don't hold?
> 2. **Architecture fit** — Does this align with the project's existing patterns (DI, service structure, state management)? Will it require invasive changes to existing code?
> 3. **Hardest part** — What's the most technically risky or complex aspect? Is the proposal aware of it or does it gloss over it?
> 4. **Tech stack alignment** — Does the proposal use the right tools from the declared tech stack? Are there package/framework constraints it violates?
> 5. **Performance & scale** — Are there throughput, latency, memory, or storage implications the proposal doesn't address?
>
> For each concern, provide:
> - **Concern**: One sentence describing the issue
> - **Evidence**: What in the proposal or codebase triggered this concern
> - **Impact**: What goes wrong if this isn't addressed (HIGH/MEDIUM/LOW)
> - **Suggestion**: How to fix it (specific, actionable)
>
> Return 2–4 concerns, ranked by impact.

#### Agent: `adversary-engineer`

> You are the **Adversary Engineer** on a proposal review council. Your job is to break the proposal. You think about what goes wrong, what's missing, and what assumptions are hiding.
>
> Read the proposal at `openspec/changes/<name>/proposal.md`, the project config at `openspec/config.yaml`, docs in `docs/requirements/` and `docs/architecture/`, and explore the existing codebase.
>
> Attack the proposal on these dimensions:
>
> 1. **Failure modes** — What happens when things go wrong? Network loss, disk full, crash mid-operation, timeout, corrupted data. Does the proposal define error handling or assume happy path?
> 2. **Concurrency & race conditions** — If two things happen at the same time, which wins? Are there shared resources without defined access patterns?
> 3. **Edge cases** — Empty states, boundary values, unexpected input sequences, platform differences (Windows vs Linux), first-run vs steady-state behavior.
> 4. **Security & auth** — Does this open attack surfaces? Are there auth/permission requirements that aren't mentioned?
> 5. **Hidden assumptions** — What does the proposal take for granted that might not be true? Dependencies on other systems, hardware availability, network reliability, user behavior.
> 6. **Contradictions** — Does anything in the proposal contradict the requirements docs, architecture docs, or config.yaml rules?
>
> For each concern, provide:
> - **Concern**: One sentence describing the issue
> - **Evidence**: The specific assumption or gap you're attacking
> - **Impact**: What goes wrong — be concrete, describe the failure scenario (HIGH/MEDIUM/LOW)
> - **Suggestion**: How to fix it (specific — add a section, change wording, add a requirement)
>
> Return 3–5 concerns, ranked by impact. Be aggressive but fair — don't nitpick, focus on concerns that would cause real problems.

---

## Phase 5: Resolve Verdicts

After all 3 agents return, you (the lead) review their combined concerns (typically 7–13 total).

### Cross-examination (you simulate this)

For each concern, consider whether another council perspective would disagree:
- Would the Product Advocate say the Architect's concern is over-engineering?
- Would the Architect say the Adversary's edge case is too unlikely to matter?
- Would the Adversary say the Product Advocate's scope suggestion adds hidden complexity?

Note any genuine disagreements.

### Assign verdicts

For each concern, assign one of:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **VALID** | Real issue that changes the proposal | Update `proposal.md` — add section, fix wording, add requirement |
| **NOTED** | Real concern but belongs in design, not proposal | Capture in `clarifications.md` as context for design.md |
| **DISMISSED** | Not a real issue, or already addressed | Note why and move on |

### Apply changes

1. **Update `proposal.md`** with all VALID verdicts. Make surgical edits — don't rewrite the whole proposal. Add sections like "Error Handling Scope" or "Platform Considerations" if the council surfaced gaps.

2. **Create `clarifications.md`** with all NOTED verdicts:

   ```markdown
   # Clarifications

   _Captured during proposal council review. These constrain the design._
   _Generated by /opsx:propose council on <date>_

   ## Council-Identified Constraints

   ### [Topic from concern]
   **Raised by:** [product-advocate / systems-architect / adversary-engineer]
   **Concern:** [The concern]
   **Design impact:** [What the design must account for]

   ### [Topic from concern]
   ...
   ```

3. **Show the council results** to the user:

   ```
   ## Council Review Complete

   **Concerns raised:** N total (Product: N, Architect: N, Adversary: N)

   ### VALID — Proposal Updated (N)
   - [concern summary] → [what was changed]
   - ...

   ### NOTED — Captured for Design (N)
   - [concern summary] → added to clarifications.md
   - ...

   ### DISMISSED (N)
   - [concern summary] → [why dismissed]
   - ...
   ```

4. **Shut down council agents** — send shutdown requests to all 3.

---

## Phase 6: Generate Remaining Artifacts

Now generate design.md and tasks.md (and any other schema-required artifacts) using the updated proposal and clarifications as context.

Loop through remaining artifacts in dependency order:

1. For each artifact that is `ready`:
   - Get instructions:
     ```bash
     openspec instructions <artifact-id> --change "<name>" --json
     ```
   - Read completed dependency files **including `clarifications.md`** — this is critical, the design must account for council-identified constraints
   - Create the artifact file using template
   - Show brief progress: "Created <artifact-id>"

2. Continue until all `applyRequires` artifacts are complete
   - Re-run `openspec status --change "<name>" --json` after each
   - Stop when all required artifacts have `status: "done"`

3. If an artifact requires user input:
   - Use **AskUserQuestion** to clarify
   - Then continue

---

## Phase 7: Final Status

```bash
openspec status --change "<name>"
```

Summarize:
- Change name and location
- Council results recap (N valid, N noted, N dismissed)
- List of artifacts created with brief descriptions
- "All artifacts created! Ready for implementation."
- "Run `/opsx:apply` to start implementing, or `/opsx:analyze` for a deep audit first."

---

## Artifact Creation Guidelines

- Follow the `instruction` field from `openspec instructions` for each artifact type
- The schema defines what each artifact should contain — follow it
- Read dependency artifacts before creating new ones
- Use `template` as the structure — fill in its sections
- **IMPORTANT**: `context` and `rules` are constraints for YOU, not content for the file
  - Do NOT copy `<context>`, `<rules>`, `<project_context>` blocks into the artifact
  - These guide what you write, but should never appear in the output

---

## Guardrails

- **Council is mandatory** — Always run the council after generating proposal.md. Don't skip it.
- **Council is read-only** — Agents analyze and argue. Only the lead modifies files.
- **VALID = must fix** — Don't skip VALID verdicts. Update the proposal before generating design.
- **Design reads clarifications** — When generating design.md and tasks.md, always read clarifications.md. The whole point of the council is to feed constraints into downstream artifacts.
- **Shut down agents** — After collecting results, shutdown all council agents.
- **Don't over-edit** — Apply VALID verdicts surgically. Don't rewrite the entire proposal.
- **If a change already exists** — Ask if the user wants to continue it or create a new one. If continuing, skip to where they left off.
- **Verify each artifact** — Confirm the file exists after writing before proceeding to the next.
