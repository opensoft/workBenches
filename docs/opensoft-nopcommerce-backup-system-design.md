# OpenSoft nopCommerce Backup System Design

This design defines the backup system that produces everything needed by the
OpenSoft nopCommerce DR runbook. The first proof target is the live FarHeap QA
AKS stack, then the same backup format should feed the OpenSoft cross-tenant DR
test.

## Goal Review

The goal is sound:

1. Use the running QA stack as the reference workload.
2. Build a backup system that captures every artifact required for DR.
3. Provision the target subscription and AKS platform.
4. Restore from the backup set into the target tenant/subscription.
5. Test, tear down, adjust, and repeat until the process is reliable.

Suggested changes to the mini-plan:

- Add a backup proof step before provisioning the target subscription. We should
  create and verify one complete backup set from QA first.
- Start with one QA site, preferably `vds1-qa-davincisite-com`, before backing
  up every site.
- Treat secrets as a separate DR input. The backup manifest should record secret
  names and versions, but secret values should come from cross-tenant escrow.
- Do not extend the current QA snapshot ConfigMap pattern. It stores operational
  credentials in ConfigMaps and only creates a storage snapshot. The new backup
  system should use workload identity or managed identity, scoped secrets, and a
  full SQL plus file backup set.
- Create one Azure Files share snapshot per backup batch, not one per site. The
  QA share contains many site folders, and Azure Files has a finite snapshot
  limit.

## QA Stack Observations

Observed from `cloudBench` on 2026-06-23:

- Tenant: FarHeap, `96d3fa6b-5547-49ca-9af1-dba9bec50c2b`
- Subscription: `Microsoft Sponsorship FH 2026`,
  `cd84dddc-e6f0-45a1-b5da-e700ae550a74`
- Resource group: `aks-davincisite-qa`
- Cluster: `aks-davincisite-qa`
- Region: `westus`
- Kubernetes: `1.33.3`
- Node pool: `nodepool1`, system, `Standard_D4s_v6`, `2` nodes
- Storage account: `aksdavincisiteqa`, `FileStorage`, `Premium_LRS`
- File share: `gps-qa`, `100Gi`, `NFS`
- Storage network state: private endpoint connection exists, but network default
  action is `Allow`; target design should tighten this.
- Storage account has HTTPS-only disabled and minimum TLS `1.0`, which is
  expected to need review for the NFS configuration rather than blindly copied.
- One static RWX PV/PVC per site, with `Retain` reclaim policy.
- Representative site: `vds1-qa-davincisite-com`
- Representative image: `nopcommerceteam/nopcommerce:4.80.3`
- Representative chart: `gps-2.2.3`
- Representative deployment strategy: `Recreate`, one replica
- Representative NFS path:

```text
/aksdavincisiteqa/gps-qa/vds1-qa-davincisite-com/
```

Representative durable mounts:

```text
/app/App_Data/plugins.json
/app/App_Data/DataProtectionKeys
/app/Plugins
/app/Themes
/app/wwwroot
```

Observed Helm values identify:

- SQL server: `davinci-gps-qa`
- SQL elastic pool: `gps-qa`
- Database name: same as site namespace for the representative site
- NFS storage account: `aksdavincisiteqa`
- NFS share: `gps-qa`
- Hostname: `vds1.qa.davincisite.com`

The current Azure login did not have SQL resource visibility for
`davinci-gps-qa`, even though the running app and chart values reference it. The
backup implementation must either receive SQL scope explicitly or have access
granted before SQL export can be proven.

## Backup System Shape

Use four cooperating pieces:

| Component | Runs where | Purpose |
|---|---|---|
| Backup controller | `cloudBench` first, later CI/manual runbook | Selects sites, validates Azure/Kubernetes context, starts backup jobs, records results. |
| Backup runner image | Kubernetes Job or VM inside the AKS VNet | Runs `SqlPackage`, mounts NFS, creates archives, writes checksums, uploads artifacts. |
| Backup storage | Dedicated Blob container outside the app resource group | Stores immutable/versioned backup sets and restore manifests. |
| Secret escrow | Outside source Azure tenant | Supplies restoreable secret values to the target tenant. |

