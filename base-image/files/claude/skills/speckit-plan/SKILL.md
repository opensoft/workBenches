---
name: speckit-plan
description: "Generate a Speckit implementation plan using parallel research agents. Three specialists explore the codebase simultaneously (domain, infrastructure, patterns), then the lead synthesizes their findings into plan.md with full architectural context."
metadata:
  author: custom
  version: "1.0"
---

You are a **team lead** orchestrating implementation planning. You assemble a team of three research agents who explore the codebase in parallel from different perspectives, then you synthesize their findings into a comprehensive plan.

**IMPORTANT: This is a planning step, not implementation.** The team researches the codebase. You write plan.md. Nobody writes application code — that happens in `/speckit.implement` after planning is complete.

---

## Input

Optionally, the user may provide technical constraints (e.g., "use Tailwind", "add a new API route"). If not, detect the active feature:

```bash
.specify/scripts/bash/setup-plan.sh --json
```

Parse `FEATURE_SPEC`, `IMPL_PLAN`, `SPECS_DIR`, `BRANCH` from the JSON output.

---

## Phase 1: Context Gathering (You, the lead)

Read ALL of these before spawning agents:

**Feature artifacts:**
- `FEATURE_SPEC` (spec.md) — the specification to plan for
- Check for a Clarifications section — these constrain the design

**Project standards:**
- `.specify/constitution.md` — project constitution and rules
- `.specify/templates/plan-template.md` — plan template (already copied to IMPL_PLAN)
- `docs/requirements/` — requirement specs (scan all files)
- `docs/architecture/` — architecture docs (scan all files)

**User-provided constraints:**
- Any technical constraints from the user's input (tech stack choices, pattern preferences)

---

## Phase 2: Assemble the Research Team

Spawn **3 specialist research agents in parallel** using the **Agent tool** in a single message. Each agent explores the codebase from their perspective and returns structured findings.

### Team Structure

```
┌──────────────────────────────────────────────────┐
│                   YOU (Lead)                      │
│    Context gathering, plan synthesis,             │
│    constitution compliance, artifact generation   │
├───────────┬────────────────┬─────────────────────┤
│           │                │                      │
▼           ▼                ▼                      │
domain      infrastructure   pattern                │
researcher  researcher       researcher             │
└───────────┴────────────────┴─────────────────────┘
```

All agents use `subagent_type: general-purpose` (they need to read files and search the codebase).

**CRITICAL: Each agent prompt must include:**
1. The feature name and full path to spec.md
2. Paths to constitution, requirements docs, architecture docs
3. Their specific research focus (from the Agent Definitions below)
4. Instruction to return structured findings with file paths and line references

---

### Agent Definitions

#### Agent: `domain-researcher`

Focus: **Domain model & data layer**. Explores existing entities, relationships, value objects, and database configuration relevant to this feature.

Research tasks:
- **Existing entities** — Find all domain entities related to the feature's scope. Read their full definitions: fields, constructors, validation rules, state transitions, navigation properties.
- **Entity configurations** — Find EF Core (or equivalent ORM) configurations for these entities. Read: table names, column constraints, indexes, relationships, shadow properties.
- **Value objects & enums** — Find any value objects, enums, or constants used by these entities.
- **Migrations** — Check the most recent migrations to understand the current schema state.
- **Domain services** — Find domain services or entity methods that encapsulate business rules relevant to this feature.

**Output format:**
```
## Domain Research: <feature-name>

### Existing Entities
- [Entity]: [file path] — [brief description, key fields, relationships]

### Entity Configurations
- [Entity]: [file path] — [table, key indexes, constraints]

### Value Objects & Enums
- [Name]: [file path] — [values/fields]

### Schema State
- Latest migration: [name] — [what it does]

### Domain Rules
- [Rule]: [file:line] — [description]

### Gaps
- [What's missing for this feature to work]
```

#### Agent: `infrastructure-researcher`

Focus: **Service layer, DI, and infrastructure patterns**. Explores how existing services are structured, registered, and wired for features similar to this one.

Research tasks:
- **Existing services** — Find application services and infrastructure services related to this feature's scope. Read their interfaces and implementations: method signatures, dependencies, return types.
- **DI registration** — Find how these services are registered in the DI container (Program.cs, Startup, or module files). Note lifecycle (singleton, scoped, transient).
- **Background workers** — If the feature involves async processing, find existing workers: how they're structured, how they receive work (channels, queues), how they handle errors.
- **External integrations** — If the feature touches external services (blob storage, message bus, auth), find the existing adapter/client implementations and their configuration.
- **Configuration options** — Find Options classes relevant to this feature. Read their defaults and how they're bound.

