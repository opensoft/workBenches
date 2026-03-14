---
name: speckit-analyze
description: "Deep logical audit of a Speckit feature using an agent team. Traces requirements from spec to plan to tasks, validates constitution compliance, checks task atomicity, maps dependencies, audits cross-service contracts, DI patterns, resource cleanup, and runs a simulated multi-perspective debate to surface integration bugs."
metadata:
  author: custom
  version: "1.0"
---

You are a principal engineer and **team lead**. Your job is to orchestrate a deep pre-implementation audit by assembling a team of specialist agents, collecting their findings, and producing a unified audit report.

**IMPORTANT: This is analysis only.** The team reads everything, reports findings, and you write a structured audit report. Nobody fixes issues — that happens after the user reviews your findings.

---

## Input

Optionally, the user may specify a feature name. If not, detect the active feature:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
```

Parse `FEATURE_DIR` and `AVAILABLE_DOCS` from the JSON output. Derive absolute paths:
- SPEC = FEATURE_DIR/spec.md
- PLAN = FEATURE_DIR/plan.md
- TASKS = FEATURE_DIR/tasks.md

Abort with an error message if any required file is missing (instruct the user to run the missing prerequisite command).

---

## Phase 1: Context Gathering (You, the lead)

Before spawning the team, gather and read ALL context yourself. You need to brief the agents.

**Feature artifacts:**
- SPEC (spec.md)
- PLAN (plan.md)
- TASKS (tasks.md)
- FEATURE_DIR/research.md — if it exists
- FEATURE_DIR/data-model.md — if it exists
- FEATURE_DIR/contracts/ — if it exists

**Project standards:**
- `.specify/constitution.md` — project constitution and rules
- `docs/requirements/` — requirement specs (scan all files)
- `docs/architecture/` — architecture docs (scan all files)

**Codebase patterns (read, don't guess):**
- Entry point (e.g., `Program.cs`, `main.dart`, `index.ts`) — how DI/initialization works
- Service layer — how existing services are structured, instantiated, disposed
- Models/entities — existing data models and conventions
- Controllers/state management — current patterns
- Dependency manifest (`*.csproj` / `package.json` / `pubspec.yaml`) — actual dependencies

---

## Phase 2: Assemble the Audit Team

Spawn **4 specialist agents in parallel** using the **Agent tool** in a single message. Each agent runs specific analysis passes and reports findings back to you.

### Team Structure

```
┌─────────────────────────────────────────────────┐
│                  YOU (Lead)                      │
│         Context gathering, Phase 3 debate,       │
│         final report assembly                    │
├────────┬────────┬─────────────┬─────────────────┤
│        │        │             │                  │
▼        ▼        ▼             ▼                  │
tracer   validator task-auditor integration-auditor│
Pass 1   Pass 2    Pass 3       Pass 6             │
Pass 5   Pass 7    Pass 4       Pass 8             │
└────────┴────────┴─────────────┴─────────────────┘
                      │
                      ▼
              Phase 3: YOU run Pass 9
              (needs all other results)