`cloudBench` is good for the first manual proof. For repeatable backups, use a
Kubernetes Job or small backup VM in the same VNet because it can reach private
SQL and NFS paths without reopening public access.

## Backup Runner Image

The runner image should include:

- `az`
- `azcopy`
- `kubectl`
- `helm`
- `sqlpackage`
- `jq`
- `yq`
- `tar`
- `zstd`
- `sha256sum`
- `curl`
- `dig` or `nslookup`

The runner should be versioned and pinned in backup manifests. Do not rely on a
mutable `latest` image tag for backups.

## Backup Site Registry

Create a Git-tracked registry file for backup targets. It should be the intended
state, while the backup controller also records discovered live state.

Example, matching `docs/examples/backup-sites.farheap-qa.yaml`:

```yaml
environment: farheap-qa
tenantId: 96d3fa6b-5547-49ca-9af1-dba9bec50c2b
subscriptionId: cd84dddc-e6f0-45a1-b5da-e700ae550a74
cluster:
  resourceGroup: aks-davincisite-qa
  name: aks-davincisite-qa
  region: westus
nfs:
  resourceGroup: aks-davincisite-qa
  storageAccount: aksdavincisiteqa
  share: gps-qa
sql:
  server: davinci-gps-qa
  elasticPool: gps-qa
sites:
  - name: vds1-qa-davincisite-com
    namespace: vds1-qa-davincisite-com
    helmRelease: vds1-qa-davincisite-com
    deployment: vds1-qa-davincisite-com-gps
    pvc: nfs-vds1-qa-davincisite-com
    database: vds1-qa-davincisite-com
    host: vds1.qa.davincisite.com
    nfsPath: /aksdavincisiteqa/gps-qa/vds1-qa-davincisite-com/
```

The registry should not contain passwords, connection strings, SAS tokens, or
service principal secrets.

## Backup Set Format

Each successful site backup creates this artifact prefix:

```text
backups/nopcommerce/<environment>/<site>/<utc-timestamp>/
  database.bacpac
  files.tar.zst
  manifest.json
  sha256.txt
  helm-values.redacted.json
  k8s-inventory.json
  sql-export.log
  file-archive.log
  smoke-test.txt
  complete.json
```

Upload to an `_incomplete` prefix first, then copy or rename the final marker to
`complete.json` only after checksums and smoke tests pass. Restore tooling should
ignore backup sets that do not have `complete.json`.

## Manifest Requirements

The manifest is the contract between backup and restore. It must contain:

- schema version
- source tenant/subscription/resource groups
- cluster name, Kubernetes version, and region
- site namespace, Helm release, chart version, image tag, and hostnames
- SQL server, database, export tool version, and BACPAC artifact name
- NFS storage account, share, PV/PVC names, source path, and archive artifact
- Azure Files share snapshot timestamp for operational rollback
- secret references required for restore, without secret values
- backup runner image and script version
- SHA-256 checksums
- start/end timestamps
- backup mode, such as `cold-consistent`
- status and smoke-test result

The manifest should include both intended config from the registry and live
config discovered from Kubernetes/Helm. If they differ, the backup should fail
unless `--allow-drift` is explicitly set for a one-off investigation.

## Cold-Consistent Backup Flow

This is the first flow to implement because it gives us the cleanest DR proof.

1. Validate Azure tenant/subscription and Kubernetes context.
2. Read the site registry and discover live deployment/PV/PVC/Helm state.
3. Check that the target backup prefix does not already exist.
4. Check SQL connectivity from the runner.
5. Check NFS mount/read access from the runner.
6. Put the site into maintenance mode or block public writes.
7. Scale the site deployment to `0`.
8. Wait until no site pods are running.
9. Create or reuse one environment-level Azure Files share snapshot for the
   backup batch.
10. Export the site database to `database.bacpac` with `SqlPackage`.
11. Archive the site NFS folder to `files.tar.zst` with `tar --numeric-owner`.
12. Save redacted Helm values to `helm-values.redacted.json`.
13. Save deployment, service, ingress, PV, PVC, and relevant ConfigMap metadata
    to `k8s-inventory.json`.
14. Write `manifest.json`.
15. Write `sha256.txt`.
16. Upload artifacts to the `_incomplete` backup prefix.
17. Verify blob sizes and checksums after upload.
18. Scale the site deployment back to its original replica count.
19. Run a smoke test.
20. Write `complete.json`.

