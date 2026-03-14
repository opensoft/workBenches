---
name: speckit-tasks
description: "Generate and validate Speckit tasks using a two-phase approach. The lead generates tasks.md from the plan, then three validation agents audit atomicity, completeness, and dependencies in parallel. Lead incorporates feedback into the final tasks.md."
metadata:
  author: custom
  version: "1.0"
---

You are a **team lead** orchestrating task generation and validation. You first generate the task breakdown from the plan, then assemble a validation team to audit the tasks before finalizing.

**IMPORTANT: This is a two-phase process — generate, then validate.** Phase 1 produces the initial tasks.md. Phase 2 spawns parallel validators to catch issues. You incorporate their feedback into the final version.

---

## Input

Optionally, the user may provide additional context. Detect the active feature:

```bash
.specify/scripts/bash/check-prerequisites.sh --json
```

Parse `FEATURE_DIR` and `AVAILABLE_DOCS` from the JSON output.

---

## Phase 1: Generate Tasks (You, the lead)

### Step 1: Load design documents

Read from FEATURE_DIR:
- **REQUIRED:** plan.md — tech stack, architecture, file structure, phases
- **REQUIRED:** spec.md — user stories with priorities, functional requirements
- **IF EXISTS:** data-model.md — entities and relationships
- **IF EXISTS:** contracts/ — API specifications
- **IF EXISTS:** research.md — technical decisions
- **IF EXISTS:** quickstart.md — integration scenarios

### Step 2: Load template and standards

- Read `.specify/templates/tasks-template.md` for task format requirements
- Read `.specify/constitution.md` for delivery standards

### Step 3: Generate tasks.md

Follow the existing Speckit `/speckit.tasks` workflow:

1. **Extract tech stack and libraries** from plan.md
2. **Extract user stories with priorities** (P1, P2, P3) from spec.md
3. **Map entities** from data-model.md to user stories (if exists)
4. **Map endpoints** from contracts/ to user stories (if exists)
5. **Generate tasks organized by user story** using the strict checklist format:

```
- [ ] [TaskID] [P?] [Story?] Description with file path
```

6. **Phase structure:**
   - Phase 1: Setup (project initialization)
   - Phase 2: Foundational (blocking prerequisites)
   - Phase 3+: User Stories in priority order
   - Final Phase: Polish & cross-cutting concerns

7. **Write initial tasks.md** to `FEATURE_DIR/tasks.md`

---

## Phase 2: Validate Tasks (Agent Team)

Spawn **3 validation agents in parallel** to audit the generated tasks.

### Team Structure

```
┌────────────────────────────────────────────────────┐
│                    YOU (Lead)                       │
│     Generate tasks, incorporate validation          │
│     feedback, finalize tasks.md                     │
├──────────────┬──────────────────┬──────────────────┤
│              │                  │                   │
▼              ▼                  ▼                   │
atomicity      completeness      dependency           │
validator      validator         auditor              │
└──────────────┴──────────────────┴──────────────────┘
```

All agents use `subagent_type: general-purpose` (they need to read files).

**CRITICAL: Each agent prompt must include:**
1. Full path to the generated tasks.md
2. Full paths to spec.md, plan.md, and data-model.md (if exists)
3. Their specific validation focus (from the Agent Definitions below)
4. Instruction to return structured findings with severity ratings

---

### Agent Definitions

#### Agent: `atomicity-validator`

Focus: **Is each task truly atomic and independently completable?**

Validation checks:
1. **Single responsibility** — Does each task do exactly one thing? Flag tasks that say "Implement X and also update Y" — these should be split.
2. **Completable in isolation** — Can a developer pick up this task without needing to do half of another task first?
3. **Testable** — Is there a clear "done" condition? Could you write a test for just this task?
4. **No hidden side effects** — Does completing a task silently break or change something not mentioned?
5. **Reasonable scope** — Is the task small enough to complete in one focused session? Flag multi-day efforts hiding behind a single checkbox.
6. **File path specificity** — Does every task specify exact file paths, or are they vague ("update the service")?

For each finding, provide:
- Task ID
- Issue description
- Severity: SPLIT (must be split), CLARIFY (needs more detail), INFO (minor improvement)
- Suggested fix (how to split or rewrite)

#### Agent: `completeness-validator`

Focus: **Does every requirement in spec.md and every section of plan.md have corresponding tasks?**

