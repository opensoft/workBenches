# Stage 3: Recommended Target Architecture

Status: **provisional recommendation**

## Target Repository Set

| Repository | Primary responsibility | Does not own |
|---|---|---|
| `opensoft/workBenches` | product control plane, schemas, catalog, release lock, orchestration CLI, cross-system docs | Windows UI, foundational Docker recipes, bench-specific tool recipes |
| `opensoft/workbenches-images` | Layer 0, all Layer 1 family images, reusable Layer 3 recipe, image graph tests and provenance | product selection UI, bench-specific Layer 2 releases |
| `opensoft/workbenches-setup` | signed Windows application, host discovery, elevation boundary, reboot/resume, WSL bootstrap, setup UX | container recipes and bench source |
| existing bench repos | one Layer 2 bench, its manifest, setup hooks, tests, and bench docs | shared foundational layers and product-wide compatibility |

The `opensoft/workbenches-setup` name was accepted on 2026-07-26. Other new
repository names remain provisional. The ownership boundaries matter more than
capitalization or hyphenation.

## Product and Build Flow

```text
bench.yaml files                     workbenches-images
in component repos                   source and workflows
        |                                      |
        v                                      v
  component releases ----------------> published OCI images
        |                                      |
        +------------------+-------------------+
                           |
                           v
                workBenches release assembly
                   catalog + release lock
                           |
              +------------+------------+
              |                         |
              v                         v
     workbenches-setup             workbenchesctl
       Windows GUI                    CLI
              |                         |
              +------------+------------+
                           |
                           v
                 user-selected workspace
```

## Image Ownership

```text
workbenches-images
├── layer0/
│   └── workbench-base
├── layer1/
│   ├── dev-bench-base
│   ├── sys-bench-base
│   └── bio-bench-base
├── layer3/
│   └── user-layer
├── docker-bake.hcl
├── tests/
└── docs/
    └── layer-placement-policy.md

individual bench repository
├── Dockerfile.layer2
├── bench.yaml
├── tests/
└── docs or README
```

Keeping the foundational layers together allows the dependency graph to be
validated as one unit. Docker Buildx Bake can describe target dependencies and
shared build settings. Individual Layer 2 repositories consume a versioned or
digest-addressed Layer 1 contract and remain independently releasable.

## Placement Policy

Every installed tool should have one primary layer and a written placement
reason.

| Layer | Placement rule | Typical content |
|---|---|---|
| 0 | needed in nearly every bench or required to operate the platform | Ubuntu base, shell, Git, shared AI CLIs |
| 1 | shared by most benches in one family | developer runtimes, cloud administration tools, bio package substrate |
| 2 | specific to one bench or tightly coupled to its purpose | Rust, .NET, Frappe, Microsoft 365 tooling |
| 3 | host-user identity and permissions only | user, UID/GID, ownership setup |
| runtime | secrets, mutable profiles, and host-specific state | SSH, Git config, Codex/Claude profiles, shell history |

A tool should move downward only when enough consumers require it. Convenience
alone is not a sufficient reason to inflate a shared image.

## Three Metadata Records

### 1. Hand-authored Intent

Each foundational layer has a `layer.yaml`, and each bench has a `bench.yaml`.
These records explain:

- stable component identity,
- family and layer,
- source repository,
- parent image contract,
- tools or capabilities intentionally provided,
- placement rationale,
- required host features,
- supported launch integrations,
- validation commands, and
- maintainers or owning team.

This is reviewable design intent, not generated version evidence.

### 2. Generated Build Receipt

CI creates a receipt for every published image:

- source repository and commit,
- parent image digest,
- resulting image digest,
- build timestamp and workflow identity,
- observed tool versions,
- tests and result,
- software bill of materials reference, and
- provenance or attestation reference.

The existing `config/version-manifest.json` is a useful precursor to the
observed-tool section of this receipt.

### 3. Product Release Lock

The control plane publishes one release lock containing:

- workBenches product version,
- exact catalog revision,
- required setup-app version,
- exact component repository revisions or releases,
- exact OCI image digests,
- compatibility constraints,
- schema versions, and
- release verification status.

The release lock is generated and reviewed. It is the installation contract.

## Candidate Control-Plane Layout

```text
workBenches/
├── catalog/
│   ├── benches.yaml
│   ├── integrations.yaml
│   └── channels.yaml
├── schemas/
│   ├── bench.schema.json
│   ├── layer.schema.json
│   ├── build-receipt.schema.json
│   └── release-lock.schema.json
├── releases/
│   └── <version>.lock.yaml
├── cmd/
│   └── workbenchesctl/
├── docs/
│   ├── architecture/
│   ├── install/
│   └── release/
└── openspec/
```

The exact directory names are proposal details. The important boundary is that
the control plane declares products and compatibility without copying the
component implementations.

## Workspace Materialization

A user-facing command or setup application should:

