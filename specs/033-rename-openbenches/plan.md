# Implementation Plan: Rename workBenches to openBenches

**Branch**: `033-rename-openbenches` | **Date**: 2026-10-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/033-rename-openbenches/spec.md` and OpenSpec change `rename-workbenches-to-openbenches`.

## Summary

Rename the current product through two separately gated deliveries: a slug-only GitHub cutover and a later runtime/product compatibility release. First land exact publication safeguards and dependent old/new discovery. Do not move existing checkouts, credentials, or persistent runtime state. Add canonical aliases and fresh-install paths only after consumers can resolve them. Validate historical and current releases, then deprecate only under a later proposal.

## Technical Context

**Language/Version**: Bash 3.2+ compatibility where required, Python 3.10+, PowerShell for existing Windows mirrors, Rust 1.88+ and TypeScript 5.8 for openProfiler.

**Primary Dependencies**: Git/GitHub CLI, OpenSpec 1.15, Speckit Git extension, Docker Compose, existing Tools/dev-bench runners, openProfiler Tauri/React core, and dependent repository toolchains.

**Storage**: Existing file-based XDG state, checkout-local logs, installer ownership records, credential-sync SQLite/leases, GitHub releases, GHCR, and Git pins. No new database or credential store.

**Testing**: Python `unittest`, existing Bash suites, Compose acceptance profiles, Rust `cargo test`, Vitest, OpenSpec strict validation, dependent repository gates, and full GitHub release workflows.

**Target Platform**: Linux, macOS/WSL where already supported, Windows/WSL profile discovery, GitHub Actions, self-hosted release QA, and existing devcontainers.

**Project Type**: Cross-repository product identity and installation compatibility migration.

**Performance Goals**: No new runtime performance requirement; preserve existing startup/discovery behavior and avoid scanning duplicate state trees.

**Constraints**: No automatic state moves, secret access, hosted-Action reliance on redirects, direct vendored edits, historical rewrites, or unapproved registry/repository broadening.

**Scale/Scope**: One current product repository, five directly affected bench workflows, named dependent repositories, 46 existing worktrees, supported 1.5/1.6/1.7 release lines, and separate future cleanup proposals.

## Constitution Check

The repository constitution remains an unexpanded template and adds no concrete gate. The required OpenSpec proposal/design/spec-delta gate passes with `openspec validate rename-workbenches-to-openbenches --strict --no-interactive`. Repository ownership, dev-container execution, host-path, pin, lane, credential, and release rules apply and are checked at every phase. Re-run the same gate after design or contract changes.

## Project Structure

### Documentation (this feature)

```text
openspec/changes/rename-workbenches-to-openbenches/
├── proposal.md
├── design.md
├── tasks.md                    # Speckit handoff only
└── specs/
    ├── product-identity/spec.md
    ├── installation-state-compatibility/spec.md
    └── repository-rename-compatibility/spec.md

specs/033-rename-openbenches/
├── spec.md
├── plan.md
├── research.md
├── quickstart.md
├── contracts/
│   ├── naming-contract.md
│   └── dependent-inventory.md
└── tasks.md                    # Only implementation task list
```

### Source Code (repository root)

```text
bootstrap.sh                       # Canonical clone URL/default and compatibility entrypoints
setup.sh                           # Product display and setup orchestration
scripts/
├── publish-shared-images.py       # Exact old/new publication identity guard
├── shared-images.py               # Historical/new release-asset resolution
├── setup-project-command.py       # Command/flag aliases and ownership preservation
├── tools-command.sh               # Dual environment forwarding
├── lib/                           # Shared compatibility and runtime resolution
└── ...                            # Existing entrypoints plus legacy wrappers
base-image/files/                  # Launcher, profile, and handoff compatibility
devBenches/base-image/             # Upstream-owned integration through pin tooling
config/                            # Release matrix and unchanged schema-v1 contracts
devcontainer.test/                 # Old/new compatibility and acceptance tests
docs/                              # Living migration and release guidance
```

Dependent source changes occur only in their owning repositories. Vendored copies, submodule gitlinks, openRepoKit code/spec revisions, assembly pins, and release locks advance only after the corresponding upstream change lands.

**Structure Decision**: Keep the existing single-repository implementation and its current file layout. Use small compatibility helpers and wrappers rather than a wholesale directory or artifact rename. The separate `openWorkBenches*` three-leg family is not restructured.

## Implementation Sequence

1. **Governance and inventory**: validate OpenSpec, record naming/dependency contracts, confirm owners and release window, and establish a fresh main-based worktree.
2. **Pre-rename safeguards**: add exact dual repository publication identity, old/new dependent discovery, native/WSL manifest fallback, dual environment readers, and compatibility tests. Keep new-slug-only changes reviewed but unmerged.
3. **Slug cutover**: pause affected activity, obtain explicit admin approval, rename the repository, verify rulesets/environments, and immediately land the five bench workflow, alias-table, canonical URL, and current-documentation updates.
4. **Runtime compatibility release**: add branding, command/flag and environment aliases, fresh-install roots, release/runner aliases, and old/new state selection while preserving durable identifiers.
5. **Validation and release**: run focused and dependent tests, fresh/legacy/frozen acceptance, full release validation and applicable protected QA, then publish only the approved tested commit with migration notes.
6. **Cleanup by later proposal**: optional checkout moves, legacy removal, GHCR namespace migration, and any `openWorkBenches*` consolidation remain outside this feature.

## Verification Strategy

Each implementation task names its files and a command that must exit successfully. Phase gates additionally require:

- OpenSpec strict validation and `git diff --check`.
- Focused publisher, transport, installer, profile, launcher, and release tests through the declared runners.
- openRepoProject, openRepoTools, openRepoKit, openProfiler, and five bench workflow gates.
- Fresh canonical, legacy-upgrade, and historical frozen-install acceptance.
- Full Release validation and applicable protected release-mode QA on the exact final head.
- No credential contents in logs, no changed historical releases, and no unapproved registry/repository acceptance.

## Complexity Tracking

No constitution exception is requested. Cross-repository coordination is retained because a single-repository string replacement cannot preserve external installation, release, and runtime contracts.