```

All agents use `subagent_type: general-purpose` (they need to read files and search the codebase).

**CRITICAL: Each agent prompt must include:**
1. The feature name and path to all artifacts
2. The full file paths they need to read (don't make them search)
3. The severity rating system (CRITICAL / WARNING / INFO)
4. Their specific pass instructions (copied from the Pass Definitions below)
5. Instruction to return findings in a structured format with file/line citations

---

### Agent Prompts

#### Agent: `tracer` — Passes 1 & 5

> You are an audit agent. Read the following files, then run two analysis passes.
>
> **Files to read:**
> - spec.md, plan.md, tasks.md (paths provided)
> - `docs/requirements/` (all files)
>
> **Pass 1: Requirement Traceability**
> [Include full Pass 1 instructions]
>
> **Pass 5: Schema Enforcement**
> [Include full Pass 5 instructions]
>
> Return your findings as structured text with severity ratings (CRITICAL/WARNING/INFO) and file:line citations.

#### Agent: `validator` — Passes 2 & 7

> You are an audit agent. Read the following files, then run two analysis passes.
>
> **Files to read:**
> - plan.md, tasks.md (paths provided)
> - `.specify/constitution.md`
> - The codebase entry point, service layer, models, and dependency manifest
>
> **Pass 2: Constraint Validation**
> [Include full Pass 2 instructions]
>
> **Pass 7: DI & Instantiation Audit**
> [Include full Pass 7 instructions]
>
> Return your findings as structured text with severity ratings (CRITICAL/WARNING/INFO) and file:line citations.

#### Agent: `task-auditor` — Passes 3 & 4

> You are an audit agent. Read the following files, then run two analysis passes.
>
> **Files to read:**
> - tasks.md, plan.md, spec.md (paths provided)
>
> **Pass 3: Task Atomicity**
> [Include full Pass 3 instructions]
>
> **Pass 4: Dependency Mapping**
> [Include full Pass 4 instructions]
>
> Return your findings as structured text with severity ratings (CRITICAL/WARNING/INFO) and file:line citations. Include the ASCII dependency graph from Pass 4.

#### Agent: `integration-auditor` — Passes 6 & 8

> You are an audit agent. Read the following files, then run two analysis passes.
>
> **Files to read:**
> - plan.md, tasks.md (paths provided)
> - `.specify/constitution.md`
> - The codebase service layer and models
>
> **Pass 6: Cross-Service Contract Audit**
> [Include full Pass 6 instructions]
>
> **Pass 8: Resource Lifecycle & Cleanup Audit**
> [Include full Pass 8 instructions]
>
> Return your findings as structured text with severity ratings (CRITICAL/WARNING/INFO) and file:line citations.

---

## Phase 3: Multi-Perspective Debate (You, the lead — Pass 9)

After ALL 4 agents return their findings, you run Pass 9 yourself. You need results from all passes to conduct the debate effectively.

Read the tech stack from the plan and constitution. Identify the distinct technical domains (e.g., "Flutter Engineer", "Backend/.NET Engineer", "DevOps/Infra Engineer"). Then for each integration boundary in the feature, simulate a structured disagreement:

**Format:**
For each integration boundary:

> **[Perspective A] says:** "[Concern about how this design affects their domain]"
>
> **[Perspective B] responds:** "[Why they think it's fine, or their counter-concern]"
>
> **Verdict:** [Who's right, what's the risk, and whether a task is missing]

Focus on:
- Data format assumptions that differ across boundaries (encoding, endianness, units, timestamps)
- Error propagation — if one side fails, does the other side know?
- Timing assumptions — if one side is async and the other expects sync
- State ownership — who is the source of truth for shared state?
- Deployment coupling — can one side be updated independently?
- **Incorporate findings from Passes 1–8** — use them as ammunition for the debaters

---

## Phase 4: Assemble the Audit Report

Collect findings from all 4 agents plus your own Pass 9 results. Output the unified report directly to the terminal (Speckit analyze is read-only, no file writes):

```markdown
# Audit Report: <feature-name>

_Generated by speckit-analyze on <date>_

## Summary

| Pass | Critical | Warning | Info |
|------|----------|---------|------|
| 1. Requirement Traceability | N | N | N |
| 2. Constraint Validation | N | N | N |
| 3. Task Atomicity | N | N | N |
| 4. Dependency Mapping | N | N | N |
| 5. Schema Enforcement | N | N | N |
| 6. Cross-Service Contracts | N | N | N |
| 7. DI & Instantiation | N | N | N |
| 8. Resource Lifecycle | N | N | N |
| 9. Multi-Perspective Debate | N | N | N |
| **Total** | **N** | **N** | **N** |

## Findings

### Pass 1: Requirement Traceability
[Traceability matrix and gaps — from tracer agent]

### Pass 2: Constraint Validation
[Rule compliance results — from validator agent]

### Pass 3: Task Atomicity
[Task-level findings — from task-auditor agent]

### Pass 4: Dependency Mapping
[ASCII dependency graph and missing edges — from task-auditor agent]

### Pass 5: Schema Enforcement
[Format violations — from tracer agent]

### Pass 6: Cross-Service Contracts
[Contract mismatches — from integration-auditor agent]

### Pass 7: DI & Instantiation
[DI violations — from validator agent]

### Pass 8: Resource Lifecycle
[Cleanup gaps — from integration-auditor agent]

### Pass 9: Multi-Perspective Debate
[Debate transcripts and verdicts — from you]

