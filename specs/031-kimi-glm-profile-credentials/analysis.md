# Specification review and approved revision

Original source review: 2026-10-23, wizard baseline `b8b1607`.
Codex and independent GPT-6 Astra review: 2026-10-24, documentation baseline
`c5f39c440b17f6f73182b183bc1e9bdef73c1feb`.
Brett approved every reported revision on 2026-10-24:
[authority and findings](review-2026-10-24.md).

Documentation only; no runtime implementation or live qualification is asserted.
Existing 029/032 evidence is not extended to these credential features. One
OpenSpec change hands off to one executable implementation checklist.

| Requirements | Owning tasks |
| --- | --- |
| FR-001, FR-006, FR-007 | T000, T001, T002, T004 |
| FR-002, FR-003, FR-016 | T002, T002A, T007A |
| FR-004, FR-022 | T004, T007A, T007 |
| FR-005, FR-020 | T000, T001, T002, T003 |
| FR-008, FR-009, FR-017 | T004, T005, T006 |
| FR-010–FR-012, FR-019 | T000, T001, T006, T007B |
| FR-013, FR-014, FR-018 | T000, T002, T007A, T007 |
| FR-015, FR-021, FR-023, SC-001–SC-007 | T000, T002A–T010 as scoped in tasks |

## Reconciled review findings

The working documents now explicitly cover native terminal transport; effective
provider routing; selected-record projection and actual sync-client integration;
stable company control-plane environment; owned profile enrollment and personal/
default/custom-root exclusion; authMode versus syncPolicy schema compatibility;
032 executable/version/update qualification; legacy OAuth/import behavior;
fingerprint-bound observations; corrected high-default/explicit-max model
behavior; packaging imports and complete verification/acceptance boundaries.

M1 local profiles/login/persistence, M2 qualified retrieval and M3 company sync
have separate release outcomes. The plan names nonempty minimum M2 rows;
unqualified required rows defer retrieval rather than passing an all-disabled
matrix. Independent account binding and OAuth restrictions remain unchanged.

The constitution remains a template; global rules and the plan's concrete
invariants apply. Provider formats, account evidence and remote/refresh
eligibility still need real qualification; documenting a gate is not passing it.

## Validation boundary

The documentation revision is checked for OpenSpec structure, relative links,
requirement/task traceability, unique unchecked runtime task IDs and consistent
planned/unsupported labels. Runtime verification commands name future task
outputs; they are not executed or claimed passing for this documentation update.
Native login, secret-store retrieval, credentials and cloud resources remain
untouched. Exact-head CI, attended mode/platform acceptance and release gates
remain outstanding.

2026-10-24 documentation results: OpenSpec strict validation passed; all 14
Markdown documents passed local-link, code-fence and LF checks; FR-001–FR-023
are uniquely defined and all 14 runtime tasks have unique IDs, scope/verification
fields and unchecked status. Git whitespace checks passed. Astra's final
read-only follow-up confirmed coverage and no remaining must-fix documentation
contradictions, including independent M2 dependencies, eligible company custom
roots and OAuth-versus-API-key migration status.
