# Stage 5: Proposal Readiness

Status: **draft input for a future OpenSpec proposal**

This is not an OpenSpec proposal. It is the review surface used to decide
whether the architecture is ready to become one.

## Candidate Parent Change

Suggested change name:

```text
restructure-workbenches-product-boundaries
```

Candidate problem statement:

> workBenches currently conflates product selection, Git aggregation,
> foundational image ownership, platform setup, and component implementation.
> Its catalogs disagree, normal installation depends on checkout topology, and
> releases are not expressed as an immutable compatible set. Establish a
> product control plane, explicit component contracts, and staged migration
> boundaries before building the Windows setup application.

## Candidate Capabilities

### `component-catalog`

Defines stable bench identities, source repositories, families, images,
integrations, host requirements, and validation metadata.

### `layer-placement-policy`

Defines what belongs in Layers 0 through 3 and runtime state, including a
reviewable rationale for each shared tool.

### `image-build-and-provenance`

Defines foundational image dependency builds, immutable publication,
generated receipts, tests, SBOM references, and attestations.

### `release-lock`

Defines a product version as an exact compatible set of component revisions,
image digests, schema versions, and minimum installer version.

### `workspace-materialization`

Defines safe, optional checkout of selected component repositories without
making submodules an end-user requirement.

### `windows-bootstrapper-contract`

Defines Windows discovery, privilege separation, WSL 2 and Ubuntu 24.04 setup,
reboot/resume, shell setup, product selection, progress, logs, and final
health.

### `documentation-ownership`

Defines where product, image, bench, installer, and operational documentation
are canonical and how a consolidated site is generated.

## External xFactory Dependency

The company project catalog is an xFactory runtime capability, not a
workBenches product-control-plane capability. Its neutral brainstorm lives in
`openxFactory/ideation/brainstorm/tenant-project-catalog-and-workstation-cache.md`;
the workBenches consumer boundary is recorded in
[60-xfactory-project-catalog-integration.md](60-xfactory-project-catalog-integration.md).

The later xFactory proposal is expected to own:

- the tenant-authoritative project and project-to-repository catalog;
- principal visibility and assignment projections;
- the portable `.xfactory/project.yaml` contract;
- the tenant/principal-scoped workstation cache contract; and
- the single-selected-Project-Hermes request boundary.

The workBenches proposal should consume those contracts after they are
accepted. It must not duplicate company projects, memberships, or credentials
inside the component catalog or release lock.

## Provisional Decision Register

| ID | Decision | Status |
|---|---|---|
| D1 | `workBenches` becomes the product control plane | proposed |
| D2 | Layer 0, all Layer 1 families, and Layer 3 move together to `workbenches-images` | proposed |
| D3 | the Windows application lives in `opensoft/workbenches-setup` | **accepted 2026-07-26** |
| D4 | independent Layer 2 benches remain independent repositories | proposed |
| D5 | `devBenches` remains a catalog family/path classification, not a repository owning all developer benches | proposed |
| D6 | normal user installs use catalog materialization, not submodules | proposed |
| D7 | image digests and exact source revisions define compatibility releases | proposed |
| D8 | `latest` remains convenience-only | proposed |
| D9 | canonical docs live with the owning component; public docs are generated | proposed |
| D10 | CodeXfactory uses one parent change plus linked component changes | proposed |

## Open Decisions

These questions should be answered before the parent proposal is generated:

1. Is the proposed `opensoft/workbenches-images` repository name accepted?
2. Does `workBenches` retain a developer-only submodule view, or should that
   move to a separate internal aggregation repository?
3. Which container runtime is the supported Windows default:
   Docker Desktop, Docker Engine inside WSL, or a pluggable choice?
4. Does the first release lock point only to published images, or may it also
   permit local builds under an explicit development policy?
5. Which benches are in the first supported catalog and which are
   experimental?
6. Is `workbenchesctl` implemented in the control-plane repository or as its
   own repository?
7. What is the minimum supported Windows version and edition?
8. What installer packaging and signing format is required for the first
   public release?
