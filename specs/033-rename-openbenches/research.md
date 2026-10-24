# Research: Rename workBenches to openBenches

## Baseline

- Implementation base: current `origin/main`; investigation started at `5407ee9`.
- Existing checkout: `feature/profile-onboarding` was not used as the rename base.
- Feature: `033-rename-openbenches`, created with the repository's Speckit linked-worktree extension.
- Target slug `opensoft/openBenches` returned not found during availability checks and must be rechecked at cutover.
- Main has active release automation and 46 registered worktrees across feature, release, and QA lines. Existing checkout directories are not moved.

## GitHub and release behavior

GitHub's rename documentation says web traffic and ordinary `git clone`, `fetch`, and `push` operations redirect to the new repository. It explicitly says hosted Actions do not redirect and warns that recreating the old name breaks redirects. Source: <https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository>.

The external inventory found no `uses: opensoft/workBenches/...` references. Five bench `bench-init.yml` workflows use `actions/checkout` with the old repository and require immediate post-cutover updates: flutterBench, frappeBench, cloudBench, goBench, and phpBench. Their immutable checker commit remains unchanged.

`scripts/publish-shared-images.py` currently restricts publication to `opensoft/workBenches`; it must temporarily accept exactly that slug and `opensoft/openBenches` before cutover. `scripts/shared-images.py` strictly allowlists `ghcr.io/opensoft/workbenches-base` and `workbenches-dev-base` plus schema-v1 manifests and digests. Those packages and historical assets remain unchanged.

Main release automation also uses `workbenches-qa` labels, `WB_*` variables, `/etc/workbenches/release-qa.json`, and an existing `OPENBENCHES_QA_FAILURE_CERT_PEM`. These are deployment interfaces, not cosmetic strings. Supported release lines currently include 1.5, 1.6, and 1.7.

## Checkout and runtime dependents

- openRepoProject `project` resolves `WORKBENCHES_ROOT`, `.workbenches-path`, `~/projects/workBenches`, `~/Projects/workBenches`, and ancestor candidates. It needs new-directory fallback without breaking explicit overrides.
- openRepoKit stores/exports the checkout through its existing `WORKBENCHES_ROOT` ABI. Component, spec, and assembly pins must advance in that order.
- new-workstation `bootstrap` uses `WORKBENCHES_DIR`, a lowercase checkout default, and `~/.config/workbenches`; its private AI-Credentials invocation boundary and recovery identity remain unchanged.
- openProfiler resolves `workbenches/openai-profiles.json` and `workbenches/claude-profiles.json` in native and WSL discovery. It needs one deterministic manifest per provider with legacy fallback, not a merged inventory.
- Install-Wave-Terminal and several scripts have checkout defaults or hard-coded host paths. New discovery must replace host-specific assumptions rather than write another absolute path.
- pyBench and cloudBench mount legacy config/lib/state paths. Their own repositories own the compatibility changes before parent pins advance.
- openRepoTools lane/handoff reads `WORKBENCHES_CLAUDE_*`. Consumers must accept new-first/legacy-fallback values before producers emit both.
- Opensoft-Tenant/AI-Credentials has private provider metadata and restore-path consumers. Owner review is required without exposing inventories or payloads.

## Durable identifiers and non-targets

Do not mechanically change:

- existing GHCR packages, release assets/manifests, schema-v1 IDs, or OCI label keys;
- existing named volumes, `.workbenches-history`, in-image compatibility paths, or live containers;
- Keycloak client/audience identifiers, Key Vault names and `workbenches-operation` tags, stored credential paths, or encrypted payloads;
- project installer lock/payload/journal names and exact historical wrapper bytes;
- generic `workbench` names, the openRepoShape compatibility token, Kubernetes annotations, or `xfactory-workbenches` service identities;
- historical releases, archived specifications, issue references, ratification records, and lane history.

`openWorkBenches*` is a separate next-generation extraction family. `openWorkBenchesCli` identifies current `workBenches` as its extraction source, so consolidation requires a different governance program.

`docs/workbenches-next` contains provisional and accepted future names including `workbenches-setup`, `workbenches-images`, and `workbenchesctl`. Any superseding `openbenches-*` naming decision must be explicit and preserve decision history.

## Implementation constraints confirmed

- Use the declared Tools/dev-bench/container surfaces for project commands and validation; Git operations for the container-created feature worktree run inside `py-bench`.
- Do not edit pinned vendored openRepoTools/openRepoShape files or submodule contents in the assembly. Land upstream changes, then use pin tooling.
- Do not read or print credentials, make model calls for verification, or publish images merely to test the rename.
- GitHub repository rename, QA pausing, merges, publication, and any state migration remain separately gated operations.
