# Tasks: AI Credential Custody

**Input**: Design documents from `specs/008-ai-credential-custody/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Required for the restore security contract and metadata reconciliation.

## Phase 1: Setup

- [x] T001 Create isolated feature worktrees for `Opensoft-Tenant:agent/ai-credential-registry` and `AI-Credentials:008-ai-credential-custody` without changing either main checkout
- [x] T002 Verify all three feature checkouts are clean or contain only this feature's changes in their respective `git status` output

## Phase 2: Foundational Contracts

- [x] T003 [P] Add the non-secret Azure Key Vault custody contract in `Opensoft-Tenant:ai/vault/azure-key-vault.json`
- [x] T004 [P] Update company custody and migration policy in `Opensoft-Tenant:ai/docs/key-management.md` and `Opensoft-Tenant:ai/vault/secret-locations.json`
- [x] T005 [P] Update personal custody and optional secondary-escrow policy in `AI-Credentials:README.md` and `AI-Credentials:ai/docs/key-management.md`

## Phase 3: User Story 1 - Recover an Opensoft profile (Priority: P1)

**Goal**: Restore one company credential from an exact approved Key Vault version without implicit overwrite or secret output.

**Independent Test**: Run the isolated fake-Azure test suite and confirm successful restore, preserve, force, and rejection cases.

- [x] T006 [US1] Add failing restore contract cases in `devcontainer.test/test-ai-credential-keyvault.sh`
- [x] T007 [US1] Implement target containment, metadata validation, exact-version download, atomic install, and `--force` handling in `scripts/backup-ai-profile-credentials-to-kv.sh`
- [x] T008 [US1] Record restored version metadata without weakening existing backup/verify behavior in `scripts/backup-ai-profile-credentials-to-kv.sh`
- [x] T009 [US1] Make all restore contract tests pass in `devcontainer.test/test-ai-credential-keyvault.sh`

## Phase 4: User Story 2 - Audit company custody (Priority: P2)

**Goal**: Represent and validate every Opensoft-owned profile and durable mapping without payload access.

**Independent Test**: Run metadata validation against current provider manifests and the Key Vault mapping and obtain a zero-silent-omission report or explicit exceptions.

- [x] T010 [US2] Reconcile canonical company profile records and ownership metadata in `Opensoft-Tenant:ai/source.json`
- [x] T011 [US2] Add metadata-only coverage validation in `Opensoft-Tenant:scripts/validate-ai-credential-registry.py`
- [x] T012 [US2] Add fixture tests for missing mappings, ownership collisions, duplicates, and retired-enabled conflicts in `Opensoft-Tenant:tests/test_validate_ai_credential_registry.py`

## Phase 5: User Story 3 - Recover personal credentials independently (Priority: P3)

**Goal**: Keep Brett-owned recovery independent while reporting incomplete escrow.

**Independent Test**: Run a personal coverage command without Azure access and list all escrowed and missing personal profiles without credential values.

- [x] T013 [US3] Add a metadata-only personal escrow coverage command in `AI-Credentials:scripts/credential-coverage`
- [x] T014 [US3] Document current personal coverage and recovery boundaries in `AI-Credentials:README.md` and `AI-Credentials:ai/docs/key-management.md`
- [x] T015 [US3] Validate all current personal records and ciphertext presence without decrypting payloads using `AI-Credentials:scripts/credential-coverage`

## Phase 6: Documentation and Verification

- [x] T016 [P] Update restore and ownership instructions in `docs/ai-harness-account-management.md`
- [x] T017 Run focused shell, syntax, metadata, and secret-leak tests across all three feature checkouts
- [x] T018 Reconcile OpenSpec and Speckit task completion and record live Key Vault/profile operations that remain intentionally deferred

## Phase 7: User Story 4 - Inventory model-hoster accounts (Priority: P2)

**Goal**: Catalog provider accounts separately from profiles and credentials and produce one secret-safe combined owner report.

**Independent Test**: Validate the current Brett and Opensoft registries together and run isolated fixtures for every duplicate, orphan, ownership, secret-metadata, and missing-escrow failure class.

- [x] T019 [P] [US4] Add the account-catalog schema in `config/ai-account-catalog.schema.json`
- [x] T020 [P] [US4] Add provider and account catalogs in `Opensoft-Tenant:ai/accounts/`
- [x] T021 [P] [US4] Add provider and account catalogs in `AI-Credentials:ai/accounts/`
- [x] T022 [US4] Link profile authentication metadata to stable account IDs in both private `ai/source.json` files
- [x] T023 [US4] Implement combined validation and reporting in `scripts/report-ai-provider-accounts.py`
- [x] T024 [US4] Add combined report fixtures in `devcontainer.test/test-report-ai-provider-accounts.py`
- [x] T025 [P] [US4] Document account catalog maintenance in both private repositories and `docs/ai-harness-account-management.md`
- [x] T026 [US4] Run secret-safe individual and combined validation and reconcile blocking findings
- [x] T027 [US4] Reconcile OpenSpec and Speckit completion and record explicit unknown subscription metadata

## Phase 8: User Story 5 - Recover OpenCode OmniRoute access (Priority: P1)

**Goal**: Restore only the Opensoft-owned OmniRoute provider record before OpenCode setup prompts for authentication.

**Independent Test**: Use an isolated fake Azure CLI and mixed-provider OpenCode auth fixture to prove fresh restore, provider-only merge, preserve-by-default behavior, fallback, and secret-safe output.

- [x] T028 [US5] Register the standalone OmniRoute credential and materialization path in `Opensoft-Tenant:ai/vault/azure-key-vault.json` and company key-management documentation
- [x] T029 [US5] Extend `scripts/backup-ai-profile-credentials-to-kv.sh` with a bounded OmniRoute provider-record validator and approved target root
- [x] T030 [US5] Implement secret-safe OmniRoute capture/status/install operations for OpenCode shared authentication
- [x] T031 [US5] Implement registry discovery and guarded Key Vault restore before the OpenCode login prompt
- [x] T032 [US5] Add fresh-workstation, mixed-provider preservation, validation, and fallback tests
- [x] T033 [US5] Back up and verify the live standalone OmniRoute secret in the Opensoft Key Vault without exposing its value
- [x] T034 [US5] Run focused validation across workBenches and Opensoft-Tenant and reconcile OpenSpec/Speckit task completion

## Dependencies & Execution Order

- T001-T002 precede all cross-repository edits.
- T003-T005 can proceed independently once worktrees exist.
- T006 precedes T007-T009; T009 completes User Story 1.
- T010-T012 depend on the Opensoft contract from T003-T004.
- T013-T015 depend only on the AI-Credentials worktree and can proceed independently of Azure.
- T016 may proceed after the CLI contract is stable; T017-T018 are final gates.
- T019-T022 establish the account contracts before T023-T024; T025 can proceed in parallel after the catalog layout is stable; T026-T027 are final account-catalog gates.
- T028 establishes the registry contract before T029-T031; T032 validates code behavior before the live T033 operation; T034 is the final gate.

## Implementation Strategy

Complete User Story 1 first because safe restore is the minimum recoverability increment. Then reconcile company metadata, then personal coverage. No live credential write or restore is required for code acceptance; any live canary follows a separate exact-profile authorization and read-back.