9. Which current documents have confirmed owners outside workBenches?
10. Who ratifies a product release lock in CodeXfactory?
11. Is xFactory project registration and first catalog sync part of the first
    `workbenches-setup` release or a linked follow-on?

## Proposal Scope Recommendation

The first parent proposal should:

- establish ownership boundaries,
- create the catalog and metadata schemas,
- define release-lock semantics,
- define layer placement policy,
- define workspace-materialization safety,
- define the Windows bootstrapper contract,
- define staged acceptance gates, and
- preserve current setup behavior through compatibility adapters.

It should not:

- create every new repository,
- move every Dockerfile,
- ship the Windows application,
- migrate every bench,
- remove submodules, or
- publish a production release.

Those are linked realizations after the contracts are accepted.

## Candidate Acceptance Criteria

The proposal is implementable when it can require that:

- every supported bench has one stable catalog identity;
- duplicate, missing, or contradictory topology is rejected by validation;
- every tool placement has an owner and rationale;
- every published image can be traced to a source commit and parent digest;
- every product release resolves to immutable component and image identities;
- the setup UI and CLI can consume the same product definition;
- workspace synchronization refuses destructive operations on unknown or dirty
  directories;
- Windows setup can resume after reboot and can report partial failure;
- existing supported users retain a compatibility path during migration; and
- no credentials are placed in images, catalogs, release locks, receipts, or
  normal logs.

If xFactory project-catalog integration is included in the first release, the
linked proposal must additionally require that:

- workBenches publishes a schema-valid project manifest that cannot grant
  access;
- setup uses native Windows/WSL configuration, state, and cache locations;
- the company runtime remains the authority for projects and assignments;
- cached catalog data carries tenant, principal, revision, digest, and
  freshness metadata; and
- Windows and WSL use one defined catalog-sync owner rather than divergent
  writable copies.

## Linked Component Changes

After the parent proposal is accepted, likely child changes are:

1. `workBenches`: add catalog, schemas, compatibility validation, and release
   lock.
2. `workbenches-images`: establish the foundational build graph and receipts.
3. `pyBench`: add the reference Layer 2 manifest and validation.
4. `rustBench`: prove the same contract for a recent Tauri-capable bench.
5. `cloudBench`: prove the contract for a system-family bench.
6. one bio bench: prove the family-neutral aspects of the contract.
7. `workbenches-setup`: build the Windows bootstrapper against the accepted
   contract.
8. `workBenches`: add workspace materialization and migrate integrations.
9. owning repositories: relocate operational and component documentation.
10. `openxFactory`/codexFactory: separately propose and realize the tenant
    project catalog and workstation projection before workBenches consumes it.

Each child change should define its own repository-local tests. The parent
change should define cross-component compatibility evidence and the final
release-lock gate.

## Evidence to Gather During Proposal Authoring

- complete supported-bench inventory,
- current image publication workflows and registry names,
- current Windows version and container-runtime support policy,
- representative clean-install and upgrade paths,
- Wave Terminal and VS Code integration inputs,
- image build times and storage impact,
- source history that must be preserved during extraction,
- existing GitHub permissions and signing capabilities, and
- the set of docs with no confirmed owner.

## Ready-to-Raise Checklist

- [ ] Ratify or revise D1 through D10.
- [x] Accept `opensoft/workbenches-setup` as the Windows application
  repository name.
- [ ] Resolve the open decisions that affect scope.
- [ ] Identify the parent proposal owner in CodeXfactory.
- [ ] Initialize OpenSpec in `workBenches`.
- [ ] Confirm the first supported bench set.
- [ ] Confirm the Windows support and container-runtime policy.
- [ ] Confirm that this discovery pack is the input, not the authority.
- [ ] Generate the parent proposal, design, capability specs, and tasks.
- [ ] Validate the proposal strictly before any implementation begins.

## Suggested Next Action

Review the provisional decisions and answer the open questions that materially
affect the first proposal. Then use the OpenSpec proposal workflow to create
`restructure-workbenches-product-boundaries` in `workBenches`.
