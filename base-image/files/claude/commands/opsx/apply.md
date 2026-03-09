---
name: "OPSX: Apply"
description: Implement tasks from an OpenSpec change using agent teams for parallel execution
category: Workflow
tags: [workflow, artifacts, experimental, teams]
---

Implement tasks from an OpenSpec change. Uses agent teams to parallelize independent tasks across non-overlapping file groups.

**Input**: Optionally specify a change name (e.g., `/opsx:apply add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

---

## Phase 1: Select & Load Context

1. **Select the change**

   If a name is provided, use it. Otherwise:
   - Infer from conversation context if the user mentioned a change
   - Auto-select if only one active change exists
   - If ambiguous, run `openspec list --json` and use **AskUserQuestion** to let the user select

   Always announce: "Using change: <name>"

2. **Check status**
   ```bash
   openspec status --change "<name>" --json
   ```
   Parse `schemaName`, artifact status, and which artifact contains tasks.

3. **Get apply instructions**
   ```bash
   openspec instructions apply --change "<name>" --json
   ```
   - If `state: "blocked"` (missing artifacts): show message, suggest `/opsx:propose`
   - If `state: "all_done"`: congratulate, suggest `/opsx:archive`
   - Otherwise: proceed

4. **Read context files**

   Read ALL files from `contextFiles` in the apply instructions output (proposal, design, specs, tasks, clarifications if present).

5. **Show progress**
   - Schema being used
   - "N/M tasks complete"
   - Remaining tasks overview

---

## Phase 2: Task Analysis & Grouping

Before implementing, analyze the pending tasks to determine the execution strategy.

### Step 1: Build the task dependency graph

For each pending task, determine:
- **Which files it will create or modify** (infer from the task description and design.md)
- **Which tasks it depends on** (does it reference output from another task?)
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
- Contains tasks that share related files (same service, same model, same test file)
- Has **zero file overlap** with other packages
- Has its internal tasks ordered by dependency

Example grouping:
```
Package A (buffer-service):     Tasks 1.1, 1.2, 1.3, 2.1, 2.2 → touches buffer_service.dart, buffer_manifest.dart
Package B (packaging-service):  Tasks 6.1, 6.2, 7.1, 7.2       → touches packaging_service.dart, package_metadata.dart
Package C (ui-widgets):         Tasks 5.2, 5.3, 12.3            → touches orphan_dialog.dart, incomplete_dialog.dart
Package D (integration-tests):  Tasks 13.1, 13.2                → touches test/ files
```

**Dependencies between packages**: If Package B depends on Package A completing first, mark it. Only packages with no blockers get spawned in the first wave.

---

## Phase 3: Team Execution (Parallel)

### Create the team
Use **TeamCreate** to create a team (e.g., `apply-<change-name>`).

### Create task items
Use **TaskCreate** for each work package. Include:
- All tasks in the package with their descriptions
- The files to create/modify
- Context: which design.md sections and spec scenarios are relevant
- Dependencies on other packages (use `addBlockedBy` if needed)

### Spawn agents
Use the **Agent tool** to spawn one `general-purpose` agent per work package **in a single message** (parallel launch). Each agent prompt must include:

1. The team name
2. The task ID to claim
3. Full file paths for all context files (proposal, design, specs, clarifications)
4. The specific tasks to implement, in order
5. The files they own (create/modify only these)
6. Instruction to mark tasks complete with `- [ ]` → `- [x]` in tasks.md — **but only their assigned tasks**
7. Instruction to report back when done or blocked

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

For each pending task:
- Show which task is being worked on
- Make the code changes required
- Keep changes minimal and focused
- Mark task complete: `- [ ]` → `- [x]`
- Continue to next task

**Pause if:**
- Task is unclear → ask for clarification
- Implementation reveals a design issue → suggest updating artifacts
- Error or blocker encountered → report and wait for guidance
- User interrupts

---

## Phase 5: Completion

### Show final status

```
## Implementation Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Strategy:** [Sequential | Parallel — N agents, M waves]
**Progress:** N/N tasks complete

### Completed This Session
- [x] Task 1.1 — description
- [x] Task 1.2 — description
...

All tasks complete! Run `/opsx:archive` to archive this change.
```

### On pause (issue encountered)

```
## Implementation Paused

**Change:** <change-name>
**Schema:** <schema-name>
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
- **Read all context before starting** — Agents must read the design, specs, and clarifications relevant to their package.
- **Pause on ambiguity** — Don't guess. Pause and ask.
- **Minimal changes** — Keep code changes scoped to each task. Don't refactor adjacent code.
- **Verify after completion** — After all agents finish, do a quick sanity check (build, lint, or test if configured).

## Fluid Workflow Integration

This command supports the "actions on a change" model:
- Can be invoked anytime: before all artifacts are done (if tasks exist), after partial implementation, interleaved with other actions
- Allows artifact updates: if implementation reveals design issues, suggest updating artifacts
- Re-running `/opsx:apply` picks up where it left off (reads checkboxes to find remaining tasks)
