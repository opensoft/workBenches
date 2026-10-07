# Tasks: All-bench process reaping

**Input**: [spec.md](spec.md), [plan.md](plan.md), governed `add-all-bench-reaping` change.

## Setup

- [x] T001 Inventory all fourteen repositories, tracked canonical/template/test definitions, instruction ownership and clean baselines; create external linked feature worktrees.
- [x] T002 Add configuration checker and negative/positive regression fixtures; demonstrate failure on old definitions.

## US1: Canonical startup protection

- [x] T003 Enable init in canonical Compose services across all fourteen benches, including Frappe bench-based workers, without changing commands or mounts.
- [x] T004 Validate canonical definitions and declared GPU/user-map override chains.

## US2: Durable templates and safe rollout

- [x] T005 Enable init in tracked Flutter templates/workspace examples, bench examples/tests and parent family/test Compose services.
- [x] T006 Run checker fixtures and Wave lifecycle suite; add CI coverage and operator rollout documentation.
- [x] T007 Recheck live container identities/start times and record exact verification evidence in verification.md.
- [x] T008 With user publication approval, open and land checked/reviewed child PRs; verify their default-branch commits.
- [ ] T009 Advance only the eight registered parent gitlinks, land the parent PR and update clean operational checkouts without replacing containers.
- [ ] T010 Close review gaps with unfiltered repository-local checks for the five public setup clones, align the three private checker references, and reject empty startup variants independently.

## Dependencies & Execution Order

T002 precedes configuration edits; T003/T005 precede effective validation. Verification precedes publication. T008 precedes T009. Live activation is not an implementation task and requires separate authorization.