1. resolve a release channel to an immutable release lock,
2. display catalog choices,
3. preflight host requirements,
4. clone selected repositories when source is needed,
5. refuse to overwrite a dirty or unknown directory,
6. check out exact approved revisions,
7. pull image digests or build only when the selected policy allows it,
8. create compatible Layer 3 images and runtime mounts,
9. install terminal/editor integrations from catalog metadata, and
10. emit a machine-readable health report.

The materialized layout can preserve familiar paths:

```text
~/workbenches/
├── platform/                  optional control-plane checkout
└── benches/
    ├── dev/
    │   ├── pyBench/
    │   └── rustBench/
    ├── sys/
    │   └── cloudBench/
    └── bio/
        └── simBench/
```

Compatibility aliases can preserve `/workspace/projects` behavior inside
containers while the source ownership model changes.

## Windows Application Boundary

The recommended stack for the Windows application is:

- C# on a supported .NET release,
- WinUI 3 / Windows App SDK for the native UI,
- a small, testable orchestration core independent of the UI,
- typed process adapters for `wsl.exe`, PowerShell, Git, and container tooling,
- JSON or YAML contracts generated from the control-plane schemas,
- structured logs and a resumable state journal, and
- a signed installer and release workflow.

The GUI should not translate the full Bash TUI line by line. It should consume
the same catalog and invoke well-bounded operations. Existing scripts can be
wrapped behind those operations during the first migration stages.

### Privilege Model

```text
standard user application
        |
        +--> read-only discovery
        +--> product selection
        +--> progress and logs
        |
        v
short-lived elevated helper
        |
        +--> enable Windows features
        +--> install/configure WSL distribution
        +--> operations requiring administrator authority
```

The elevated surface should be narrow and auditable. Credentials, AI profiles,
and ordinary bench state must not pass through the elevated helper unless a
specific operation requires it.

### Resumable Installation Phases

1. Windows and hardware preflight.
2. WSL feature enablement.
3. reboot checkpoint when required.
4. Ubuntu 24.04 installation and first-user creation.
5. WSL base packages, Zsh, and Oh My Zsh.
6. container runtime readiness.
7. workBenches release resolution.
8. selected source and image materialization.
9. terminal/editor integration.
10. health verification and launch.

Each phase should be idempotent and should record enough state to resume without
guessing.

## Documentation Ownership

| Content | Canonical owner |
|---|---|
| product architecture, catalog, compatibility, release process | `workBenches` |
| layer placement rationale, image build graph, shared image security | `workbenches-images` |
| bench tools, usage, ports, bench-local tests | individual bench repo |
| Windows detection, elevation, WSL setup, installer troubleshooting | `workbenches-setup` |
| operational runbooks for unrelated deployed systems | the owning system or OpsxFactory repo |
| public documentation website | generated from canonical sources |

Images, icons, and UI assets should live with the application or integration
that owns them. Container image binaries should live in an OCI registry.

## CodeXfactory Integration

CodeXfactory should govern the product change as a parent change with linked
component realizations.

```text
workBenches parent change
  |
  +--> workbenches-images change
  +--> workbenches-setup change
  +--> workbenchesctl/control-plane change
  +--> selected bench manifest changes
  +--> documentation relocation changes
```

The parent change owns cross-repository contracts, compatibility criteria, and
release evidence. Component changes own their code and local tests. The parent
is complete only when the release lock points to the exact merged component
revisions and published image digests.

This mirrors the existing xFactory principle that a top-level aggregation
repository owns workspace assembly and compatible pins while domain
repositories own their implementations.

## CI and Supply-Chain Model

- Component repositories test their own manifests and artifacts.
- `workbenches-images` builds the foundational dependency graph.
- Reusable GitHub workflows can centralize common validation without copying
  the workflow logic into every repository.
- Images are published by digest to GHCR.
- Build provenance and artifact attestations are attached to releases.
- `workBenches` integration CI validates a candidate release lock across a
  representative matrix of benches.
- A release is promoted only after the lock and evidence are committed.

Official implementation references:

- Docker build contexts:
  <https://docs.docker.com/build/concepts/context/>
- Docker Buildx Bake:
  <https://docs.docker.com/build/bake/>
- GitHub reusable workflows:
  <https://docs.github.com/en/actions/how-tos/reuse-automations>
- GitHub Container Registry:
  <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>
- GitHub artifact attestations:
  <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations>

## Security Boundaries

- No credentials or AI profile material enters a container image, catalog, or
  release lock.
- Runtime credential mounts remain separate from image publication.
- Release locks identify artifacts, not secret locations.
- Windows elevation is task-scoped.
- Workspace synchronization is non-destructive by default.
- CI publication requires repository-specific authority; a parent workflow
  cannot silently broaden permissions across components.
- `latest` tags are convenience aliases, never sufficient production release
  evidence.
