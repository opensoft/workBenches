# Naming and state contract

## Canonical aliases

| Interface | Canonical | Legacy compatibility |
|---|---|---|
| Repository/display | `openBenches` | `workBenches` remains in history and documented aliases |
| Fresh checkout | `~/Projects/openBenches` | Existing `workBenches` basenames remain discoverable |
| Environment | `OPENBENCHES_*` | `WORKBENCHES_*` and established `WB_*` remain during the support window |
| Setup command | `setup-openbenches` | `setup-workbenches` |
| MCP command | `openbenches-mcp-sync` | `workbenches-mcp-sync` |
| Credential command | `openbenches-credential-sync` | `workbenches-credential-sync` |
| Installer flag | `--openbenches` | `--workbenches` |
| Root flag | `--openbenches-root` | `--workbenches-root` |
| Fresh config/cache/data roots | `openbenches` | Existing `workbenches` roots remain in legacy-root mode |
| QA runner label | `openbenches-qa` after dual-label rollout | `workbenches-qa` remains routable |
| QA config | `/etc/openbenches/release-qa.json` | `/etc/workbenches/release-qa.json` fallback |

## Resolution rules

1. Explicit configured values take precedence in new/legacy/default order, except dangerous conflicting dual values fail.
2. Equal old/new values are accepted. Different paths, endpoints, credential settings, or release configuration produce an actionable conflict.
3. A root is selected per consumer contract; old and new trees are never merged.
4. Only old root: legacy-root mode. Only new root: new-root mode.
5. Both roots: use a documented explicit selection or refuse ambiguous stateful startup. Never duplicate profile inventories.
6. Existing checkouts and runtime state are not moved automatically.
7. Old and new producers/consumers must interoperate during the support window; consumer readers land before producer dual emission.
8. One installed artifact has one implementation and one ownership lock. Command aliases do not create independent writers.

## Durable identifiers retained

- GHCR `ghcr.io/opensoft/workbenches-base` and `workbenches-dev-base`, schema-v1 image manifests, and existing OCI `io.workbenches.*` labels.
- Published tags, historical releases/assets/locks, old issue references, archived specs, and lane history.
- Existing named volumes, `.workbenches-history`, live container names, and persistent in-image paths.
- Schema-v1 `$id`/`kind` values, setup catalog keys, and credential payload fields.
- Keycloak realms/client IDs/audiences, Key Vault names and `workbenches-operation` tags, stored credential paths, and encrypted payloads.
- Installer lock/payload/journal names and exact historical wrapper fixtures during mixed-version operation.
- Generic `workbench` concepts, `workbench-base`, `devBenches`, `sysBenches`, `bioBenches`, openRepoShape compatibility tokens, Kubernetes annotations, and `xfactory-workbenches` service identities.

New GHCR namespaces, legacy removal, credential rotation, and `openWorkBenches*` consolidation require separate proposals.

## Support window

Recommended minimum for ordinary aliases is 90 days or two release cycles, whichever is longer. Cheap fallbacks and persistent identifiers may remain indefinitely. Removal requires fresh-install and upgrade evidence plus a later approved deprecation/major-version change.
