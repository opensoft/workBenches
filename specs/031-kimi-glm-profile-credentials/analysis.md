# Specification review — 2026-10-23

Documentation only; no runtime implementation or live qualification is asserted.
Baseline: wizard feature 029 at `b8b1607`. Existing 029 evidence is not extended
to this addition. One OpenSpec change hands off to one implementation task list.

| Requirements | Tasks |
| --- | --- |
| FR-001, FR-006, FR-007 | T001, T002, T004 |
| FR-002, FR-003 | T002, T007 |
| FR-004 | T004, T007 |
| FR-005 | T003 |
| FR-008, FR-009 | T004, T005 |
| FR-010–FR-012 | T006 |
| FR-013, FR-014 | T007 |
| FR-015, SC-001–SC-005 | T008–T010 |

The constitution remains a template; global rules and the plan's invariants apply.
Provider account binding, native field allowlists, client compatibility and OAuth
remote/refresh eligibility require qualification before their operation is enabled.
Each has a task owner and an unsupported fallback. No credentials, pins or cloud
resources change in this documentation.

Brett's subsequent request for managed CLI harness installation is a separate
installer feature. Feature 031 owns credentials; integration must reconcile
prerequisite messages without mistaking CLI presence for authentication.
