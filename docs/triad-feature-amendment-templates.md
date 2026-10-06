# Feature Amendment Record Templates

Status: manual templates
Kind: template
Workflow: [Triad feature amendments](triad-feature-amendments.md).

These portable templates describe the adopted record format. A future custom OpenSpec schema can generate them; no schema installation is implied here. Replace placeholders with real repository identities, immutable commit references, requirement IDs and decision sources.

## Local feature manifest

```yaml
feature: NNN-feature
governing_repository: owner/project-spec
governing_change: governing-change
governing_path: openspec/changes/governing-change
approved_baseline_commit: <full-docs-commit>
speckit_path: specs/NNN-feature
docs_branch: NNN-feature
code_branch: NNN-feature
reconciliation_issue: owner/project-spec#issue-number
amendments:
  - id: 001-refine-acceptance
    path: changes/001-refine-acceptance/amendment.md
    disposition: accepted
```

Create this manifest in `features/<NNN-feature>/openspec/` in the code feature checkout. `governing_path` and `speckit_path` are relative to the named docs repository; amendment paths are relative to the manifest. A proposal moved into archive retains its change ID and gains its archive location in the final reconciliation record. Repository identity plus commit and path identifies the baseline even after that move.

## Amendment

```markdown
# Amendment: 001-refine-acceptance

Feature: NNN-feature
Governing change: governing-change
Approved baseline: owner/project-spec @ <full-docs-commit>
Disposition: proposed
Decision authority: <person or existing delegated authority>
Decision source: <dated instruction, review or decision-record reference>
Affected requirements/contracts: <identifiers>
Affected Speckit tasks: <task identifiers>
Reconciliation issue: owner/project-spec#issue-number

## Reason and scope

Explain the discovery and why this fits the approved feature boundaries.

## Specification change

Describe the previous and revised interpretation. Link any requirement deltas.

## Working feature updates

Identify the feature spec, plan, acceptance criteria and tasks updated in docs.

## Implementation and verification

Record implementation commits and evidence when they exist.

## Final disposition

Record implementation, reversal, supersession or deferral with its reason.
```

When a requirement delta is needed, place it in the same local change's `specs/<capability>/spec.md`, using existing OpenSpec requirement/scenario syntax. These deltas express changes relative to the docs baseline; they do not authorize promotion into a local product-spec store.

## Reconciliation issue

Title: `Reconcile NNN-feature amendments into governing docs`

```markdown
Governing change: <change ID and baseline commit>
Feature: <Speckit feature path>
Code repository and branch: <repository, branch>

Collect the final dispositions and net effect of all feature amendments.
Keep executable work in the Speckit task list.

## Amendment references

- <amendment ID and durable code-repository path/commit>

## Completion evidence

- <docs reconciliation PR>
- <corresponding landed code commit and verification report>
- <future-proposal issue links for deferred larger ideas>

Close after the docs reconciliation lands. The feature landing record tracks
the matching assembly pin update and subsequent archive eligibility.
```

## Final docs reconciliation record

```markdown
# As-built reconciliation: NNN-feature

Governing change and original baseline: <ID, docs repository, full commit>
Working feature: specs/NNN-feature
Landed code commit: <code repository, full commit>
Reconciliation issue: <issue reference>
Verification: <evidence links>

## Amendment dispositions

| Amendment | Final disposition | Effect on the final requirements | Evidence |
|---|---|---|---|
| <ID and link> | <implemented/reverted/superseded/deferred> | <net effect> | <link> |

## As-built changes

Describe the net changes applied to governing specs, contracts and design.

## Approved history and future work

Preserve the approved baseline and decisions; link deferred proposal issues.

## Project landing

Link the docs/code PRs and the assembly landing record when available.
```