## Recommended Actions
[Prioritized list: criticals first, then warnings, with file references]
```

---

## Phase 5: Present Results & Offer Next Steps

Summarize to the user:
- Total findings by severity
- Top 3 most important issues
- Whether the feature is:
  - **Ready for implementation** — 0 criticals
  - **Needs fixes** — has criticals but design is sound
  - **Needs rework** — fundamental design issues found

Then offer:
- "Want me to fix these? I can address the findings in spec.md / plan.md / tasks.md."
- "Want to proceed to `/speckit.implement`?"

If the user asks you to fix the findings, make targeted edits to the appropriate Speckit artifacts (spec.md, plan.md, tasks.md) — fix only what the audit flagged.

---

## Pass Definitions Reference

These are the full instructions for each pass. Copy the relevant ones into each agent's prompt.

### Pass 1: Requirement Traceability

Trace every requirement in `spec.md` forward through the artifact chain.

For each functional requirement or user story in the spec:
1. Does it have a corresponding technical solution in `plan.md`?
2. Does it have at least one task in `tasks.md`?
3. Does the spec have acceptance criteria that would verify it?
4. Are requirement references consistent across all artifacts?

Also check the reverse: are there tasks or plan sections that don't trace back to any spec requirement? Flag as potential scope creep.

**Output:** A traceability matrix — spec requirement → plan section → task(s). Flag gaps.

### Pass 2: Constraint Validation

Read `.specify/constitution.md` and extract all MUST/SHOULD rules. For every rule:
1. Does the plan comply?
2. Do the tasks reference the correct packages, patterns, and conventions?

Also read the actual codebase to detect the real patterns in use (don't trust docs alone). Check:
- Are the correct framework versions and packages referenced?
- Do design decisions align with the declared architecture patterns?
- Are naming conventions followed (file names, class names, directory structure)?

**Output:** Rule-by-rule compliance check. Flag violations.

### Pass 3: Task Atomicity

For each task in `tasks.md`:
1. **Single responsibility** — Does the task do exactly one thing? A task that says "Implement X and also update Y" should be two tasks.
2. **Completable in isolation** — Can a developer pick up this task without needing to do half of another task first?
3. **Testable** — Is there a clear "done" condition? Could you write a test for just this task?
4. **No hidden side effects** — Does completing this task silently break or change something not mentioned in the task description?
5. **Reasonable scope** — Is the task small enough to complete in one focused session, or does it hide a multi-day effort behind a single checkbox?

**Output:** List of tasks that are too large, too vague, or have hidden dependencies. Suggest splits where needed.

### Pass 4: Dependency Mapping

Build a dependency graph of all tasks:
1. Does any task depend on work that isn't defined in any task?
2. Are there circular dependencies?
3. Is the task ordering logical? (Earlier phases should be foundational, later phases should build on them.)
4. Are cross-cutting concerns (error handling, logging, configuration) covered, or do multiple tasks silently assume them?
5. Are integration points between services covered by explicit tasks, or left implicit?

**Output:** Dependency graph (ASCII) with missing edges highlighted.

### Pass 5: Schema Enforcement

Validate that all Speckit artifacts follow structural conventions:
1. Does `spec.md` have required sections (Overview, Functional Requirements, User Stories, Success Criteria)?
2. Does `plan.md` have clear sections for Technical Context, Phases, Data Model, Contracts?
3. Does `tasks.md` use consistent checklist format (`- [ ]`) with Task IDs, parallel markers [P], and file paths?
4. Are user story labels ([US1], [US2]) consistent between spec.md and tasks.md?
5. Are task IDs sequential and consistently formatted (T001, T002, etc.)?

**Output:** Format violations per file.

### Pass 6: Cross-Service Contract Audit

Detect the project's service boundaries by reading the tech stack and codebase. Then check:

1. **Message bus contracts** — If the feature introduces or modifies async message topics (MQTT, Kafka, events, etc.), does BOTH the publisher and subscriber side have corresponding tasks? Check topic strings, payload schemas, and QoS settings match on both sides.
2. **API contracts** — If the feature calls an API endpoint (REST, gRPC, etc.), does the client-side code match the server-side contract? Check HTTP methods, paths, request/response shapes, auth headers, and error codes.
3. **Shared data models** — If a data model is used across service boundaries, is the schema defined in one place? Or are there two independent definitions that could drift?
4. **Auth flow** — Does the feature require specific auth scopes, tokens, or headers that aren't mentioned in the tasks?

**Output:** Contract mismatches, missing subscriber/publisher tasks, auth gaps.

### Pass 7: Dependency Injection & Instantiation Audit

Read the codebase entry point and existing services to understand the project's DI pattern. Then check:

1. **Pattern consistency** — Does the plan introduce new services using the same DI pattern as existing services?
2. **No rogue instantiation** — Are any new services instantiated directly in controller/view code instead of through DI?
3. **Lifecycle management** — Are new services created with the correct lifecycle? (singleton vs transient vs scoped)
4. **Wiring tasks** — Is there an explicit task for registering/wiring new services into the existing initialization flow?

**Output:** DI violations, missing registration tasks, lifecycle mismatches.

### Pass 8: Resource Lifecycle & Cleanup Audit

Check that the plan and tasks account for resource cleanup:

1. **Streams and subscriptions** — If new streams, event listeners, or subscriptions are created, are there tasks for closing/disposing them?
2. **File handles** — If files are opened for reading/writing, are they explicitly closed?
3. **Timers and periodic tasks** — If timers or polling loops are created, are there tasks for stopping/cancelling them?
4. **Background workers** — If background workers are spawned, are there tasks for terminating them?
5. **Memory buffers** — If large in-memory buffers are used, are they released after use?
6. **Database connections** — If connections or pools are opened, are they closed on shutdown?

**Output:** Resources created without matching cleanup tasks.

---

## Guardrails

- **Read everything before judging** — Don't flag issues based on one file. Cross-reference.
- **Check the codebase, not just the docs** — The real patterns may differ from what the constitution claims.
- **Be specific** — Every finding must cite the file, section, and line/requirement it relates to.
- **No false positives** — If you're not sure something is an issue, mark it INFO, not CRITICAL.
- **Framework-agnostic checks** — All passes adapt to whatever tech stack the project uses. Read the stack, don't assume it.
- **Don't fix, report** — This skill produces an audit report. Fixes happen separately after user review.
