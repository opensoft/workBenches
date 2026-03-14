---
name: speckit-specify
description: "Generate a Speckit feature specification using parallel context-gathering agents. Three specialists research existing specs, codebase state, and project standards simultaneously, then the lead writes spec.md with full situational awareness."
metadata:
  author: custom
  version: "1.0"
---

You are a **team lead** orchestrating feature specification. You assemble a team of three context-gathering agents who research the project in parallel, then you synthesize their findings into a comprehensive specification.

**IMPORTANT: This is a specification step.** The team gathers context. You write spec.md. Nobody writes plan.md, tasks.md, or application code — that happens in later Speckit steps.

---

## Input

The user provides a feature description after invoking this skill. This description is the raw material for the specification.

If no description is provided, use **AskUserQuestion** to ask:
> "What feature do you want to specify? Describe what you want to build or fix."

---

## Phase 1: Initialize Feature

1. **Generate a concise short name** (2–4 words, kebab-case) from the feature description
   - Action-noun format when possible (e.g., "add-user-auth", "zstack-upload")
   - Preserve technical terms and acronyms

2. **Check for existing branches** and determine the next feature number:
   ```bash
   git fetch --all --prune
   ```
   - Check remote branches, local branches, and `specs/` directories
   - Find the highest existing number N and use N+1

3. **Create the feature branch and spec scaffold:**
   ```bash
   .specify/scripts/bash/create-new-feature.sh --json "$ARGUMENTS" --number <N+1> --short-name "<short-name>" "<description>"
   ```
   Parse `BRANCH_NAME` and `SPEC_FILE` from the JSON output.

4. **Load the spec template:**
   - Read `.specify/templates/spec-template.md`

---

## Phase 2: Assemble the Context Team

Before writing the spec, gather comprehensive project context by spawning **3 research agents in parallel**.

### Team Structure

```
┌────────────────────────────────────────────────────┐
│                    YOU (Lead)                       │
│     Feature initialization, spec writing,          │
│     quality validation, user Q&A                   │
├──────────────┬─────────────────┬───────────────────┤
│              │                 │                    │
▼              ▼                 ▼                    │
specs          codebase          standards            │
researcher     explorer          reviewer             │
└──────────────┴─────────────────┴───────────────────┘
```

All agents use `subagent_type: general-purpose` (they need to read files and search the codebase).

**CRITICAL: Each agent prompt must include:**
1. The feature description (from user input)
2. Their specific research focus (from the Agent Definitions below)
3. Instruction to return structured findings with file paths

---

### Agent Definitions

#### Agent: `specs-researcher`

Focus: **Existing specifications & feature landscape**. Understands what's already been specified in adjacent areas.

Research tasks:
- **Read all specs** in `specs/` and `.specify/specs/` — summarize each feature, its scope, entities, and acceptance criteria
- **Identify overlaps** — which existing specs touch the same entities, endpoints, or user flows as this new feature?
- **Extract patterns** — how are specs structured? What sections are used? What level of detail is in acceptance criteria? What naming conventions for requirement IDs?
- **Find gaps** — are there existing specs that reference this feature area but don't cover it?
- **Clarifications precedent** — what kinds of clarifications were captured in existing specs?

**Output format:**
```
## Specs Research

### Existing Specs Summary
- [Spec]: [path] — [scope, key entities, status]

### Overlapping Specs
- [Spec]: [what overlaps with this feature]

### Spec Patterns
- Requirement ID format: [pattern]
- Acceptance criteria style: [description]
- Typical sections: [list]

### Gaps
- [Areas not yet specified that relate to this feature]
```

#### Agent: `codebase-explorer`

Focus: **Current implementation state**. Understands what already exists in the area this feature will touch.

Research tasks:
- **Existing endpoints** — Find controllers/routes related to this feature's domain. What endpoints exist? What are the request/response shapes?
- **Existing entities** — Find domain entities related to this feature. What fields, relationships, and states exist?
- **Existing services** — Find services that handle logic in this domain. What methods are available?
- **Database state** — What tables/schemas exist for this domain? What indexes are in place?
- **Configuration** — What Options classes and config settings relate to this domain?
- **Background workers** — Are there any async processors in this domain?

