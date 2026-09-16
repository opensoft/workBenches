# Implementation Plan: AI Credential Custody

**Branch**: `008-ai-credential-custody` | **Date**: 2026-09-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-ai-credential-custody/spec.md`

## Summary

Define an ownership-aware credential registry across Opensoft-Tenant and Brett's AI-Credentials repository, make the Opensoft Azure Key Vault contract explicit, and extend the existing workBenches escrow CLI with a preserve-by-default restore operation. The implementation validates all authority, path, metadata, and payload boundaries before atomically installing a credential and never emits credential contents. OpenCode bootstrap additionally restores the Opensoft-owned OmniRoute record independently and merges only that record into shared authentication before offering interactive login.

## Technical Context

**Language/Version**: Bash 5.x for credential operations; Python 3.12+ or jq-based validation for registry reconciliation; JSON and Markdown contracts

**Primary Dependencies**: Azure CLI, jq, stat, sha256sum, cmp, Git, existing workBenches profile launchers

**Storage**: Azure Key Vault versioned secrets; private Git repositories containing metadata or SOPS ciphertext; mode-0600 local JSON state

**Testing**: Shell integration tests with a fake Azure CLI and isolated HOME; metadata schema/coverage validation; existing workBenches devcontainer test harness

**Target Platform**: Linux and WSL2 hosts plus workBenches containers using the same Linux home-backed profile roots

**Project Type**: Cross-repository CLI, metadata contract, and operational documentation

**Performance Goals**: Restore one profile with one metadata lookup and one version-pinned download; batch work remains linear in selected entries

**Constraints**: No secret values in Git, argv, logs, telemetry, tests, or chat; no implicit overwrite; no path escape; no reliance on workstation state for first restore

**Scale/Scope**: Hundreds of profile records, tens to low hundreds of enabled durable mappings, Claude and Codex initially with Pi retained only where its existing validator and root are safe

## Constitution Check

The repository constitution is an unratified placeholder and defines no enforceable project gates. The implementation therefore follows the repository AGENTS instructions and global OpenSpec/Speckit protocol. Security gates come from the approved feature specification: secret-safe output, ownership separation, target containment, preserve-by-default, exact-version restore, and focused tests.

Post-design check: PASS. No design artifact weakens those gates, adds plaintext storage, or gives workBenches credential ownership.

## Project Structure

### Documentation (this feature)

```text
specs/008-ai-credential-custody/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── key-vault-manifest.schema.json
│   └── restore-cli.md
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
└── backup-ai-profile-credentials-to-kv.sh

devcontainer.test/
└── test-ai-credential-keyvault.sh

docs/
└── ai-harness-account-management.md

openspec/changes/govern-ai-credential-custody/
├── proposal.md
├── design.md
├── specs/
└── tasks.md
```

Cross-repository implementation checkouts carry the same feature intent:

```text
Opensoft-Tenant-worktrees/ai-credential-registry/
└── ai/                         # tenant metadata and vault contract

AI-Credentials-worktrees/008-ai-credential-custody/
└── ai/                         # personal metadata, ciphertext policy, coverage
```

**Structure Decision**: Extend the existing workBenches escrow script rather than introduce another credential CLI. Keep tenant and personal ownership metadata in their owning private repositories and keep cross-repository acceptance criteria in this feature's governance/specification artifacts.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Three repository change | Ownership metadata belongs to two different owners while generic restore tooling belongs in workBenches | Putting all artifacts in workBenches or Opensoft-Tenant would make the wrong repository authoritative for personal or generic behavior |
