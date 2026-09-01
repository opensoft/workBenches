# Stage 1: Current-State Inventory

Status: **observed snapshot**

Snapshot date: 2026-07-26

This document distinguishes repository evidence from architectural
recommendations. The facts below were observed in the current
`workBenches` checkout; they are not claims about every remote repository or
published image.

## Current Product Shape

```text
workBenches
├── setup.sh                         host setup and orchestration
├── scripts/interactive-setup.sh     Bash TUI and component actions
├── config/bench-config.json         selectable bench catalog
├── config/version-manifest.json     observed tool-version snapshot
├── base-image/                      Layer 0
├── devBenches/
│   ├── base-image/                  Layer 1a
│   └── <bench>/                     Layer 2 repos/checkouts
├── sysBenches/
│   ├── base-image/                  Layer 1b
│   └── <bench>/                     Layer 2 repos/checkouts
├── bioBenches/
│   ├── base-image/                  Layer 1c
│   └── <bench>/                     Layer 2 repos/checkouts
├── user-layer/                      reusable Layer 3 recipe
└── docs/                            product, setup, profile, and ops docs
```

## Image Graph

The current canonical layer model is:

```text
ubuntu:24.04
     |
     v
workbench-base:latest                         Layer 0
     |
     +----------------+----------------+
     |                |                |
     v                v                v
dev-bench-base   sys-bench-base   bio-bench-base  Layer 1
     |                |                |
     v                v                v
language benches  cloud/365/ops   genomics/sim    Layer 2
     |                |                |
     +----------------+----------------+
                      |
                      v
           <bench>:<username>                   Layer 3
                      |
                      v
        runtime mounts and user credentials
```

Relevant sources:

- Layer 0: `base-image/Dockerfile`
- Developer Layer 1: `devBenches/base-image/Dockerfile`
- System Layer 1: `sysBenches/base-image/Dockerfile`
- Bio Layer 1: `bioBenches/base-image/Dockerfile`
- Layer 2 examples:
  `devBenches/pyBench/Dockerfile.layer2`,
  `devBenches/rustBench/Dockerfile.layer2`, and
  `sysBenches/cloudBench/Dockerfile.layer2`
- Layer 3: `user-layer/Dockerfile`

This is one dependency graph even though its recipes are distributed across
the aggregation repository and nested bench repositories.

## Current Git Topology

Eight paths are registered as Git submodules:

| Family | Registered submodules |
|---|---|
| dev | `cppBench`, `dotNetBench`, `goBench`, `javaBench`, `pyBench`, `rustBench` |
| sys | `365Bench`, `cloudBench` |
| bio | none |

Six additional bench folders are independent Git checkouts but are not
registered as submodules in this checkout:

| Family | Independent, unregistered checkouts |
|---|---|
| dev | `flutterBench`, `frappeBench`, `phpBench` |
| sys | `opsBench` |
| bio | `gentecBench`, `simBench` |

An empty `devBenches/pythonBench` directory is also present locally. It is not
tracked and should not be treated as a product component.

This mixed state means the directory tree alone does not reveal whether a
bench is:

- owned by the aggregation repository,
- a pinned submodule,
- an independently updated checkout,
- ignored local workspace content, or
- part of the installable product.

## Catalog Drift

`config/bench-config.json` currently lists:

```text
cloudBench, cppBench, dotNetBench, flutterBench, frappeBench,
gentecBench, javaBench, pyBench, simBench
```

It does not list the registered `goBench`, `rustBench`, or `365Bench`
submodules. It also does not list the locally present `phpBench` or `opsBench`
repositories.

Conversely, `.gitmodules` knows about source locations and pins, but it does
not carry product metadata such as:

- bench family,
- image identity,
- user-facing description,
- compatible foundational-image release,
- integration capabilities,
- required host features,
- install channel, or
- verification policy.

The catalog and `.gitmodules` therefore serve overlapping but incomplete
roles.

## Current Setup Responsibilities

The root `setup.sh` currently coordinates:

- log creation,
- shell environment setup,
- AI workflow/profile setup,
- Docker discovery or installation guidance,
- Layer 0 creation,
- Wave Terminal widget setup,
- the interactive selector,
- selected component actions, and
- Layer 1 builds for detected bench families.

The Bash TUI in `scripts/interactive-setup.sh` currently manages three visible
groups:

- benches,
- AI assistants and specification tools, and
- workstation tools such as VS Code, Warp, Wave, and VPN clients.

It also contains logic for:

- Windows program detection from WSL,
- cloning and updating bench repositories,
- deciding whether a directory is safe to replace,
- running bench-local setup or build scripts,
- checking Layer 2 and Layer 3 images,
- credential prompts, and
- installing Windows-facing tools through helper scripts.

This is valuable implementation knowledge, but it also means the user
interface, product catalog, host discovery, mutation engine, credentials, Git
operations, and image build orchestration are tightly coupled.

## Current Metadata

`config/version-manifest.json` is a useful generated observation of installed
and latest-known tool versions by layer. It is not yet sufficient as a release
contract because it does not identify:

- the source commit that produced each image,
- the immutable image digest,
- the exact compatible set of component revisions,
- the reason a tool belongs in a particular layer,
- the tests performed against the image, or
- whether the observation came from a local image or a published artifact.

Three different records are needed:

1. hand-authored placement intent,
2. generated build evidence, and
3. a product-level compatibility lock.

## Documentation Shape

The root `docs/` directory currently mixes:

- container architecture,
- workBenches setup and mounts,
- AI provider profile management,
- VPN and terminal integration,
- spec-driven development, and
- unrelated application, AKS, router, and nopCommerce operational material.

The mixture obscures which repository owns a document and whether it is a
product contract, a component guide, a live operations runbook, or historical
research.

## Strengths to Preserve

- The layer model is already understandable and useful.
- The same base images are intentionally shared by multiple benches.
- Layer 2 repos can evolve independently.
- Layer 3 separates user creation from user-agnostic tool layers.
- Runtime mounts keep user profiles and credentials out of the image.
- The existing TUI contains real-world detection and recovery behavior.
- Current local paths are familiar to users and integrations.
- `config/bench-config.json` proves that data-driven bench discovery is already
  part of the system.

## Main Architectural Problems

| Problem | Consequence |
|---|---|
| Git topology doubles as product topology | install behavior depends on checkout shape |
| Multiple incomplete catalogs | benches can be present but invisible, or selectable but unpinned |
| Coupled image recipes have distributed ownership | a base change is hard to validate and release atomically |
| Floating `latest` tags are the normal identity | an installation is not reproducible |
| Setup UI and mutation engine are coupled | a Windows UI would have to duplicate or shell into large procedural scripts |
| Generated version observations lack provenance | tool inventory cannot prove a released image's origin |
| Documentation ownership is unclear | product and operational guidance drift together |
| End users need aggregation-repo Git knowledge | installation is harder than product selection requires |

## Conclusion from the Inventory

The current system should not be discarded. It should be separated into:

- a product definition and release control plane,
- a foundational image build graph,
- independently owned Layer 2 benches,
- platform-specific setup applications, and
- generated release evidence.
