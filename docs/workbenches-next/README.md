# workBenches Next Architecture Discovery Pack

Status: **brainstorm / pre-proposal**

Date captured: 2026-07-26

This directory records the repository, image, installer, documentation, and
release architecture discussion for the next generation of workBenches. It is
deliberately separate from the current operational documentation and from an
OpenSpec change.

Nothing in this directory authorizes a repository split, image migration,
installer release, submodule removal, or other implementation work. Statements
marked **provisional** are recommendations to ratify before a proposal is
raised.

## Reading Order

1. [00-brief.md](00-brief.md) — goals, constraints, and scope.
2. [10-current-state.md](10-current-state.md) — repository-grounded inventory
   and the problems it exposes.
3. [20-brainstorm-options.md](20-brainstorm-options.md) — structural options
   and tradeoffs.
4. [30-recommended-target-architecture.md](30-recommended-target-architecture.md)
   — the provisional target model.
5. [40-staged-migration.md](40-staged-migration.md) — a reversible migration
   sequence with stage gates.
6. [50-proposal-readiness.md](50-proposal-readiness.md) — decisions, open
   questions, candidate capabilities, and the checklist for raising the
   OpenSpec proposal.
7. [60-xfactory-project-catalog-integration.md](60-xfactory-project-catalog-integration.md)
   — boundary between the company-authoritative xFactory project catalog and
   the workstation/setup-app projection consumed by workBenches.

## Document Lifecycle

```text
brainstorm
    |
    v
decision review
    |
    v
OpenSpec proposal
    |
    v
approved implementation
    |
    v
release and migration
    |
    v
archive into canonical architecture docs
```

The documents in this directory occupy the first box. Once the choices in
[50-proposal-readiness.md](50-proposal-readiness.md) are ratified, the material
can be transformed into a governed OpenSpec proposal. The proposal, rather
than this brainstorm, will define approved scope and acceptance criteria.

## Working Vocabulary

- **Control plane**: the product catalog, schemas, release lock, orchestration
  CLI, and cross-component contracts.
- **Foundational images**: Layer 0, the Layer 1 family images, and the reusable
  Layer 3 user-image recipe.
- **Bench**: a selectable, domain-specific development or operations
  environment, normally owning a Layer 2 image.
- **Catalog**: the hand-authored list of available benches, their repositories,
  families, image identities, and integration metadata.
- **Release lock**: the generated, immutable compatibility set used for a
  product release.
- **Build receipt**: generated evidence about an image build, including source
  revision, content digest, observed tool versions, and verification results.
- **Workspace materialization**: cloning or updating selected bench
  repositories from the catalog and release lock, without requiring the user
  to operate Git submodules.

## Current Recommendation in One Sentence

**Provisional:** keep `workBenches` as the product control plane, move the
coupled foundational image graph into one `workbenches-images` repository,
build the Windows bootstrapper in a separate `workbenches-setup` repository,
retain independently released Layer 2 benches in their own repositories, and
replace the end-user submodule contract with a catalog plus an immutable
release lock.