If any step fails after the deployment is scaled down, the script must try to
scale the deployment back up before exiting.

## SQL Export Design

Use `SqlPackage` from inside the VNet for the first implementation.

Why:

- SQL private endpoint and firewall settings should not have to change for
  backup.
- Microsoft recommends `SqlPackage` for scale and performance in production
  import/export scenarios.
- BACPAC export is only transactionally consistent if writes are stopped or a
  transactionally consistent database copy is used. The first design stops app
  writes by scaling the deployment to zero.

SQL permissions options:

| Option | Use now? | Notes |
|---|---:|---|
| Existing SQL admin/login from QA chart | Temporary only | Useful for first proof if no better access exists. Do not carry into OpenSoft production. |
| Dedicated SQL backup login per database | Yes for first production candidate | Store in Key Vault/External Secrets. Restrict as much as `SqlPackage` allows. |
| Managed identity/Entra SQL auth | Target state | Better for production, but requires SQL Entra setup and runner identity plumbing. |

For large databases, the design should support scaling the database or elastic
pool up during export and scaling down after export. Record any scale action in
the manifest.

## NFS Archive Design

Use a Kubernetes Job that mounts the same PVC as the site, or a VM that mounts
the same NFS path directly.

Archive command shape:

```bash
tar --numeric-owner --acls --xattrs -I 'zstd -T0 -6' \
  -cpf /backup/files.tar.zst \
  -C /mnt/site .
```

For the first proof, archive the entire site folder. After restore tests pass,
we can decide whether cache directories are safe to exclude.

The archive should preserve:

- directory layout
- case-sensitive paths
- symlinks
- ownership IDs
- permissions
- data protection keys

## Azure Files Snapshot Design

The snapshot is for fast same-share operational rollback. It is not the portable
DR artifact.

Because `gps-qa` contains all site folders, take one snapshot per backup batch:

```bash
az storage share-rm snapshot \
  --resource-group aks-davincisite-qa \
  --storage-account aksdavincisiteqa \
  --name gps-qa \
  --metadata Environment=farheap-qa BackupBatch=<batch-id> Initiator=nopcommerce-backup
```

Record the snapshot timestamp in every site manifest created during that batch.
Keep snapshot retention short enough to stay below Azure Files snapshot limits.

## Kubernetes Inventory Design

Back up Kubernetes state as reference metadata, not as the primary restore
mechanism.

Capture these objects:

- Deployment
- Service
- Ingress
- PVC
- PV
- selected ConfigMaps with sensitive values redacted
- Helm release metadata and redacted Helm values
- image tag and chart version

Do not capture service account tokens or live Secret values into the backup set.

## Secret Design

The backup set must not contain secret values. It should contain only:

- required secret names
- source Key Vault names or ExternalSecret references
- secret version IDs if useful
- restore instructions for target Key Vault paths

The QA chart currently includes operational credentials in Helm values and
ConfigMaps. The backup design should not copy that pattern. Before the OpenSoft
production candidate, move these values to Key Vault plus External Secrets or an
equivalent secret backend.

For cross-tenant DR, use one of these:

- SOPS/age encrypted files stored in Git.
- 1Password/Bitwarden or another escrow outside the source Azure tenant.
- A manually approved DR secret export/import package.

Azure Key Vault object backup is not sufficient for cross-tenant DR because
restores are constrained to the same Azure subscription and geography.

## Backup Storage Design

Use a dedicated Blob storage account and container, separate from app storage.

For the FarHeap QA proof, the existing backup landing zone is:

- Tenant: FarHeap, `96d3fa6b-5547-49ca-9af1-dba9bec50c2b`
- Subscription: `Backups`, `38854b62-a74e-406d-9a7d-c9aaa3549db2`
- Resource group: `AKS-Backups`

Dedicated nopCommerce DR backup storage was provisioned on 2026-06-23:

```text
Storage account: bknopcomdrqa
Container: nopcommerce-dr
Prefix: backups/nopcommerce/farheap-qa/vds1-qa-davincisite-com/<timestamp>/
```

