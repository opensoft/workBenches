# Stage 2: Repository and Delivery Options

Status: **brainstorm with provisional recommendation**

## Decision Principle

A repository boundary should follow ownership, release cadence, security
boundary, and independent consumption. A directory name or number of files is
not enough reason to create a repository.

## Option A: Keep the Current Aggregation Model

Keep foundational image recipes, setup scripts, docs, and submodule pins in
`workBenches`. Continue adding each bench below its family folder.

Advantages:

- smallest immediate migration,
- familiar checkout layout,
- one clone exposes most of the system, and
- simple relative paths for existing scripts.

Costs:

- submodule state remains part of the user installation contract,
- Windows setup remains coupled to the Linux/Bash implementation,
- catalog drift remains easy,
- foundational-image changes and bench changes are hard to release as a
  coherent immutable set, and
- the root repository keeps collecting unrelated responsibilities.

This is viable as a temporary state, not a strong long-term product boundary.

## Option B: Make Each Family Folder a Repository

Create repositories such as `devBenches`, `sysBenches`, and `bioBenches`.
Place each family base image and all of that family's Layer 2 benches in the
family repository.

Advantages:

- the directory and repository concepts align,
- each family can have its own maintainers and CI, and
- Layer 1 and Layer 2 changes can be tested together within a family.

Costs:

- existing independently released benches lose clean boundaries or become
  nested submodules,
- Layer 0 and Layer 3 still couple all three family repositories,
- cross-family base changes require coordinated releases anyway,
- making only `devBenches` a repository creates an asymmetric model, and
- user installation still needs either submodules or custom materialization.

This is reasonable only if a whole family has one owner and one release cadence.
That is not the current shape.

## Option C: Product Control Plane plus Component Repositories

Keep `workBenches` as the product control plane. Move the coupled foundational
image graph to one image repository. Keep independently released Layer 2
benches in their own repositories. Give the Windows application its own
repository.

Advantages:

- ownership follows actual release and security boundaries,
- the shared image dependency graph can be built and tested together,
- the Windows application can use an appropriate toolchain and signing flow,
- each bench can publish independently,
- product releases can pin exact compatible revisions and image digests, and
- end-user installation no longer depends on Git submodule expertise.

Costs:

- requires schemas and release automation,
- cross-repository changes need explicit orchestration,
- existing scripts need a compatibility period, and
- local developer workspace assembly must be replaced or retained as an
  optional convenience.

**Provisional recommendation:** choose Option C.

## Comparison

| Criterion | A: current aggregation | B: family repos | C: control plane + components |
|---|---:|---:|---:|
| Smallest migration | high | medium | low |
| Clear ownership | low | medium | high |
| Independent bench release | medium | low/medium | high |
| Coherent base-image release | medium | medium | high |
| Windows app isolation | low | low | high |
| Reproducible product release | low | medium | high |
| End-user simplicity | low | low/medium | high |
| CodeXfactory traceability | medium | medium | high |

## Should `devBenches` Become Its Own Repository?

Not as a wholesale container for every developer bench.

`devBenches` currently expresses two different concepts:

1. a product classification: developer-oriented benches, and
2. a source path: a folder holding several independent repositories.

Those concepts should be separated. The classification belongs in the product
catalog. Source ownership belongs to each component repository.

If the developer Layer 1 base ever needs its own repository, use a name that
states the owned artifact, such as `dev-bench-base`. Creating a repository
called `devBenches` would suggest ownership of all developer benches and would
reintroduce ambiguity.

The same rule should apply symmetrically to system and bio families.

## Foundational Image Alternatives

### One Repository for Layer 0, Layer 1, and Layer 3

This is the provisional recommendation because:

- all family bases inherit Layer 0,
- Layer 3 must remain compatible with any selectable Layer 2 image,
- a base update needs cascade testing, and
- one build graph can express dependencies and publish a tested set.

### One Repository per Layer or Family

This offers smaller permissions and independent ownership, but adds a release
coordination problem before the current build graph has a formal contract.
It can be revisited if team ownership or release cadence actually diverges.

## Source Checkout Alternatives

### Git Submodules as the Product Contract

Pros:

- native exact commit pins,
- familiar to advanced Git users, and
- already used by the repository.

Cons:

- recursive clone/update behavior is easy to miss,
- detached heads and dirty submodules confuse normal users,
- optional bench selection is awkward, and
- submodule registration does not express image or host requirements.

### Catalog plus Workspace Materialization

The control plane reads a catalog and release lock, then clones only selected
repositories to exact revisions.

Pros:

- supports optional products,
- allows clear errors and recovery,
- separates product selection from Git topology,
- is usable by GUI and CLI installers, and
- can preserve the current local folder layout.

Cons:

- requires a new synchronization implementation,
- must handle local changes safely, and
- must never overwrite an existing checkout implicitly.

**Provisional recommendation:** use catalog materialization for normal users.
An aggregation repository with submodules may remain as an internal developer
convenience, but it should not define the public install contract.

## Documentation Alternatives

### One Dedicated Documentation Repository

This can simplify publishing but tends to separate component behavior from the
code that changes it. It is useful for a generated public site, not as the only
canonical source.

### Documentation with the Owning Component

This keeps behavior and documentation versioned together.

**Provisional recommendation:**

- cross-system architecture and release policy live in `workBenches/docs`,
- foundational layer rationale lives in `workbenches-images/docs`,
- bench-specific tools and usage live in each bench repository,
- Windows bootstrap behavior lives in `workbenches-setup/docs`, and
- a public documentation site is generated from these canonical sources.

## Binary Artifact Alternatives

Container images should be published to GHCR or another OCI registry. Git
should contain recipes, metadata, and evidence links, not image archives.

Compatibility installs should use immutable image digests. Human-friendly tags
such as `latest` or release aliases can remain available for exploration, but
must not be the only identity in a product release.