Validation checks:
1. **Spec coverage** — For each functional requirement and user story in spec.md, is there at least one task? List uncovered requirements.
2. **Plan coverage** — For each section of plan.md (data model, API contracts, services, configuration, workers), are there corresponding tasks?
3. **Non-functional coverage** — Are there tasks for: error handling, logging, configuration, observability, auth, validation? If the spec or plan mentions these, they need tasks.
4. **Testing tasks** — If the spec or constitution requires tests, are test tasks included?
5. **Migration tasks** — If new entities or schema changes are in the plan, is there a migration task?
6. **DI registration** — If new services are introduced, is there a task for DI wiring?
7. **Constitution compliance** — Does the task list satisfy the constitution's delivery standards?

For each finding, provide:
- Missing requirement or plan section reference
- Severity: CRITICAL (core requirement has no task), WARNING (non-functional gap), INFO (nice-to-have)
- Suggested task to add (with Task ID, description, phase, and file path)

#### Agent: `dependency-auditor`

Focus: **Are task dependencies correct, complete, and free of cycles?**

Validation checks:
1. **Ordering** — Are foundational tasks (entities, configs, DI) before tasks that depend on them (services, controllers)?
2. **Phase correctness** — Are Setup tasks truly independent of domain logic? Are user story tasks correctly assigned to their story phase?
3. **Parallel safety** — Are tasks marked [P] truly parallelizable? Do any [P] tasks share files or have hidden dependencies?
4. **Missing dependencies** — Are there tasks that assume another task is done but don't declare the dependency?
5. **Circular dependencies** — Are there cycles where A needs B and B needs A?
6. **Cross-story dependencies** — If User Story 2 depends on an entity from User Story 1, is that entity in Foundational (Phase 2) or is the dependency declared?
7. **Integration order** — Are integration/end-to-end tasks at the end, after all components they integrate?

For each finding, provide:
- Task IDs involved
- Severity: CRITICAL (wrong order or cycle), WARNING (missing dependency declaration), INFO (could optimize order)
- Suggested fix (reorder, add dependency note, move to different phase)

Include an **ASCII dependency graph** showing the actual task flow with highlighted issues.

---

## Phase 3: Incorporate Feedback (You, the lead)

After all 3 validators return:

### Step 1: Triage findings

Categorize all findings:
- **CRITICAL / SPLIT** — Must fix before finalizing
- **WARNING / CLARIFY** — Should fix, high-value improvements
- **INFO** — Nice-to-have, fix if simple

### Step 2: Apply fixes to tasks.md

For each finding (criticals first):
1. **Split tasks** that aren't atomic
2. **Add missing tasks** for uncovered requirements
3. **Reorder tasks** to fix dependency issues
4. **Add parallel markers** [P] where the dependency auditor confirmed parallelism
5. **Add file paths** where specificity was missing
6. **Renumber Task IDs** if tasks were added or split (keep sequential)

### Step 3: Re-validate

Do a quick self-check:
- All tasks follow the checklist format: `- [ ] [TaskID] [P?] [Story?] Description with file path`
- Task IDs are sequential
- Each user story has tasks
- No obvious dependency violations

---

## Phase 4: Report

```
## Task Generation Complete

**Feature:** <feature-name>
**Tasks:** <path to tasks.md>

### Summary
- **Total tasks:** N
- **By phase:** Setup: N, Foundational: N, [Story phases]: N each, Polish: N
- **Parallelizable:** N tasks marked [P]

### Validation Results
| Validator | Critical | Warning | Info | Fixed |
|-----------|----------|---------|------|-------|
| Atomicity | N | N | N | N |
| Completeness | N | N | N | N |
| Dependencies | N | N | N | N |
| **Total** | **N** | **N** | **N** | **N** |

### Changes from Validation
- Split N tasks into N smaller tasks
- Added N missing tasks (coverage gaps)
- Reordered N tasks (dependency fixes)
- Added [P] markers to N tasks

### Dependency Graph
[ASCII graph from dependency auditor, updated with fixes]

**Next step:** Run `/speckit.analyze` for full consistency audit, or `/speckit.implement` to start building.
```

---

## Guardrails

- **Generate before validating** — Write the initial tasks.md first, then let the validators find issues. Don't try to be perfect on the first pass.
- **Read-only on codebase** — You and the agents may read any file. Do NOT write application code.
- **You MAY write** tasks.md — that's a Speckit artifact, not implementation.
- **Strict checklist format** — Every task must follow `- [ ] [TaskID] [P?] [Story?] Description with file path`. No exceptions.
- **Validation is mandatory** — Always run the 3 validators. Don't skip even if the initial generation looks good.
- **Fix criticals, report warnings** — All CRITICAL and SPLIT findings must be fixed. WARNING findings should be fixed. INFO findings are optional.
- **Framework-agnostic** — Validation agents adapt to whatever tech stack and task format the project uses.
- **Don't over-split** — Atomic doesn't mean trivial. A task like "Create UserService with CRUD methods" is fine if all methods are in one file and serve one purpose.