This account is the storage target for the FarHeap QA backup tests. It is also
the handoff point for the later FarHeap-to-OpenSoft DR move: once a complete
backup set exists here, we can either copy that backup set into an OpenSoft-owned
backup account or grant OpenSoft a tightly scoped read path for the selected
backup prefix during the restore test. The backup set must therefore be portable
and complete before any OpenSoft restore starts.

Enabled controls:

- StorageV2, `Standard_LRS`, `eastus`
- HTTPS-only
- Minimum TLS `1.2`
- Public blob access disabled
- Blob versioning enabled
- Blob soft delete: `30` days
- Container soft delete: `30` days
- Container immutability policy: `7` days, unlocked, on `nopcommerce-dr`

Other storage accounts observed in `AKS-Backups`:

| Storage account | Containers observed | Notes |
|---|---|---|
| `bkaksqa` | `cluster-backups` | Existing AKS backup account candidate. |
| `bkosaksqa` | `cluster-backups` | Existing AKS backup account candidate. |
| `bkaksqadartwing` | `app-backups` | Appears app-specific; do not use for nopCommerce unless confirmed. |
| `bkaksqahttpstatus` | `app-backups` | Appears app-specific; do not use for nopCommerce unless confirmed. |

The older observed storage accounts did not have blob versioning, blob delete
retention, container delete retention, or immutability enabled when inspected on
2026-06-23. The dedicated `bknopcomdrqa` account should be used for the
nopCommerce DR proof instead of changing those existing accounts.

Recommended controls:

- Blob versioning enabled.
- Blob soft delete enabled.
- Container soft delete enabled.
- Immutability policy for the retention window.
- Lifecycle rules for cool/cold/archive movement.
- Private endpoint when the target network is ready.
- Separate identities for backup write and restore read.
- Backup writer can create and upload but cannot delete.
- Restore reader can read selected prefixes.

For the first proof, uploading from `cloudBench` or a runner with a scoped SAS is
acceptable. For production, prefer workload identity or managed identity over SAS
tokens.

## Identity And RBAC

Kubernetes permissions for the backup controller:

- read deployments, pods, services, ingresses, PVCs, PVs, ConfigMaps, and Helm
  metadata
- scale only the selected site deployments
- create backup Jobs in the backup namespace
- read backup Job status and logs

Azure permissions for the backup identity:

- create Azure Files share snapshots for the source share
- upload blobs to the backup container
- read backup blobs for verification
- no delete permission on immutable backup storage
- read enough Azure resource metadata to populate manifests

SQL permissions:

- connect to the target database
- export schema and data with `SqlPackage`
- ideally scoped to a backup login or managed identity rather than SQL admin

## QA Proof Plan

Run this against `vds1-qa-davincisite-com` first.

1. Create the backup storage account/container for proof artifacts.
2. Create a backup namespace in the QA cluster.
3. Build or select the backup runner image.
4. Create a site registry entry for `vds1-qa-davincisite-com`.
5. Create a dry-run inventory:
   - Kubernetes objects discovered
   - Helm values redacted
   - PV/PVC/NFS path discovered
   - SQL server/database discovered
6. Confirm SQL export permissions for `davinci-gps-qa`.
7. Run a cold backup during an approved QA window.
8. Verify `database.bacpac`, `files.tar.zst`, `manifest.json`, and `sha256.txt`.
9. Restore the NFS archive into a disposable folder and inspect file shape.
10. Optionally import the BACPAC into a disposable QA database.
11. Mark the backup proof complete only after `complete.json` is written.

The proof should not attempt to back up all QA sites until the first site has a
known-good backup and at least one test import/extract.

### First QA Backup Result

First completed backup set:

```text
Date: 2026-06-23
Site: vds1-qa-davincisite-com
Storage account: bknopcomdrqa
Container: nopcommerce-dr
Prefix: backups/nopcommerce/farheap-qa/vds1-qa-davincisite-com/20260623T122723Z/
Completion marker: complete.json
Smoke test: HTTP 200 from https://vds1.qa.davincisite.com/
```

Uploaded artifacts:

