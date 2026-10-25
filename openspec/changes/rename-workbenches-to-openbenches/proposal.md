# Proposal

## Why

The current `workBenches` product and repository need the canonical identity `openBenches`, but the old name is embedded in repository URLs, installed commands, environment contracts, state paths, release automation, and dependent tooling. A one-step replacement would break existing workstations and historical releases, so the rename must be a staged compatibility migration.

## What Changes

- Rename `opensoft/workBenches` to `opensoft/openBenches` during a controlled administrative cutover after dependent safeguards land.
- Make `openBenches`, `openbenches`, and `OPENBENCHES_*` canonical for product display, fresh installations, and new aliases while preserving legacy behavior during the support window.
- Add deterministic old/new checkout, environment, command, configuration-root, profile-manifest, and launcher-handoff resolution.
- Update direct dependent references and release publication guards in consumer-first order, preserving immutable checker commits and pin governance.
- Preserve existing checkout directories, credentials, sessions, Docker state, schema-v1 identifiers, GHCR repositories, release assets, and historical records.
- Validate fresh canonical installs, legacy upgrades, supported release lines, dependent workflows, and the full release gate before the first `openBenches` release.
- No compatibility-breaking removal is authorized by this change. Legacy removal, GHCR namespace migration, and `openWorkBenches*` consolidation require separate proposals.

## Capabilities

### New Capabilities

- `product-identity`: canonical `openBenches` naming and backward-compatible command, environment, documentation, and fresh-install aliases.
- `installation-state-compatibility`: preservation and deterministic resolution of existing checkouts, configuration, credentials, persistent runtime state, schemas, and release artifacts.
- `repository-rename-compatibility`: safe GitHub slug cutover, dependent-reference migration, publication identity checks, redirect validation, and cross-version release continuity.

### Modified Capabilities

None. The existing canonical specs cover Claude behavior that this change preserves rather than redefines.

## Impact

Affected systems include the current repository and its setup/release tooling; openRepoProject, openRepoTools, openRepoKit, openProfiler, new-workstation, Install-Wave-Terminal, selected bench repositories and their pins; profile manifests and launcher handoffs; GitHub rulesets, environments, workflows, and runner configuration; and fresh-install/upgrade documentation. Deployed identity-provider credentials, secret payloads, published tags, old release assets, and the separate `openWorkBenches*` extraction family are explicitly out of scope for destructive or automatic migration.

Implementation is handed off to the single Speckit feature `specs/033-rename-openbenches/`.
