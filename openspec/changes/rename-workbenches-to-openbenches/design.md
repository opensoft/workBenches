# Design

## Context

`workBenches` is both a GitHub repository and an installed product identity. It has active feature/release worktrees, published and draft releases, GHCR packages, protected QA, and consumers that resolve either its repository slug or its checkout path. The separate `openWorkBenches*` assemblies are an extraction destination, not part of this rename. Brett Heap authorized implementation of the staged plan on 2026-10-24.

## Decisions

### D1: Separate slug cutover from runtime migration

Prepare safeguards first, rename the GitHub slug without moving checkouts or runtime state, update direct references, then ship runtime naming in a compatibility release. GitHub redirects are a temporary bridge for web and ordinary Git traffic, never the final reference state. Do not recreate `opensoft/workBenches`, which would break redirects. No current external hosted-Action dependency is known; recheck before cutover.

### D2: Use one naming policy

- Canonical repository/display: `openBenches`.
- Canonical fresh checkout: `~/Projects/openBenches`; existing checkout basenames remain valid.
- Canonical environment prefix: `OPENBENCHES_*`.
- New command aliases include `setup-openbenches`, `openbenches-mcp-sync`, and `openbenches-credential-sync`; new flag aliases include `--openbenches` and `--openbenches-root`.
- Fresh config/cache/data roots use `openbenches` only after dependent mount and discovery support is released.
- Generic `workbench` concepts and separately governed future repository names are not mechanical replacements. Future `openbenches-setup`, `openbenches-images`, and `openbenchesctl` names require an explicit superseding decision in the relevant proposal.

Environment resolution is new value, then legacy `WORKBENCHES_*` or existing `WB_*`, then default. Equal dual values are accepted. Conflicting old/new paths, endpoints, credential configuration, and release configuration fail explicitly rather than selecting ambiguous state.

### D3: Preserve state and durable contracts

An existing old root remains in legacy-root mode; a new root uses new-root mode. Both roots are never merged. An explicit configured root wins subject to the conflict rule; ambiguous stateful startup with both roots must offer a deterministic selection or refuse. No automatic checkout, credential, session, or live-agent migration occurs.

The credential-sync agent retains one agent, lock, and lease root. Any later explicit migration stops and drains the old agent first and is separately authorized.

Keep existing GHCR repositories, old release manifests, OCI label keys, schema-v1 `$id`/`kind` values, Docker volumes and `.workbenches-history`, Keycloak and Key Vault identifiers, stored credential paths, installer lock/payload/journal names, and exact historical generated-byte fixtures. New images may update `org.opencontainers.image.source`; old images and release assets are never rewritten. A GHCR namespace change is a separate proposal.

### D4: Migrate consumers before producers

Land old/new checkout discovery and environment readers before producers emit new names. Specifically:

1. openRepoProject, openRepoKit, new-workstation, Install-Wave-Terminal, pyBench/cloudBench, and openProfiler accept either existing identity.
2. openRepoTools lane/handoff consumers accept `OPENBENCHES_CLAUDE_*` with legacy fallback before the launcher emits both forms.
3. The shared-image publisher temporarily allowlists exactly `opensoft/workBenches` and `opensoft/openBenches`; active release lines that may publish receive the same guard.
4. Direct new-slug changes are prepared but merged only when the new slug exists.
5. Upstream changes land before vendored pins, child gitlinks, openRepoKit component/spec revisions, assembly pins, or release locks advance.

openProfiler selects one manifest per provider with new-first/legacy-fallback behavior in native and WSL discovery. It never merges old/new inventories or duplicates profiles. Manifest v1 remains unchanged.

### D5: Keep a controlled administrative cutover

Pause affected scheduled QA/release activity and let active runs finish. Recheck target-name availability and hosted-Action references. An org owner/repository admin performs the rename only after explicit cutover approval. Keep `main`, branches, tags, environments, rules, and releases. Rename only the display text of the repository tag ruleset, not its rules.

Immediately update the five bench checkout repository fields, openRepoTools and live alias tables, current documentation links, canonical bootstrap/release links, and local remotes. Preserve immutable checker commits and lane history. Do not rename the 46-worktree layout; an optional later checkout move uses park/fresh-clone procedures, installer regeneration, and `git worktree repair` as applicable.

### D6: Validate old and new behavior as a matrix

Tests must cover old/new/both checkout and config roots, explicit overrides, equal/conflicting environment pairs, old/new commands, foreign-command collisions, mixed-version handoff, one credential-sync agent, old release artifacts, unsupported registries, native/WSL profile discovery, fresh canonical install, legacy upgrade, and supported 1.5/1.6/1.7 source lines.

The shared-image publisher is not a test target. The first `openBenches` release requires the full release workflow and applicable protected QA on its exact tested commit. Old releases are never retagged or edited.

### D7: Deprecation is separate

Recommended alias support is 90 days or two release cycles, whichever is longer; cheap read fallbacks and persistent identifiers may remain indefinitely. Removal requires a later approved major/deprecation change after clean-install and upgrade evidence. This change does not authorize legacy deletion, credential rotation, GHCR namespace migration, or `openWorkBenches*` consolidation.

### D8: Fail closed across the credential composition boundary

Root discovery alone is insufficient for credential composition: older workBenches installers and launchers still write or read legacy defaults even when a composer emits a manifest into a new root. Non-legacy delegation therefore requires the selected workBenches and AI-Credentials helpers to advertise `openbenches-config-root-v1` through their explicit capability queries. The parent passes equal old/new checkout and config-root variables and the exact preflighted recovery identity; AI-Credentials rechecks workBenches capability after checkout updates and before SOPS installation or manifest composition. Missing or incompatible capabilities refuse before manifest writes. Legacy-default operation requires neither capability and retains existing behavior.

The workBenches capability is part of the runtime implementation, not a declaration to add ahead of correctness. Advertise it only after all affected installers and launchers honor the selected root and synthetic parent/child tests prove that new-root operation never reads or writes legacy manifests or identities. No real new-root provisioning is authorized by the dependent compatibility PRs alone.

## Consequences

The migration requires coordinated PRs and a quiet administrative window, but avoids a cross-repository flag day. Existing users keep their checkout and state while new installations can adopt `openBenches` after dependent compatibility is proven. Rollback primarily rolls code forward through retained aliases rather than restoring moved data.
