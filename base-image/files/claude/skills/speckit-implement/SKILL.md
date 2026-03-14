---
name: speckit-implement
description: "Execute Speckit tasks using agent teams for parallel implementation. Analyzes task dependencies, groups independent tasks into non-overlapping work packages, and spawns parallel agents for concurrent execution."
metadata:
  author: custom
  version: "1.0"
---

You are a **team lead** orchestrating feature implementation. You analyze the task list, group independent tasks into work packages with non-overlapping file ownership, and spawn parallel agents to maximize throughput.

**IMPORTANT: Analyze before parallelizing.** Build the dependency graph first. Only parallelize tasks with zero file overlap and no blocking dependencies.

---

## Input

Optionally, the user may specify a feature name. If not, detect the active feature:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
```

Parse `FEATURE_DIR` and `AVAILABLE_DOCS` from the JSON output.

---

## Phase 1: Load Context

1. **Read all feature artifacts:**
   - **REQUIRED:** tasks.md — the complete task list and execution plan
   - **REQUIRED:** plan.md — tech stack, architecture, file structure
   - **IF EXISTS:** spec.md — requirements and acceptance criteria
   - **IF EXISTS:** data-model.md — entities and relationships
   - **IF EXISTS:** contracts/ — API specifications
   - **IF EXISTS:** research.md — technical decisions

2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files for completion status
   - If any checklist is incomplete: show status table and ask user whether to proceed
   - If all complete: proceed automatically

3. **Parse tasks.md:**
   - Extract all tasks with: ID, description, file paths, phase, parallel markers [P], story labels [USn], completion status [x]/[ ]
   - Identify pending tasks (unchecked `- [ ]`)
   - If no pending tasks: congratulate and suggest next step

---

## Phase 2: Task Analysis & Grouping

### Step 1: Build the task dependency graph

For each pending task, determine:
- **Which files it will create or modify** (infer from the task description and plan.md)
- **Which tasks it depends on** (does it reference output from another task? Is it in a later phase?)
- **Which tasks are independent** (no shared files, no dependency)

### Step 2: Choose execution strategy

**Sequential (no team)** — Use when:
- 5 or fewer pending tasks
- Most tasks depend on each other linearly
- Tasks touch overlapping files
- The user asks to go one-by-one

**Parallel (agent team)** — Use when:
- 6+ pending tasks remaining
- Tasks can be grouped into 2+ independent clusters
- Clusters touch non-overlapping files

If parallel, proceed to Phase 3. If sequential, skip to Phase 4.

### Step 3: Group tasks into work packages

Group independent tasks into **work packages**, where each package:
- Contains tasks that share related files (same service, same entity, same test file)
- Has **zero file overlap** with other packages
- Has its internal tasks ordered by dependency

Example grouping:
```
Package A (domain-entities):    Tasks T003, T004, T005 → touches Entity.cs, EntityConfig.cs
Package B (service-layer):      Tasks T008, T009, T010 → touches Service.cs, IService.cs
Package C (api-endpoints):      Tasks T012, T013       → touches Controller.cs, Validator.cs
Package D (background-workers): Tasks T015, T016       → touches Worker.cs, Channel.cs
```

**Dependencies between packages:** If Package C depends on Package B completing first, mark it. Only packages with no blockers get spawned in the first wave.

---

## Phase 3: Team Execution (Parallel)

### Create the team
Use **TeamCreate** to create a team (e.g., `speckit-impl-<feature-name>`).

### Create task items
Use **TaskCreate** for each work package. Include:
- All tasks in the package with their descriptions
- The files to create/modify
- Context: which plan.md sections, spec requirements, and data model sections are relevant
- Dependencies on other packages (use `addBlockedBy` if needed)

### Spawn agents
Use the **Agent tool** to spawn one `general-purpose` agent per work package **in a single message** (parallel launch). Each agent prompt must include:

1. The team name
2. The task ID to claim
3. Full file paths for all context files (spec.md, plan.md, data-model.md, contracts/)
4. The specific tasks to implement, in order
5. The files they own (create/modify only these)
6. Constitution path (`.specify/constitution.md`) for coding standards reference
7. Instruction to mark tasks complete with `- [ ]` → `- [x]` in tasks.md — **but only their assigned tasks**
8. Instruction to report back when done or blocked

**CRITICAL file ownership rules:**
- Each agent ONLY modifies files in its assigned package
- `tasks.md` checkbox updates: each agent updates ONLY its own task checkboxes
- If an agent discovers it needs to modify a file owned by another agent, it reports the dependency instead of making the change

### Monitor & coordinate
- Wait for agents to complete or report blockers
- If an agent is blocked on another package, check if the blocking package is done
- When a wave completes, check for newly-unblocked packages and spawn the next wave
- Handle conflicts: if two agents report needing the same file, reassign one

### Shutdown
After all packages complete:
- Send **shutdown_request** to all agents
- **TeamDelete** to clean up

---

## Phase 4: Sequential Execution (Fallback)

For each pending task, in order:
- Show which task is being worked on
- Read the relevant plan.md sections and spec requirements for context
- Make the code changes required
- Keep changes minimal and focused on the task
- Mark task complete: `- [ ]` → `- [x]` in tasks.md
- Continue to next task

**Pause if:**
- Task is unclear → ask for clarification
- Implementation reveals a design issue → suggest updating artifacts
- Error or blocker encountered → report and wait for guidance
- User interrupts

---

## Phase 5: Validation & Completion

### Post-implementation checks

After all tasks complete (or a wave completes):
1. **Verify tasks.md** — all assigned tasks should be `[x]`
2. **Build check** — if a build command is configured, run it
3. **Lint check** — if lint/format tools are configured, run them
4. **Test check** — if test tasks were included, verify they pass

### Show final status

```
## Implementation Complete

**Feature:** <feature-name>
**Strategy:** [Sequential | Parallel — N agents, M waves]
**Progress:** N/N tasks complete

### Completed This Session
- [x] T003 — Create CaptureSession entity
- [x] T004 — Add EF Core configuration
- [x] T005 — Create migration
...

### Validation
- Build: ✓ PASS / ✗ FAIL
- Lint: ✓ PASS / ✗ FAIL / — SKIPPED
- Tests: ✓ PASS / ✗ FAIL / — SKIPPED

All tasks complete! Run `/speckit.analyze` for a post-implementation audit.
```

### On pause (issue encountered)

```
## Implementation Paused

**Feature:** <feature-name>
**Progress:** N/M tasks complete

### Issue Encountered
<description of the issue>

**Options:**
1. <option 1>
2. <option 2>
3. Other approach

What would you like to do?
```

---

## Guardrails

- **Analyze before parallelizing** — Don't blindly spawn agents. Build the dependency graph first.
- **Zero file overlap between agents** — This is the #1 rule. If two packages share a file, merge them into one package.
- **tasks.md ownership** — Each agent only checks off its own tasks. The lead can check off integration tasks.
- **Keep going until done or blocked** — Don't stop between tasks unless there's a reason.
- **Read all context before starting** — Agents must read the plan, spec, and relevant artifacts for their package.
- **Pause on ambiguity** — Don't guess. Pause and ask.
- **Minimal changes** — Keep code changes scoped to each task. Don't refactor adjacent code.
- **Verify after completion** — After all agents finish, do a quick sanity check (build, lint, or test if configured).
- **Respect constitution** — All implementation must follow the project constitution's coding standards.
- **Re-runnable** — Running this skill again picks up where it left off (reads checkboxes to find remaining tasks).
