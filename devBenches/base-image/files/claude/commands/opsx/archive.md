---
name: "OPSX: Archive"
description: Archive a completed change in the experimental workflow
category: Workflow
tags: [workflow, archive, experimental]
---

Archive a completed change in the experimental workflow.

**Input**: Optionally specify a change name after `/opsx:archive` (e.g., `/opsx:archive add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Steps**

1. **If no change name provided, prompt for selection**

   Run `openspec list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select.

   Show only active changes (not already archived).
   Include the schema used for each change if available.

   **IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

2. **Check artifact completion status**

   Run `openspec status --change "<name>" --json` to check artifact completion.

   Parse the JSON to understand:
   - `schemaName`: The workflow being used
   - `artifacts`: List of artifacts with their status (`done` or other)

   **If any artifacts are not `done`:**
   - Display warning listing incomplete artifacts
   - Prompt user for confirmation to continue
   - Proceed if user confirms

3. **Resolve the single Speckit handoff**

   Read the OpenSpec governance/handoff artifact and resolve exactly one linked Speckit feature, branch, and repo-relative task path (`specs/<feature>/tasks.md`). Resolve the current worktree through Speckit helpers rather than a committed host-absolute path.

   **If the link is missing, stale, or ambiguous:** stop and require the handoff to be repaired. Do not infer implementation completion from OpenSpec governance checkboxes.

4. **Check Speckit implementation and landing status**

   Read the linked Speckit `tasks.md` and count `- [ ]` (incomplete) vs `- [x]` (complete). Verify the handoff records one of these terminal outcomes:
   - the implementation branch/PR landed and verification passed
   - the implementation was explicitly abandoned with a recorded decision

   **If incomplete Speckit tasks or no terminal outcome is recorded:**
   - Display the incomplete count and missing landing/abandonment evidence
   - Stop while the work remains active
   - If the user chooses to abandon the work, first record that explicit terminal decision in the OpenSpec handoff; only then may archive continue

   **If the linked Speckit task file does not exist:** stop. A missing implementation authority is not equivalent to zero tasks.

5. **Assess delta spec sync state**

   Check for delta specs at `openspec/changes/<name>/specs/`. If none exist, proceed without sync prompt.

   **If delta specs exist:**
   - Compare each delta spec with its corresponding main spec at `openspec/specs/<capability>/spec.md`
   - Determine what changes would be applied (adds, modifications, removals, renames)
   - Show a combined summary before prompting

   **Prompt options:**
   - If changes needed: "Sync now (recommended)", "Archive without syncing"
   - If already synced: "Archive now", "Sync anyway", "Cancel"

   If user chooses sync, apply the delta specs directly using the standard OpenSpec delta rules. Update the corresponding files under `openspec/specs/<capability>/spec.md`, then proceed to archive. Do not invoke a separate sync skill or command unless it exists in the current project.

6. **Perform the archive**

   Create the archive directory if it doesn't exist:
   ```bash
   mkdir -p openspec/changes/archive
   ```

   Generate target name using current date: `YYYY-MM-DD-<change-name>`

   **Check if target already exists:**
   - If yes: Fail with error, suggest renaming existing archive or using different date
   - If no: Move the change directory to archive

   ```bash
   mv openspec/changes/<name> openspec/changes/archive/YYYY-MM-DD-<name>
   ```

7. **Display summary**

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status (synced / sync skipped / no delta specs)
   - Linked Speckit feature and terminal outcome
   - Note about any warnings (incomplete artifacts or Speckit tasks)

**Output On Success**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** ✓ Synced to main specs

All artifacts complete. All tasks complete.
```

**Output On Success (No Delta Specs)**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** No delta specs

All artifacts complete. All tasks complete.
```

**Output On Success With Warnings**

```
## Archive Complete (with warnings)

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** Sync skipped (user chose to skip)

**Warnings:**
- Archived with 2 incomplete artifacts
- Archived with 3 incomplete tasks
- Delta spec sync was skipped (user chose to skip)

Review the archive if this was not intentional.
```

**Output On Error (Archive Exists)**

```
## Archive Failed

**Change:** <change-name>
**Target:** openspec/changes/archive/YYYY-MM-DD-<name>/

Target archive directory already exists.

**Options:**
1. Rename the existing archive
2. Delete the existing archive if it's a duplicate
3. Wait until a different date to archive
```

**Guardrails**
- Always prompt for change selection if not provided
- Use artifact graph (openspec status --json) for completion checking
- Never treat OpenSpec governance checkboxes as implementation completion
- Require exactly one linked Speckit feature; block if the handoff or task file is missing or ambiguous
- Block unfinished active work. An explicitly abandoned change may proceed only after the terminal abandonment decision is recorded in the handoff.
- Preserve any files that actually exist inside the change directory when moving it to archive.
- Show clear summary of what happened
- If sync is requested, update the main specs directly from the delta specs before archiving.
- If delta specs exist, always run the sync assessment and show the combined summary before prompting
