# xFactory Project Catalog Integration

Status: **brainstorm / external-contract dependency**

Date captured: 2026-07-27

This note records how the proposed workBenches product and Windows setup
application may consume xFactory's future tenant project catalog. It does not
define that catalog and does not authorize implementation.

The canonical neutral architecture brainstorm is:

```text
openxFactory/ideation/brainstorm/tenant-project-catalog-and-workstation-cache.md
```

That brainstorm deliberately belongs to openxFactory because the catalog,
principal projection, workstation cache, and single-project request scope are
cross-product xFactory contracts. workBenches is the first intended
multi-repository consumer.

## Boundary

The deployed company codexFactory runtime is authoritative for:

- company projects and their lifecycle;
- each project's repository composition;
- which projects a principal may discover;
- project access and assignment relationships; and
- the server revision from which a workstation projection was derived.

The engineer workstation may keep:

- company endpoint and active-tenant configuration;
- a tenant- and principal-scoped, replaceable project cache;
- checkout-location mappings;
- sync health and last-known-good state; and
- recent and favorite project preferences.

The workstation cache is not a permissions database. A local checkout,
project manifest, favorite, or stale cached grant cannot authorize a live
operation.

## workBenches responsibilities

After the neutral xFactory contract is accepted, the workBenches product
control plane may:

1. publish a portable `.xfactory/project.yaml` from the primary
   `workBenches` repository;
2. describe the repositories that form the workBenches project, including
   the control plane, foundational images, Windows setup application, and
   independently released bench repositories;
3. preserve repository roles, document roots, and source provenance so the
   xFactory dashboard can compose rather than copy project documents; and
4. validate the manifest as part of the workBenches product contract.

The manifest is descriptive import input. It must contain no company
membership, principal grants, credentials, access tokens, or host-specific
checkout paths. Registration into a live company catalog is a separate,
authenticated, auditable xFactory operation.

## `workbenches-setup` responsibilities

Once xFactory publishes a workstation-client contract, the Windows setup
application may:

- install or register the xFactory workstation client;
- configure the selected company endpoint and initiate its supported
  authentication flow;
- create the platform-native configuration, state, and cache locations;
- perform the first authenticated project-catalog sync;
- make the resulting Company Projects and My Projects views available to the
  installed xFactory application;
- configure the chosen Windows-to-WSL bridge without creating a second
  competing catalog; and
- report the active tenant, catalog revision, last sync time, and stale or
  failed state in setup health.

The setup application must not:

- invent or copy the company's authoritative project list;
- infer access from GitHub clones, submodules, or local folders;
- store raw credentials in configuration, logs, images, manifests, or the
  project cache;
- silently keep independent writable Windows and WSL catalogs; or
- treat a successful setup sync as authorization for later live operations.

## Native workstation locations

The logical local home is `xfactory`, but setup should follow operating-system
conventions rather than create one shared literal `.xFactory` directory.

| Purpose | Windows | WSL/Linux |
|---|---|---|
| Configuration | `%APPDATA%\Opensoft\xFactory\config.yaml` | `~/.config/opensoft/xfactory/config.yaml` |
| Durable state | `%LOCALAPPDATA%\Opensoft\xFactory\state\` | `~/.local/state/opensoft/xfactory/` |
| Replaceable cache | `%LOCALAPPDATA%\Opensoft\xFactory\cache\projects\` | `~/.cache/opensoft/xfactory/projects/` |
| Credentials | Windows Credential Manager or supported secure store | Supported keyring/credential broker |

One side must own sync. The Windows application can be that owner and expose a
local broker or deliberate derived projection to WSL, or WSL can own sync and
serve Windows. The neutral contract must be chosen before the setup
application implements either path.

## Product-manifest relationship

The proposed workBenches component catalog and release lock answer product
installation questions:

- which benches and repositories make up a compatible workBenches release;
- which source revisions and image digests are selected; and
- which components the installer materializes.

The xFactory project catalog answers company/runtime questions:

- which projects the company operates;
- which repositories belong to each project;
- which projects the signed-in principal can see; and
- which visible projects are assigned to that principal.

These catalogs may reference the same repositories, but they are not the same
authority and should not be merged into one file.

## Candidate acceptance inputs for later proposals

A later workBenches or setup-app proposal can require that:

- workBenches publishes a schema-valid project manifest with no credentials,
  grants, or host paths;
- importing that manifest cannot grant project access;
- setup stores config, state, cache, and credentials in their defined native
  locations;
- the first sync records tenant ID, principal ID, catalog revision, digest,
  and freshness;
- refresh atomically replaces the last-known-good cache;
- offline use is visibly stale;
- a revoked project is denied by the runtime even if it remains in an old
  cache;
- Windows and WSL have one defined catalog owner and bridge; and
- Company Projects, My Projects, Favorites, and Recent remain distinguishable
  views.

## Decisions still required

Before this integration is proposed:

1. define Company Projects visibility policy;
2. define the exact meaning of My Projects;
3. choose the workstation cache owner and Windows/WSL bridge;
4. choose the cache serialization and integrity mechanism;
5. decide whether preferences are local-only or optionally synchronized;
6. define project-manifest approval and reconciliation; and
7. decide whether xFactory registration is in the first setup-app release or
   a linked follow-on release.

## Sequencing

1. Keep the current xFactory development-plane repository selector separate.
2. Ratify and propose the neutral tenant catalog and workstation projection in
   xFactory.
3. Accept the workBenches product catalog and Windows bootstrapper contracts.
4. Add the workBenches project manifest against the accepted xFactory schema.
5. Implement the setup integration as a linked component change.

Until those gates are passed, this file is planning input only.