| Artifact | Size |
|---|---:|
| `database.bacpac` | `251379543` bytes |
| `files.tar.zst` | `67092149` bytes |
| `manifest.json` | `1818` bytes |
| `sha256.txt` | `746` bytes |
| `helm-values.redacted.json` | `1027` bytes |
| `k8s-inventory.json` | `23553` bytes |
| `sql-export.log` | `9270` bytes |
| `file-archive.log` | `80` bytes |
| `cold-backup.log` | `1558` bytes |
| `smoke-test.txt` | `118` bytes |

Operational lessons from the first proof:

- `SqlPackage` must run from inside AKS or another allowed network path; direct
  export from `cloudBench` was blocked by the Azure SQL firewall.
- Large artifact transfer over `kubectl exec`/`kubectl cp` was unreliable for
  the BACPAC and NFS archive. The reliable pattern is to create both large
  artifacts on pod-local disk, restore the app, then upload those artifacts
  directly from the backup pod to Blob with AzCopy.
- The first upload used an account-key SAS because the current operator identity
  could manage the storage account but did not have Blob Data Contributor for
  metadata uploads, and the user-delegation SAS failed AzCopy's destination HEAD
  check.
- The temporary backup pod and local sensitive files were removed after upload.

OpenSoft staging copy:

```text
Date copied: 2026-06-23
Target subscription: sub-os-credits-partnersuccess-2026
Target storage account: stosbkdrtst01
Target container: nopcommerce-dr
Target prefix: backups/nopcommerce/farheap-qa/vds1-qa-davincisite-com/20260623T122723Z/
Copy result: 11 blobs, 318510111 bytes, 0 failures
```

## Target DR Sequence

After the QA backup proof:

1. Provision the target subscription and resource groups.
2. Deploy the OpenSoft AKS candidate plan.
3. Deploy target backup/restore dependencies:
   - backup blob storage read access
   - Azure Files Premium/NFS share
   - Azure SQL server/elastic pool/database target
   - Redis
   - platform Key Vault/External Secrets
   - certificate Key Vault for preserved customer or production TLS certs
   - ingress-nginx with TCP Azure Load Balancer health probes
   - cert-manager with `letsencrypt-prod` `ClusterIssuer`
4. Copy or grant read access to the selected backup set.
5. Restore secrets into the target platform Key Vault.
6. Restore or verify preserved TLS certificates in the target certificate Key
   Vault.
7. For each site, create TLS from this order of precedence:
   - use the target certificate Key Vault certificate when one exists
   - generate a new certificate with cert-manager when no preserved certificate
     exists and the site is allowed to use managed issuance
   - fail the site restore when the site is marked certificate-continuity
     required and the preserved certificate is missing or invalid
8. Import `database.bacpac`.
9. Extract `files.tar.zst` into the target NFS site folder.
10. Helm install the site with target values, TLS secret name, and the source
    image/chart versions.
11. Test with a temporary DR hostname and verify the served certificate issuer,
    SANs, expiration, and fingerprint.
12. Record measured RTO and RPO.

## Failure Handling

The backup script must be restart-safe:

- It should never overwrite an existing complete backup prefix.
- It should write into `_incomplete` until all checks pass.
- It should try to scale the deployment back up after failure.
- It should mark failed backups with `failed.json`.
- It should emit enough logs to diagnose which phase failed.
- It should not delete prior backup sets as part of the backup job.

## Open Questions

- Where should the first proof backup storage account live: FarHeap QA,
  OpenSoft, or a separate backup subscription?
- Who owns the cross-tenant secret escrow and approval flow?
- Which identity will be allowed to export from `davinci-gps-qa` for the QA
  proof?
- Is cold downtime acceptable for the first production launch, or do we need an
  online/copy-based backup before launch?
- Should production media move to Blob before the first full DR test, or should
  the first DR test prove the current NFS media shape?

## First Implementation Backlog

1. Expand `docs/examples/backup-sites.farheap-qa.yaml` after the first-site
   proof works.
2. Build the backup runner image.
3. Write `discover-site.sh`.
4. Write `backup-site.sh`.
5. Write `verify-backup-set.sh`.
6. Run inventory-only proof for `vds1-qa-davincisite-com`.
7. Run cold backup proof for `vds1-qa-davincisite-com`.
8. Import/extract into disposable targets.
9. Use the resulting backup set for the first cross-tenant DR restore.