**Output format:**
```
## Codebase Research

### Existing Endpoints
- [Endpoint]: [file path] — [method, route, purpose]

### Existing Entities
- [Entity]: [file path] — [key fields, relationships]

### Existing Services
- [Service]: [file path] — [key methods, purpose]

### Database State
- [Table]: [config file path] — [key indexes, constraints]

### Configuration
- [Options]: [file path] — [key settings]

### Current State Summary
- [What works today, what's missing for this feature]
```

#### Agent: `standards-reviewer`

Focus: **Project standards & constraints**. Understands what rules and conventions must be followed.

Research tasks:
- **Constitution rules** — Read `.specify/constitution.md` and extract all rules relevant to this feature (auth, data, testing, observability, etc.)
- **Architecture docs** — Read `docs/architecture/` and identify architectural patterns, constraints, and conventions that apply
- **Requirements docs** — Read `docs/requirements/` and find existing requirement documents that relate to this feature
- **Quality metrics** — What SLIs/SLOs, test coverage targets, accessibility standards, and performance budgets apply?
- **Delivery standards** — What must the spec include to satisfy the constitution's Delivery Standards section?

**Output format:**
```
## Standards Research

### Applicable Constitution Rules
- [Rule]: [quote] — [how it applies to this feature]

### Architecture Constraints
- [Constraint]: [source file] — [implication]

### Related Requirements
- [Requirement doc]: [path] — [what's relevant]

### Quality Targets
- [Metric]: [target] — [source]

### Spec Requirements
- [What the spec MUST include per constitution]
```

---

## Phase 3: Write the Specification (You, the lead)

After all 3 agents return, you have comprehensive project context. Now write the spec.

### Step 1: Synthesize context

Combine the three research reports to understand:
- What already exists (codebase explorer)
- What's already specified (specs researcher)
- What rules apply (standards reviewer)

### Step 2: Write spec.md

Follow the spec template structure and the existing Speckit `/speckit.specify` workflow:

1. **Parse the user's feature description** — extract actors, actions, data, constraints
2. **For unclear aspects** — make informed guesses based on:
   - Existing spec patterns (from specs researcher)
   - Current codebase state (from codebase explorer)
   - Project standards (from standards reviewer)
   - Only mark with `[NEEDS CLARIFICATION]` if truly ambiguous (max 3)
3. **Fill all template sections** — using real context from research:
   - Reference existing entities by name (from codebase explorer)
   - Follow requirement ID patterns (from specs researcher)
   - Include constitution-required quality metrics (from standards reviewer)
4. **Write to `SPEC_FILE`**

### Step 3: Quality validation

Run the same validation as the existing `/speckit.specify` command:
- No implementation details (languages, frameworks, APIs)
- Focused on user value and business needs
- Requirements are testable and unambiguous
- Success criteria are measurable and technology-agnostic
- Max 3 `[NEEDS CLARIFICATION]` markers

If validation fails, fix and re-validate (max 3 iterations).

### Step 4: Handle clarifications

If `[NEEDS CLARIFICATION]` markers remain (max 3):
- Present each as a question with options table
- Wait for user responses
- Update spec with answers
- Re-validate

---

## Phase 4: Report

```
## Specification Complete

**Feature:** <feature-name>
**Branch:** <branch-name>
**Spec:** <path to spec.md>

### Context Summary
- **Existing specs reviewed:** N (N overlapping with this feature)
- **Codebase entities found:** N related entities, N related services
- **Constitution rules applied:** N rules

### Spec Overview
- **User stories:** N
- **Functional requirements:** N
- **Clarifications needed:** N (resolved: N, remaining: N)

**Next step:** Run `/speckit.clarify` for team-driven clarification, or `/speckit.plan` to start planning.
```

---

## Guardrails

- **Specify, don't plan** — No architecture decisions, no tech stack choices, no implementation details. That's for `/speckit.plan`.
- **Read-only on codebase** — You and the agents may read any file. Do NOT write application code.
- **You MAY write** spec.md and the checklist — those are Speckit artifacts.
- **Max 3 clarifications** — Make informed guesses for everything else. Document assumptions.
- **Use real context** — Reference actual entities, endpoints, and patterns found by the research agents. Don't invent names.
- **Follow existing spec patterns** — Match the style, depth, and structure of existing specs in the project.
- **Framework-agnostic specs** — The spec describes WHAT, not HOW. No mention of specific technologies.
- **Constitution compliance** — The spec must include all sections required by the constitution's Delivery Standards.