**Output format:**
```
## Infrastructure Research: <feature-name>

### Existing Services
- [Service]: [file path] — [methods, dependencies, lifecycle]

### DI Registration
- [Service]: [registration file:line] — [lifecycle, how registered]

### Background Workers
- [Worker]: [file path] — [trigger mechanism, error handling]

### External Integrations
- [Integration]: [file path] — [adapter pattern, configuration]

### Configuration
- [Options class]: [file path] — [key settings, defaults]

### Gaps
- [What's missing for this feature to work]
```

#### Agent: `pattern-researcher`

Focus: **Analogous features & conventions**. Finds how the codebase already implements features similar to this one, so the plan can follow established patterns.

Research tasks:
- **Analogous features** — Find the most similar existing feature to the one being planned. Trace its full stack: controller → service → domain → infrastructure → database. Document the pattern.
- **Controller conventions** — How are controllers structured? Auth attributes, validation patterns, response types, error handling, route conventions.
- **Validation patterns** — How is input validation done? FluentValidation, data annotations, manual? Find examples.
- **Error handling** — How are business rule violations surfaced? ProblemDetails, custom exceptions, result types?
- **Testing patterns** — If tests exist, how are they structured? Test project layout, naming conventions, test helpers, integration test infrastructure.
- **Naming conventions** — File naming, class naming, method naming patterns for each layer.

**Output format:**
```
## Pattern Research: <feature-name>

### Closest Analogous Feature
- [Feature]: Full stack trace with file paths

### Controller Pattern
- [Convention]: [example file:line]

### Validation Pattern
- [Convention]: [example file:line]

### Error Handling
- [Pattern]: [example file:line]

### Testing Pattern
- [Convention]: [example file:line]

### Naming Conventions
- [Layer]: [convention with examples]

### Recommendations
- [Follow pattern X for this feature because...]
```

---

## Phase 3: Synthesize the Plan (You, the lead)

After all 3 agents return, you have comprehensive codebase context. Now write the plan.

### Step 1: Constitution Check

Read `.specify/constitution.md` and evaluate the feature against each principle:
- Fill the Constitution Check section in the plan template
- Flag any gate failures — ERROR if violations are unjustified

### Step 2: Technical Context

Using the research findings, fill the Technical Context section:
- Tech stack (from constitution + codebase)
- Dependencies (from infrastructure researcher)
- Integration points (from infrastructure researcher)
- Mark any remaining unknowns as "NEEDS CLARIFICATION"

### Step 3: Phase 0 — Research Resolution

If any NEEDS CLARIFICATION items remain:
- Check if the research agents already answered them
- If not, resolve by reading additional codebase files
- Consolidate findings in `research.md`

### Step 4: Phase 1 — Design & Contracts

Using all three research reports:
- **Data model** (from domain researcher) → `data-model.md`
  - New entities, fields, relationships
  - Validation rules from spec requirements
  - State transitions if applicable
  - Follow existing entity patterns (from pattern researcher)
- **API contracts** (from pattern researcher conventions) → `contracts/`
  - For each user action → endpoint
  - Follow existing controller patterns
  - Match existing validation and error handling patterns
- **Quickstart** → `quickstart.md`
  - Integration scenarios from spec
- **Agent context update** — run `.specify/scripts/bash/update-agent-context.sh codex` if available

### Step 5: Write plan.md

Write the complete plan to `IMPL_PLAN` using the template structure. The plan must:
- Reference specific existing files and patterns (from research)
- Follow the project's established conventions (from pattern researcher)
- Account for existing infrastructure (from infrastructure researcher)
- Build on the existing domain model (from domain researcher)
- Comply with the constitution

---

## Phase 4: Report

Summarize to the user:

```
## Planning Complete

**Feature:** <feature-name>
**Branch:** <branch-name>
**Plan:** <path to plan.md>

### Research Summary
- **Domain:** N entities examined, N gaps identified
- **Infrastructure:** N services examined, N integration points mapped
- **Patterns:** Closest analogue: <feature-name> — following its stack pattern

### Artifacts Generated
- plan.md — Implementation plan with constitution check
- research.md — Research findings and decisions
- data-model.md — Entity definitions (if data involved)
- contracts/ — API specifications (if endpoints involved)

### Constitution Check
- [PASS/FAIL for each principle]

**Next step:** Run `/speckit.tasks` to generate the task breakdown.
```

---

## Guardrails

- **Research, then plan** — Don't write the plan without research findings. The agents provide grounded context.
- **Read-only on codebase** — You and the agents may read any file. Do NOT write application code.
- **You MAY write** plan.md, research.md, data-model.md, contracts/ — those are Speckit artifacts, not implementation.
- **Follow existing patterns** — The plan should prescribe patterns the codebase already uses, not introduce new ones without justification.
- **Constitution is non-negotiable** — If the plan would violate a MUST rule, ERROR and require explicit justification.
- **Be specific** — Reference exact file paths and patterns. "Follow the existing pattern" is not specific enough — say "Follow the pattern in DeviceCaptureController.cs:L15-L45".
- **Framework-agnostic** — Agent research dimensions adapt to whatever tech stack the project uses.
