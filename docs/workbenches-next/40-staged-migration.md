# Stage 4: Staged Migration

Status: **provisional sequence**

The migration should preserve a working installer at every stage. Each stage
has an explicit exit gate, and removal work occurs only after the replacement
has been exercised.

## Stage 0: Ratify Product Boundaries

Deliverables:

- approve or revise the repository ownership model,
- select the remaining repository names
  (`opensoft/workbenches-setup` is accepted),
- decide whether the optional internal submodule aggregator remains,
- decide the first release-lock format, and
- identify the owner of the Windows application.

Exit gate:

- the decision register in
  [50-proposal-readiness.md](50-proposal-readiness.md) contains no unresolved
  question that would materially change proposal scope.

No runtime changes occur in this stage.

## Stage 1: Establish the Control-Plane Contracts

Deliverables:

- initialize OpenSpec in `workBenches`,
- create schemas for bench, layer, build receipt, and release lock,
- create a canonical catalog that includes every supported bench,
- add schema and cross-reference validation, and
- document compatibility and deprecation policy.

Compatibility behavior:

- existing `config/bench-config.json` remains available,
- current setup scripts continue to operate, and
- generated compatibility views may be added instead of editing every
  consumer immediately.

Exit gate:

- one command validates the catalog, schemas, and current repository mapping;
- all currently supported benches are represented exactly once.

## Stage 2: Make Existing Setup Consume the Catalog

Deliverables:

- extract catalog reading from the Bash TUI,
- make bench discovery, repository URL, source path, and image identity come
  from the canonical catalog,
- add non-destructive checkout guards, and
- add machine-readable setup results.

Exit gate:

- the current Linux/WSL setup path can install a selected bench solely from
  catalog data;
- catalog and `.gitmodules` disagreement is a failing validation, not a hidden
  condition.

Rollback:

- retain the previous config adapter until the catalog-backed path is proven.

## Stage 3: Extract and Publish Foundational Images

Deliverables:

- create `workbenches-images`,
- move Layer 0, all Layer 1 recipes, and the Layer 3 recipe with history where
  practical,
- define the dependency graph,
- publish digest-addressed test images,
- generate build receipts, and
- run cascade tests against representative Layer 2 benches.

Exit gate:

- every foundational image is published by digest;
- a clean runner can verify labels, critical tools, and Layer 3 compatibility;
- current local aliases remain available during the transition.

Rollback:

- the last release lock continues pointing to the previous known-good images.

## Stage 4: Add Bench Manifests

Deliverables:

- add `bench.yaml` to each supported Layer 2 repository,
- validate parent-image compatibility and required integrations,
- document each bench's placement rationale and verification commands, and
- publish bench images with receipts where applicable.

Suggested rollout order:

1. `pyBench` as the mature developer example,
2. `rustBench` as the recent developer example,
3. `cloudBench` as the system-family example,
4. one bio bench,
5. remaining supported benches.

Exit gate:

- the central catalog can verify every selected bench against its repository
  manifest and published image.

## Stage 5: Build the Windows Setup Application

Deliverables:

- create `workbenches-setup`,
- implement read-only host discovery first,
- add state-journal and reboot-resume behavior,
- wrap current setup operations behind typed adapters,
- implement WSL 2 and Ubuntu 24.04 bootstrap,
- configure Zsh and Oh My Zsh,
- consume the product catalog and release lock,
- show progress, logs, recovery actions, and final health, and
- establish signed CI releases.

Exit gate:

- a clean supported Windows test machine can complete installation;
- an already-configured machine is idempotent;
- a required reboot resumes safely;
- failure leaves a readable log and does not corrupt existing WSL
  distributions or source checkouts.

Rollback:

- the setup application can direct advanced users to the existing supported
  WSL setup path for the same release lock.

## Stage 6: Introduce Workspace Materialization

Deliverables:

- implement `workbenchesctl sync` or equivalent shared orchestration,
- clone selected benches to exact revisions,
- detect dirty, diverged, missing, and unknown directories,
- preserve the current local folder layout where required, and
- expose the same operation to the Windows application.

Exit gate:

- normal users can install and update selected benches without submodule
  commands;
- no operation overwrites local changes;
- exact release-lock revisions are verifiable after setup.

## Stage 7: Move Integrations to Catalog Identity

Deliverables:

- update Wave Terminal, VS Code, and other launch integrations to resolve
  benches by stable catalog identity,
- remove assumptions that a bench is necessarily a child Git submodule, and
- test upgraded and clean installations.

Exit gate:

- a bench launches correctly whether its source was materialized from a
  release lock or checked out by a developer in a supported custom location.

## Stage 8: Retire Submodules from the Public Install Contract

Deliverables:

- stop adding new public-install submodules,
- mark legacy submodule instructions as developer-only or deprecated,
- remove Git links only after all supported consumers use catalog
  materialization, and
- optionally retain a separate internal aggregation repository.

Exit gate:

- clean install, upgrade, repair, and uninstall flows no longer depend on
  recursive submodule operations;
- the release lock provides equivalent or better exact-revision evidence.

Rollback:

- release locks and component repositories are immutable; the last known-good
  installer can continue to materialize its exact set.

## Stage 9: Relocate and Publish Documentation

Deliverables:

- move component-specific docs to their owning repositories,
- move unrelated operational docs to their actual system owners,
- leave redirects or relocation notes where useful,
- generate a consolidated public documentation site, and
- archive this discovery pack into the approved architecture records.

Exit gate:

- every published document has a declared canonical owner;
- generated public docs link back to a versioned source.

## Cross-stage Verification Matrix

| Concern | Required proof |
|---|---|
| compatibility | release lock resolves every selected component and parent image |
| reproducibility | clean machine uses exact commits and image digests |
| safety | dirty or unknown checkout is never overwritten |
| secrets | catalog, receipts, images, and logs contain no credentials |
| Windows recovery | reboot and interrupted runs resume or roll back cleanly |
| image provenance | source revision and digest are linked by generated evidence |
| integration | Wave/VS Code launch by catalog identity |
| documentation | owning repository and canonical path are explicit |

## Changes That Must Not Be Bundled Prematurely

- repository creation and historical migration,
- complete Windows UI implementation,
- all bench manifest migrations,
- submodule removal,
- operational documentation relocation, and
- product release promotion.

The parent proposal should define the contracts and stage gates. Component
realizations can then be raised as linked changes with their own evidence.
