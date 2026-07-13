# OpenSoft nopCommerce DR Runbook

This runbook defines how the OpenSoft nopCommerce AKS platform should be backed
up and restored, including a proof test where the restore target is a different
tenant/subscription from the source.

The backup system that produces the SQL, NFS, manifest, checksum, and inventory
artifacts is designed in `docs/opensoft-nopcommerce-backup-system-design.md`.

The important design rule is simple: the AKS cluster is disposable. The platform
must be rebuilt from Git/IaC, and only application data, file data, and secrets
are restored.

## DR Goals

- Recreate a nopCommerce site without depending on the source AKS cluster.
- Prove restore into a clean tenant/subscription, not just the original tenant.
- Keep same-tenant operational recovery fast, but do not confuse it with real
  cross-tenant disaster recovery.
- Make every backup self-describing with a restore manifest and checksums.
- Run the whole process from `cloudBench` or from a purpose-built backup runner
  container.

## Recovery Lanes

| Lane | Purpose | Primary mechanism | Notes |
|---|---|---|---|
| Operational restore | Fix accidental delete, bad deploy, bad plugin change | Azure SQL PITR, Azure Files NFS snapshots, Git/Helm rollback | Same tenant/subscription/resource lineage. Fastest path. |
| Regional restore | Survive a regional failure | Geo-redundant storage, SQL geo-restore/replication if enabled, AKS/IaC rebuild | Useful later, but not the first proof target. |
| Cross-tenant DR | Prove we can recreate everything somewhere new | IaC + BACPAC + file archive + secret escrow + Helm values | This is the required DR test. |

## Source Of Truth

The source of truth should be:

- IaC for resource groups, VNet, subnets, private DNS, AKS, storage, SQL, Redis,
  Key Vault, ingress, managed identities, role assignments, and monitoring.
- Helm chart and environment values for each nopCommerce site.
- Pinned container image tags.
- SQL BACPAC exports for cross-tenant database restore.
- Azure Files NFS folder archives for cross-tenant file restore.
- Secret material held in a cross-tenant-capable escrow, such as SOPS/age,
  1Password, or another store that is not bound to the source Azure tenant.
- A restore manifest for every backup set.

Do not use the source AKS cluster as the source of truth. Kubernetes object
backups are helpful for inspection, but the restore should still work from Git,
the backup artifacts, and secret escrow.

## What To Rebuild Vs Restore

Rebuild these from code:

- AKS cluster and node pools
- ingress-nginx, cert-manager, external-secrets, monitoring, and backup tooling
- namespaces, services, ingress, PVC/PV definitions, ConfigMaps, and Helm
  releases
- Azure SQL logical server, elastic pool, empty database shell
- Azure Files Premium/NFS share and site folders
- Redis
- Key Vault and access policies/RBAC

Restore these from backups:

- nopCommerce SQL database content
- NFS-backed site folder content, currently including `App_Data`,
  `DataProtectionKeys`, `Plugins`, `Themes`, and `wwwroot`
- media content if it remains on NFS; if media moves to Blob, restore or sync
  the Blob container separately
- secret values from cross-tenant escrow into the target Key Vault or Kubernetes
  Secret backend
- preserved TLS certificate material for sites that require certificate
  continuity, restored from the target environment certificate Key Vault into
  Kubernetes TLS secrets

Usually do not restore these:

- AKS nodes
- Redis cache contents
- old pod IPs, load balancer generated names, or managed identities from the
  source tenant
- raw Kubernetes service account tokens

## Backup Target

Use a dedicated backup storage account/container that is isolated from the
production app resource group.

For the FarHeap QA to OpenSoft DR proof, the current backup landing zone is:

```text
Tenant: FarHeap
Subscription: Backups / 38854b62-a74e-406d-9a7d-c9aaa3549db2
Resource group: AKS-Backups
Storage account: bknopcomdrqa
Container: nopcommerce-dr
Prefix: backups/nopcommerce/farheap-qa/<site>/<utc-timestamp>/
```

During backup testing, all QA backup artifacts land in this FarHeap backup
account. During the later FarHeap-to-OpenSoft DR exercise, this account becomes
the transfer source: the selected complete backup prefix is copied into OpenSoft
backup storage or exposed to OpenSoft with narrowly scoped read access for the
restore window. Do not start the OpenSoft restore from live FarHeap AKS, SQL, or
NFS resources; start it from this completed backup set.

Recommended backup storage settings:

- Blob versioning enabled.
- Blob soft delete enabled.
- Container or version-level immutability for the retention window.
- Lifecycle rules to move older backup sets to cool/cold/archive tiers.
- Storage account and container names recorded in IaC.
- Production backup identity can create/write backup objects but should not be
  able to delete them.
- Restore identity can read selected backup objects during a DR test.

For cross-tenant DR, the backup account should either live in a separate backup
subscription/tenant or be replicated/copied there. If Azure object replication is
used across tenants, remember that cross-tenant replication must be explicitly
allowed on the storage accounts. A simpler first proof is to upload directly to
the target backup tenant with `azcopy` and a tightly scoped SAS or workload
identity.

## Backup Set Layout

Every backup should produce one folder-like prefix:

```text
backups/nopcommerce/<site>/<utc-timestamp>/
  database.bacpac
  files.tar.zst
  manifest.json
  sha256.txt
  smoke-test.txt
```

The manifest should be treated as required restore metadata:

```json
{
  "schemaVersion": 1,
  "site": "vds1-qa-davincisite-com",
  "createdUtc": "2026-06-23T20:15:00Z",
  "backupMode": "cold-consistent",
  "source": {
    "tenantId": "<source-tenant-id>",
    "subscriptionId": "<source-subscription-id>",
    "resourceGroup": "<source-rg>",
    "cluster": "<source-aks>",
    "namespace": "<source-namespace>",
    "helmRelease": "<source-release>"
  },
  "app": {
    "image": "nopcommerceteam/nopcommerce:4.90.4",
    "chart": "gps-2.2.3",
    "replicas": 1
  },
  "database": {
    "engine": "azure-sql",
    "server": "<source-sql-server>",
    "database": "<source-db>",
    "artifact": "database.bacpac"
  },
  "files": {
    "storage": "<source-nfs-storage>",
    "share": "<source-nfs-share>",
    "path": "/<share>/<site>/",
    "artifact": "files.tar.zst"
  },
  "secrets": {
    "source": "external-escrow",
    "requiredNames": [
      "sql-connection-string",
      "redis-connection-string",
      "data-protection-key-material"
    ]
  },
  "checksums": {
    "database.bacpac": "<sha256>",
    "files.tar.zst": "<sha256>"
  }
}
```

## Cold Backup Workflow

Use this as the first implementation because it is easiest to prove correct.
Later we can optimize for lower RPO.

1. Announce maintenance or block public write traffic at ingress.
2. Confirm the target site and backup prefix.
3. Capture Helm values and current image/chart versions.
4. Scale the nopCommerce deployment to `0`.
5. Export SQL to `database.bacpac`.
6. Take an Azure Files NFS share snapshot for same-share rollback.
7. Archive the site's NFS folder to `files.tar.zst`.
8. Generate `manifest.json`.
9. Generate `sha256.txt`.
10. Upload all artifacts to the backup container.
11. Scale the deployment back to `1`.
12. Run a smoke test and save the result beside the backup set.

Example orchestration shape:

```bash
kubectl -n <site-namespace> scale deploy/<release>-gps --replicas=0

# For private SQL, prefer SqlPackage from a runner inside the VNet.
sqlpackage /Action:Export \
  /SourceServerName:<sql-server>.database.windows.net \
  /SourceDatabaseName:<database> \
  /TargetFile:/backup/database.bacpac

# Snapshot is for quick operational rollback of the NFS share.
az storage share-rm snapshot \
  --resource-group <storage-rg> \
  --storage-account <storage-account> \
  --name <share>

# Run from a pod/runner that mounts the same NFS path.
tar --numeric-owner -I zstd -cpf /backup/files.tar.zst -C /mnt/nfs/site .
sha256sum /backup/database.bacpac /backup/files.tar.zst > /backup/sha256.txt
azcopy copy "/backup/*" "https://<backup-account>.blob.core.windows.net/<container>/<prefix>?<sas>"

kubectl -n <site-namespace> scale deploy/<release>-gps --replicas=1
```

The backup runner image should include `az`, `azcopy`, `kubectl`, `helm`,
`sqlpackage`, `tar`, `zstd`, `jq`, and `sha256sum`.

## SQL Backup Notes

Use two SQL protection layers:

- Azure SQL automated backups, PITR, and long-term retention for operational
  recovery.
- BACPAC exports for portable cross-tenant DR.

For private endpoint SQL, run `SqlPackage` from inside the VNet. That avoids
turning public access back on and avoids depending on the Azure SQL Import/Export
service path. The restore path imports the BACPAC into a new target Azure SQL
database or elastic pool.

PITR is not the cross-tenant answer. Microsoft documents that Azure SQL Database
point-in-time restore is same-server only; cross-server, cross-subscription, and
cross-geo PITR are not currently supported.

## NFS/File Backup Notes

The current GPS/nopCommerce pattern uses Azure Files Premium over NFS. That is
fine for the app test, but it changes the backup plan:

- Azure Files NFS snapshots are available and should be used for quick
  operational rollback.
- Azure Backup/Recovery Services does not currently support NFS Azure file
  shares.
- Azure Backup for AKS also does not support Azure Files NFS persistent volumes,
  and its Azure Files volume support is aimed at SMB shares rather than the
  private NFS pattern we observed.
- Therefore, real DR needs a portable file archive or sync path.

Use a Kubernetes Job or backup runner VM in the same VNet to mount the NFS share
and create `files.tar.zst`. Do not rely on copying individual files with storage
account APIs because the NFS folder needs Linux path, ownership, and directory
shape preserved.

For new NFS shares, mount the share before taking the first snapshot. Microsoft
documents that snapshots taken before the first mount can behave unexpectedly
when listed.

If production media moves from NFS to Blob Storage, back up the media container
with blob-native features: versioning, soft delete, immutability, lifecycle, and
optionally object replication or scheduled `azcopy sync` into the backup tenant.

## Secrets Notes

Do not rely on Azure Key Vault object backup for cross-tenant DR. Microsoft
documents that Key Vault backup blobs cannot be decrypted outside Azure and must
be restored into a Key Vault in the same Azure subscription and geography.

For cross-tenant DR, use one of these instead:

- SOPS-encrypted secret files in Git, with age recipients controlled by the DR
  owners.
- 1Password/Bitwarden/another external escrow outside the source tenant.
- A dedicated manual secret export/import procedure approved for DR only.

The restore should create new target-tenant secrets and update Helm values or
ExternalSecret references to point at the target Key Vault.

## Kubernetes Backup Notes

Velero or Azure Backup for AKS can still be useful, but only as a secondary
layer:

- Back up namespace manifests for inspection and migration assistance.
- Back up ConfigMaps, Services, Ingress, PVC/PV definitions, and Helm release
  metadata.
- Do not make Velero/Azure Backup the only restore path.
- Do not depend on AKS backup for Azure Files NFS volume restore.

The canonical restore should be Helm install/upgrade against a newly rebuilt
cluster.

## Cross-Tenant Restore Workflow

1. Select a backup set and verify `sha256.txt`.
2. Deploy the target platform from IaC:
   - resource groups
   - VNet/subnets/private DNS
   - AKS PlanA1 or current candidate plan
   - Azure SQL server, elastic pool, and database target
   - Azure Files Premium/NFS share and site folder
   - Redis
   - platform Key Vault and certificate Key Vault
   - ingress public IP and temporary DR DNS
3. Restore secrets into the target platform Key Vault or Kubernetes Secret
   backend.
4. Restore or verify TLS certificates in the target certificate Key Vault for
   every site that has a preserved certificate.
5. Import `database.bacpac` into the target database.
6. Mount the target NFS folder from a restore runner.
7. Extract `files.tar.zst` into the target site folder.
8. Install platform components:
   - ingress-nginx
   - cert-manager with a production `ClusterIssuer` for Let’s Encrypt
   - external-secrets
   - monitoring/logging
9. Create each site's Kubernetes TLS secret:
   - prefer the certificate from the target certificate Key Vault
   - fall back to cert-manager issuance when no preserved certificate exists
10. Helm install the nopCommerce site with target-specific values:
   - target SQL server/database
   - target NFS server/share/path
   - target Redis endpoint
   - target host name
   - TLS secret name and certificate source
   - image tag and chart version from `manifest.json`
11. Test through a temporary DR hostname.
12. Apply the safe cache pilot:
   - theme-level browser warm-fetch script
   - in-cluster homepage warmer CronJob
13. Record measured RTO, RPO, broken assumptions, and manual steps.
14. Tear down the target resources or keep them as the next warm DR target.

### Required Ingress and TLS Baseline

Every rebuilt DR cluster must include `ingress-nginx` and `cert-manager` before
the restored site is considered ready for browser testing or DNS cutover.

Required baseline:

- `ingress-nginx` controller exposed through the AKS public load balancer.
- Azure Load Balancer health probes for the ingress service set to TCP for both
  ports `80` and `443`. HTTP probes to `/` can mark the backend unhealthy when
  NGINX does not have a matching host rule for the probe.
- `cert-manager` installed in the cluster.
- A production ACME `ClusterIssuer` named `letsencrypt-prod`.
- Site ingress `spec.tls` configured with the DR hostname and a per-site TLS
  secret.
- Restored site ingress annotated with `cert-manager.io/cluster-issuer:
  letsencrypt-prod` only when the site is using on-the-fly certificate issuance.

### DR Certificate Operating Model

Certificate handling is part of the restore, not an afterthought. Every site
must declare one of these certificate modes in the restore manifest or target
values:

| Mode | Source | Restore behavior |
|---|---|---|
| `auto` | Target certificate Key Vault first, then cert-manager | Default. If a matching certificate exists in the target certificate Key Vault, sync it into a Kubernetes TLS secret. If no matching certificate exists, create ingress or `Certificate` resources and let cert-manager issue a fresh certificate after DNS points at the target ingress IP. |
| `preserved` | Target certificate Key Vault, for example `kv-os-qa-certs` | Export/sync the Key Vault certificate into a Kubernetes TLS secret and configure ingress to use that secret. Use this when the operator has confirmed the cert exists before the restore. |
| `managed` | cert-manager with `letsencrypt-prod` | Always create a fresh certificate with cert-manager. Use this for temporary DR hostnames and low-continuity test domains. |
| `preserved-required` | Target certificate Key Vault | Same as `preserved`, but the restore must fail if the certificate is missing or expired. Use this for customer domains, pinned integrations, commercial CA certs, or any domain where continuity is contractually important. |

Default rule:

1. If the site has mode `auto` or `preserved` and has a matching certificate in
   the target certificate Key Vault, use that certificate.
2. If no preserved certificate exists and the site mode is `auto`, generate a
   certificate on the fly with cert-manager.
3. If the site is marked `preserved-required` and the certificate is missing,
   expired, lacks the hostname in SANs, or cannot be exported/synced, stop the
   restore for that site and raise it as a DR readiness failure.
4. If the site is marked `managed`, do not use Key Vault certificate material;
   let cert-manager issue the certificate.

Recommended vault split:

| Vault | Purpose |
|---|---|
| `kv-os-prod-platform` | Production platform and app secrets. |
| `kv-os-prod-certs` | Production/customer TLS certificates. |
| `kv-os-qa-platform` | QA platform, restore, and app secrets. |
| `kv-os-qa-certs` | QA/DR copies of production/customer TLS certificates for restore testing. |

The certificate Key Vault object must be usable by the restore process. For
cross-tenant or cross-subscription DR, do not depend on Azure Key Vault object
backup as the only portable copy because Key Vault backup restore is constrained
to the same Azure subscription and geography. Use an approved exportable
certificate package or a controlled certificate copy/import process into the
target certificate Key Vault before the restore drill.

For each preserved certificate, the restore test must record:

- Key Vault name and certificate name.
- Certificate subject, SANs, issuer, serial number, not-before, and expiration.
- Kubernetes TLS secret name created from the certificate.
- Ingress hostnames using that secret.
- Browser or `openssl s_client` proof that the restored ingress serves the
  expected certificate.

The first OpenSoft DR test used:

```text
DR hostname: drtest.davinci-designer.com
Ingress public IP: 172.184.151.118
ClusterIssuer: letsencrypt-prod
TLS secret: drtest-davinci-designer-tls
Certificate issuer: Let's Encrypt
```

## First OpenSoft Target Setup

The first target environment was provisioned on 2026-06-23 for the single-site
restore proof.

```text
Tenant: OpenSoft
Subscription: sub-os-credits-partnersuccess-2026
Subscription ID: 13bd2833-45a6-4e51-8f24-83e0598f4cae
Region: westus
AKS: aks-os-drtest-test-01
Namespace: nopcommerce-test
Restore tools namespace: dr-tools
SQL server: sql-os-nopcommerce-test-03
SQL database: sqldb-os-nopcommerce-test2-test-01
NFS account/share: stosnopdrtst01 / nopcommerce-test
Backup staging account/container: stosbkdrtst01 / nopcommerce-dr
```

Private endpoint validation from inside AKS passed:

| Service | FQDN | Private IP | Port |
|---|---|---:|---:|
| SQL | `sql-os-nopcommerce-test-03.database.windows.net` | `10.60.240.4` | `1433` |
| Azure Files NFS | `stosnopdrtst01.file.core.windows.net` | `10.60.240.5` | `2049` |
| Backup Blob | `stosbkdrtst01.blob.core.windows.net` | `10.60.240.6` | `443` |

The selected FarHeap QA backup set was copied into OpenSoft backup staging:

```text
backups/nopcommerce/farheap-qa/vds1-qa-davincisite-com/20260623T122723Z/
```

The target copy contains 11 blobs, including `complete.json`,
`database.bacpac`, `files.tar.zst`, `manifest.json`, and `sha256.txt`.

## First OpenSoft Restore Result

The first restore into the OpenSoft target stack was completed on 2026-06-24
using the selected FarHeap QA backup set.

Restore result:

| Area | Result | Notes |
|---|---|---|
| Backup verification | Passed | All artifacts in `sha256.txt` verified before restore. |
| SQL restore | Passed | `database.bacpac` imported into `sqldb-os-nopcommerce-test2-test-01`. |
| SQL import elapsed | 4:02:49 | Import ran on S1; DTU and physical reads were saturated for much of the run. |
| SQL max size | Raised to 50 GiB | The original 5 GiB target was too small; restored DB reached about 17.7 GiB. |
| File restore | Passed | `files.tar.zst` extracted to `/stosnopdrtst01/nopcommerce-test/vds1-qa-davincisite-com/`. |
| Restored file size | About 277 MiB | Included `App_Data`, `DataProtectionKeys`, `Plugins`, `Themes`, and `wwwroot`. |
| App deployment | Passed | Minimal Kubernetes deployment used `nopcommerceteam/nopcommerce:4.80.3`. |
| Internal smoke | Passed | Port-forward GET with forwarded HTTPS headers returned HTTP 200 and the restored home page. |
| Restart smoke | Passed | Pod restart completed with zero restarts; post-warm-up GET returned HTTP 200. |
| Public ingress | Passed | `ingress-nginx` was installed and exposed on `172.184.151.118`. |
| Temporary DR DNS | Passed | `drtest.davinci-designer.com` pointed to the ingress public IP. |
| TLS | Passed | `cert-manager` issued a trusted Let’s Encrypt certificate for the DR hostname. |

The restored site was deployed as:

```text
Namespace: nopcommerce-test
Deployment: nopcommerce-test-gps
Service: nopcommerce-test-gps
PV: nfs-vds1-qa-davincisite-com-drtest
PVC: nfs-vds1-qa-davincisite-com
Image: nopcommerceteam/nopcommerce:4.80.3
Smoke host header: vds1.qa.davincisite.com
DR hostname: drtest.davinci-designer.com
Ingress public IP: 172.184.151.118
TLS secret: drtest-davinci-designer-tls
```

Important findings from the restore:

- The BACPAC expands much larger than its compressed size. The 240 MiB BACPAC
  restored to about 17.7 GiB because the `dbo.Log` table and its indexes are
  large.
- For future drills, start the SQL import on a temporary higher tier, then scale
  down after import and smoke testing. S1 worked but made the restore too slow
  for a realistic RTO.
- Consider pruning or separately handling high-volume operational log tables
  before portable DR export, if business requirements allow it.
- The first restored workload used the SQL admin login as a temporary app
  connection string. The admin password was rotated after import. The permanent
  restore automation should create a contained app database user, store that
  secret, and avoid passing SQL passwords as process arguments.
- The GPS Helm chart was not available in `cloudBench`, so the first app restore
  used a minimal manifest reconstructed from the backup inventory. The next
  iteration should restore through the real Helm chart.
- Public ingress, DNS, and TLS are now proven for the DR hostname. Admin login,
  product image inspection, test upload, and explicit SQL/NFS write tests are
  still pending.

## Second OpenSoft Restore Result

The second OpenSoft restore iteration was run on 2026-06-24 UTC / 2026-06-25
Asia/Shanghai after deleting the previous single-site proof stack and recreating
the target resource groups.

Restore source:

```text
Restore set: backups/nopcommerce/farheap-qa/_restore-sets/latest-full-iterative.json
Site restored in this iteration: vds1-qa-davincisite-com
Selected prefix: backups/nopcommerce/farheap-qa/vds1-qa-davincisite-com/20260624T184141Z/
OpenSoft staging account/container: stosbkdrtst01 / nopcommerce-dr
Copied artifacts: 19 blobs, 324,213,670 bytes, 0 failures
```

Target stack:

```text
Subscription: sub-os-credits-partnersuccess-2026
AKS: aks-os-drtest-test-01
Namespace: nopcommerce-test
SQL server: sql-os-nopcommerce-test-03
SQL database: sqldb-os-nopcommerce-test2-test-01
NFS account/share: stosnopdrtst01 / nopcommerce-test
Ingress public IP: 172.184.127.96
DR hostname: drtest.davinci-designer.com
```

Restore result:

| Area | Result | Notes |
|---|---|---|
| Old test teardown | Passed | Deleted `rg-os-sandbox-drtest-test`, `rg-os-workload-nopcommerce-test`, `rg-os-backups-drtest-test`, and the AKS managed resource group. |
| Platform rebuild | Passed | Recreated VNet, private DNS, private endpoints, AKS, SQL, NFS, backup staging storage, ingress-nginx, and cert-manager. |
| Backup staging copy | Passed | Latest `vds1` backup from the full iterative restore set was copied into OpenSoft staging storage. |
| File restore | Passed | Extracted `files.tar.zst` into `/stosnopdrtst01/nopcommerce-test/vds1-qa-davincisite-com/`. |
| Restored files | Passed | 4,158 files, 288,452,778 bytes extracted. |
| SQL managed import | Failed as designed | Azure Import/Export could not reach SQL while public network access was disabled. |
| SQL private import | Passed | `SqlPackage` ran inside AKS over the SQL private endpoint. |
| SQL import elapsed | 1:58:47.92 | Target DB was temporarily S3, then scaled down to S1 after smoke testing. |
| App deployment | Passed | Minimal Kubernetes deployment using `nopcommerceteam/nopcommerce:4.80.3` reached `1/1`. |
| Ingress smoke | Passed | HTTPS request with `--resolve drtest.davinci-designer.com:443:172.184.127.96` returned HTTP 200 and the nopCommerce home page title. |
| Public DNS/TLS | Pending | `drtest.davinci-designer.com` still needs to point at `172.184.127.96`; cert-manager is waiting for HTTP-01 propagation. |

Important findings from the second restore:

- With SQL public network disabled, the Azure managed Import/Export operation is
  not usable unless Import/Export Private Link is configured. The reliable
  private-path restore is an in-cluster `SqlPackage` runner.
- The second restore proved the latest full iterative backup set can be used as
  the source of truth, even though this iteration restored only the `vds1` site.
- S3 reduced SQL import time from the first restore's S1 result, but the import
  still took nearly two hours. Future RTO tests should evaluate S6 or a temporary
  vCore tier, followed by scale-down after validation.
- The rebuilt cluster must have the current `drtest.davinci-designer.com` DNS A
  record updated after every new ingress IP; otherwise Let’s Encrypt remains
  pending even though host-overridden smoke tests pass.

## QA DR Certificate Policy Audit

On 2026-06-25, the QA DR target subscription was updated to include a dedicated
certificate Key Vault:

```text
Subscription: sub-os-qa-platform
Certificate Key Vault: kv-os-qa-certs
Resource group: rg-os-sandbox-drtest-qa
AKS: aks-os-drtest-qa-01
Ingress public IP: 172.185.27.29
```

The 9-site restore set is:

```text
backups/nopcommerce/farheap-qa/_restore-sets/latest-full-iterative.json
Restore set ID: 20260624T184141Z-full-iterative
Site count: 9
```

Certificate policy for this restore set is tracked in:

```text
docs/examples/restore-cert-policy.opensoft-qa-drtest.yaml
```

The policy uses `certificateMode: auto` for all 9 sites:

1. Check `kv-os-qa-certs` for a matching certificate whose SANs cover the target
   host.
2. If found, sync that Key Vault certificate into the site's Kubernetes TLS
   secret and do not request a replacement certificate.
3. If not found, issue the certificate on the fly with cert-manager using
   `letsencrypt-prod`.

At audit time, `kv-os-qa-certs` contained no certificates, and
`aks-os-drtest-qa-01` contained no restored site namespaces, site ingresses,
Kubernetes `Certificate` resources, TLS secrets, or site SQL databases. Before
browser/DNS cutover for a 9-site restore, rerun the certificate policy audit and
record the served certificate issuer, SANs, expiration, and fingerprint for
each restored host.

Follow-up on 2026-06-25: because no preserved certificate existed in
`kv-os-qa-certs`, the DR target used the documented `auto` fallback and issued a
managed Let's Encrypt certificate for `drtest.davinci-designer.com`.
`ingress-nginx` was configured to use
`ingress-nginx/drtest-davinci-designer-tls` as its default certificate until the
restored site ingress creates or references its own TLS secret.

```text
Certificate: ingress-nginx/drtest-davinci-designer-com
TLS secret: ingress-nginx/drtest-davinci-designer-tls
Issuer: Let's Encrypt YR1
Not before: 2026-06-25T07:56:52Z
Not after: 2026-09-23T07:56:51Z
SHA-256 fingerprint: 94:22:EF:DA:A6:61:1D:32:50:E1:8C:6C:BE:1F:B6:66:41:8F:4F:C0:E6:72:99:53:50:0C:5C:3C:0A:15:F4:51
```

## QA 9-Site Restore Result

On 2026-06-25 UTC, the full FarHeap QA restore set was applied into the
OpenSoft QA DR target:

```text
Target subscription: sub-os-qa-platform / 297b2389-33bf-48c8-8deb-0b92838431e4
AKS: aks-os-drtest-qa-01
SQL server: sql-os-nopcommerce-qa-01
NFS account/share: stosnopdrqa01 / nopcommerce-qa
Ingress public IP: 172.185.27.29
Restore set: backups/nopcommerce/farheap-qa/_restore-sets/latest-full-iterative.json
Restore set ID: 20260624T184141Z-full-iterative
```

The restore job ran inside AKS so that SQL import and NFS restore stayed on the
private network. It verified the backup checksums, extracted each
`files.tar.zst` archive under `/stosnopdrqa01/nopcommerce-qa/<site>/`, and
imported each `database.bacpac` into a same-named Azure SQL database. The
restore job completed in 101 minutes and logged `ALL SITES RESTORED`.

Restored sites:

| Site | Host | Image | NFS file count | App status |
| --- | --- | --- | ---: | --- |
| `digiwrap-qa-davincisite-com` | `digiwrap.qa.davincisite.com` | `nopcommerceteam/nopcommerce:4.80.3` | 7,368 | `1/1` |
| `eds1-qa-davincisite-com` | `eds1.qa.davincisite.com` | `nopcommerceteam/nopcommerce:4.80.3` | 4,304 | `1/1` |
| `eds2-qa-davincisite-com` | `eds2.qa.davincisite.com` | `nopcommerceteam/nopcommerce:4.80.3` | 4,340 | `1/1` |
| `eds3-qa-davincisite-com` | `eds3.qa.davincisite.com` | `nopcommerceteam/nopcommerce:4.80.3` | 4,310 | `1/1` |
| `irs-qa-davincisite-com` | `fa-psp.inkrouter.com` | `nopcommerceteam/nopcommerce:4.80.8` | 4,476 | `1/1` |
| `qa1-overnightprints-eu-4-80-3` | `qa1.overnightprints.eu` | `nopcommerceteam/nopcommerce:4.80.3` | 6,068 | `1/1` |
| `qa2-overnightprints-eu-4-80-3` | `qa2.overnightprints.eu` | `nopcommerceteam/nopcommerce:4.80.3` | 5,761 | `1/1` |
| `staging-rentapress-com` | `staging.rentapress.com` | `nopcommerceteam/nopcommerce:4.80.3` | 7,764 | `1/1` |
| `vds1-qa-davincisite-com` | `vds1.qa.davincisite.com` | `nopcommerceteam/nopcommerce:4.80.3` | 4,158 | `1/1` |

App restore notes:

- One namespace, deployment, service, PVC, and ingress was created per site.
- A temporary `drtest.davinci-designer.com` ingress was also pointed at the
  restored `vds1` service for browser testing.
- `https://drtest.davinci-designer.com/` and
  `https://drtest.davinci-designer.com/newproducts` returned HTTP 200 with the
  managed Let's Encrypt certificate.
- Direct ingress smoke tests for the original hosts returned HTTP 200 or 302
  through `172.185.27.29`; the 302 responses were application redirects.
- The temporary restore secret containing the FarHeap SAS and import-time SQL
  credential was deleted after restore. Per-site app connection secrets remain
  in each site namespace.

Important follow-ups:

- The GPS Helm chart was still not available in `cloudBench`, so this restore
  applied minimal Kubernetes resources reconstructed from the backup metadata.
  The next iteration should deploy through the real chart.
- The checked-in minimal-manifest restore path is
  `scripts/render-nopcommerce-dr-k8s-manifests.py`. It renders the restored
  Deployment with `ConnectionStrings__ConnectionString` coming from
  `valueFrom.secretKeyRef`, not a literal environment variable.
- Each restored production hostname still needs the certificate policy applied
  before DNS/browser cutover: use a preserved Key Vault certificate when one is
  available, otherwise issue with cert-manager.
- SQL databases were imported at service objective `S6` for speed and remained
  at `S6` after the smoke test. Scale them down before leaving the environment
  running for low-cost QA testing.

### Secret-backed Minimal App Restore

In a real DR, the app connection strings come from the SOPS escrow stored in Git
and are decrypted with the age identity recovered from 1Password. The restore
operator should decrypt only long enough to restore the value into the target
secret system, then delete the local plaintext file.

Example for one restored site:

```bash
export SOPS_AGE_KEY_FILE=/home/brett/.ssh/opensoft-dr-age-brett.txt
tmp_conn=$(mktemp)

sops -d --output-type json /path/to/Opensoft-Tenant/escrow/farheap/davincisite-production/secrets.sops.yaml \
  | python3 -c '
import json, sys
site = "vds1-qa-davincisite-com"
data = json.load(sys.stdin)
for item in data["secrets"]:
    if item["namespace"] == site:
        sys.stdout.write(item["values"]["ConnectionStrings__ConnectionString"])
        break
else:
    raise SystemExit(f"missing escrowed connection string for {site}")
' \
  > "$tmp_conn"

./scripts/render-nopcommerce-dr-k8s-manifests.py \
  --backup-site-dir /restore/backups/vds1-qa-davincisite-com \
  --namespace vds1-qa-davincisite-com \
  --host vds1.davinci-designer.com \
  --nfs-server stosnopdrqa01.file.core.windows.net \
  --nfs-path /stosnopdrqa01/nopcommerce-qa/vds1-qa-davincisite-com \
  --secret-name vds1-qa-davincisite-com-app-secrets \
  --connection-string-file "$tmp_conn" \
  --apply

shred -u "$tmp_conn"
```

The script writes only non-secret Kubernetes restore manifests under
`restore-manifests/<site>/`. When `--apply` is used with
`--connection-string-file`, it creates or updates the Kubernetes Secret directly
through `kubectl`; the decrypted value is not written into the rendered manifest
file. If the Secret has already been restored by another step, pass
`--existing-secret-name` instead.

After restore, verify that no literal SQL connection string remains in the
Deployment spec:

```bash
kubectl -n vds1-qa-davincisite-com get deploy vds1-qa-davincisite-com-gps -o json \
  | jq '.spec.template.spec.containers[0].env[]
        | select(.name == "ConnectionStrings__ConnectionString")'
```

The expected output contains `valueFrom.secretKeyRef` and does not contain a
`value` field.

### Post-Restore Homepage Warm and Prefetch

After the restored sites, services, ingresses, and theme mounts exist, apply the
safe cache pilot:

```bash
docker exec cloud-bench bash -lc '
set -euo pipefail
USER_SITE=$(/opt/az/bin/python3 -c "import site; print(site.getusersitepackages())")
export PYTHONPATH="$USER_SITE:/opt/az/lib/python3.13/site-packages" AZ_INSTALLER=PIP
export HTTP_PROXY=http://host.docker.internal:17891
export HTTPS_PROXY=http://host.docker.internal:17891
export http_proxy=$HTTP_PROXY
export https_proxy=$HTTPS_PROXY
export NO_PROXY=.database.windows.net,.file.core.windows.net,10.0.0.0/8,127.0.0.1,localhost
export no_proxy=$NO_PROXY
export AZ_CMD="/opt/az/bin/python3 /tmp/azfixed.py"
cd /home/brett/projects/workBenches
./scripts/apply-opensoft-nopcommerce-cache-pilot.sh
'
```

This is not ingress full-page caching. It is intentionally safer:

- The script discovers restored nopCommerce deployments and mounted theme
  `Head.cshtml` files.
- It installs `opensoft-prefetch.js` into each mounted theme.
- It adds an ONP-specific loader when `ONPTheme/Content/js/onp-theme-script.js`
  is present.
- It restarts only deployments whose theme files changed.
- It creates or updates
  `nopcommerce-cache/opensoft-nopcommerce-homepage-warmer`, which curls every
  ingress hostname through `ingress-nginx` every two minutes.

The browser warm-fetch script warms only likely same-origin public links that
are visible near the first viewport. It uses explicit low-priority `fetch()`
requests after browser idle with host-tuned limits, and high-priority `fetch()`
for the exact link on hover, focus, or touch intent when that link has not
already been warmed. DigiWrap browser warming is currently disabled because it
was slower in test. If a user clicks while a warm fetch for that same URL is
still in flight, the script aborts the warm fetch before navigation. It skips
admin, login, register, logout, cart, wishlist, checkout, customer, order,
password recovery, and search paths, including localized paths such as
`/en/cart`.

Validation from the 2026-06-26 OpenSoft QA restore:

- All nine restored nopCommerce deployments were `1/1`.
- All 11 ingress host bindings served the warm-fetch JavaScript or ONP loader.
- A clean warmer run returned HTTP 200 for every host, mostly below 0.5 seconds
  after warm-up.
- Browser smoke tests for DigiWrap and ONP showed no OpenSoft warm-fetch
  console errors and no blocked cart/wishlist/login/checkout/null warm targets.

The autonomous measurement plan for proving whether this cache pilot helps is
tracked in `docs/opensoft-nopcommerce-cache-test-plan.md`. The optimization
decisions and cache-header findings live in
`docs/nopcommerce-performance-optimization.md`; the DR runbook only references
them.

### Post-Restore Internal Site Publishing

After a DR restore, the restored source hostnames may still be owned by the
source tenant, customer DNS, or old QA domains. For OpenSoft DR testing, publish
the restored sites under the `davinci-designer.com` domain instead. The proven
pattern is:

```text
Spaceship DNS A record -> AKS ingress public IP -> per-site ingress -> per-site service -> nopCommerce Store host
```

Do not rely on only one layer. The browser path works only when all of these
are aligned:

- Public DNS resolves the new `davinci-designer.com` hostname to the AKS ingress
  public IP.
- The site namespace has an ingress rule for that exact hostname.
- cert-manager has issued a TLS certificate for that exact hostname, unless a
  preserved Key Vault certificate is restored.
- nopCommerce has a `Store` row whose `Url` and `Hosts` accept that hostname.
- The site deployment has been restarted or its cache cleared after the
  nopCommerce store change.

Use one DNS name per restored site. For the current 9-site QA restore, the
intended internal DR aliases are:

| Restored site | Source host | `davinci-designer.com` alias |
| --- | --- | --- |
| `digiwrap-qa-davincisite-com` | `digiwrap.qa.davincisite.com` | `digiwrap.davinci-designer.com` |
| `eds1-qa-davincisite-com` | `eds1.qa.davincisite.com` | `eds1.davinci-designer.com` |
| `eds2-qa-davincisite-com` | `eds2.qa.davincisite.com` | `eds2.davinci-designer.com` |
| `eds3-qa-davincisite-com` | `eds3.qa.davincisite.com` | `eds3.davinci-designer.com` |
| `irs-qa-davincisite-com` | `fa-psp.inkrouter.com` | `irs.davinci-designer.com` |
| `qa1-overnightprints-eu-4-80-3` | `qa1.overnightprints.eu` | `qa1-overnightprints.davinci-designer.com` |
| `qa2-overnightprints-eu-4-80-3` | `qa2.overnightprints.eu` | `qa2-overnightprints.davinci-designer.com` |
| `staging-rentapress-com` | `staging.rentapress.com` | `staging-rentapress.davinci-designer.com` |
| `vds1-qa-davincisite-com` | `vds1.qa.davincisite.com` | `vds1.davinci-designer.com` |

`drtest.davinci-designer.com` is the temporary cluster smoke-test name and
currently points to the restored `vds1` service. Keep it as a general test
entrypoint; use the per-site aliases above for internal site validation.

#### 1. Add DNS Records

The `davinci-designer.com` public DNS zone is hosted at Spaceship. For every
site alias, create an `A` record pointing to the current AKS ingress public IP:

```text
Type: A
Host: <site-alias>
Value: 172.185.27.29
TTL: 60 or 300
```

Example:

```text
Type: A
Host: digiwrap
Value: 172.185.27.29
TTL: 60
```

If the AKS cluster is rebuilt, the ingress public IP may change unless it is
reserved and reused. Update all site aliases to the new ingress IP before
expecting cert-manager to issue or browsers to load the restored sites.

Spaceship's API can manage these records when a key with
`dnsrecords:read` and `dnsrecords:write` is available. Keep the API key and
secret out of Git and pass them through environment variables or Key Vault.

#### 2. Add A Per-Site Alias Ingress

Create a separate alias ingress in the restored site's namespace. Keeping the
alias ingress separate from the source-host ingress makes the DR mapping easy
to inspect and remove without disturbing the original restored metadata.

Template:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <alias-name>
  namespace: <site-namespace>
  labels:
    opensoft.one/site: <site-name>
    opensoft.one/dr-alias: davinci-designer
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - <alias-host>.davinci-designer.com
      secretName: <alias-name>-tls
  rules:
    - host: <alias-host>.davinci-designer.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <site-service>
                port:
                  number: 80
```

For DigiWrap, the applied values were:

```text
Namespace: digiwrap-qa-davincisite-com
Ingress: digiwrap-davinci-designer
Service: digiwrap-qa-davincisite-com-gps
Host: digiwrap.davinci-designer.com
TLS secret: digiwrap-davinci-designer-tls
```

#### 3. Update nopCommerce Store Configuration

nopCommerce does not accept the new site name only because Kubernetes routes
the request. The restored database must also know that the new host belongs to
the store.

For each restored site database, update the correct row in `[Store]`:

```sql
UPDATE [Store]
   SET [Url] = N'https://<alias-host>.davinci-designer.com/',
       [Hosts] = N'<alias-host>.davinci-designer.com',
       [SslEnabled] = 1
 WHERE [Id] = <store-id>;
```

Use a trailing slash in `Url`. `Hosts` is comma-separated when multiple host
names are intentionally allowed. For internal DR validation, prefer only the
`davinci-designer.com` alias so the restored app has a clear canonical URL.

Before updating, inspect the restored store row:

```sql
SELECT Id, Name, Url, SslEnabled, Hosts
FROM [Store];
```

Run SQL changes from inside AKS or another network path that can reach the
private SQL endpoint. The current manual test used a short-lived
`mcr.microsoft.com/mssql-tools:latest` pod in the site namespace with the
site's existing `nop-sql-connection` secret. Delete the helper pod after the
update so it does not linger.

#### 4. Restart Or Clear nopCommerce Cache

nopCommerce caches store configuration. After changing `[Store]`, restart the
site deployment:

```bash
kubectl -n <site-namespace> rollout restart deployment/<site-deployment>
kubectl -n <site-namespace> rollout status deployment/<site-deployment> --timeout=180s
```

Expect the first request after restart to be slow while the app warms up. During
that warm-up window, nginx may briefly return `502` if it reaches the pod before
Kestrel is listening. Retry after the pod is ready and the app has completed
startup.

#### 5. Verify DNS, TLS, Ingress, And App

Verify public DNS from more than one recursive resolver:

```bash
curl --noproxy '*' -H 'accept: application/dns-json' \
  'https://cloudflare-dns.com/dns-query?name=<alias-host>.davinci-designer.com&type=A'

curl --noproxy '*' -H 'accept: application/dns-json' \
  'https://dns.google/resolve?name=<alias-host>.davinci-designer.com&type=A'
```

Both should return the AKS ingress IP.

Check cert-manager:

```bash
kubectl -n <site-namespace> get certificate <alias-name>-tls -o wide
kubectl -n <site-namespace> get order,challenge
```

The certificate should become `READY=True`. If it is stuck pending with
`no such host`, public DNS is not visible to the cluster resolver yet. If it is
stuck with an HTTP-01 self-check failure, confirm the alias ingress, solver
ingress, and DNS record all point to the same ingress IP.

Verify the live certificate:

```bash
printf '' | openssl s_client \
  -connect 172.185.27.29:443 \
  -servername <alias-host>.davinci-designer.com \
  -showcerts 2>/dev/null |
  openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

Verify the app through the real ingress IP:

```bash
curl --noproxy '*' \
  --resolve <alias-host>.davinci-designer.com:443:172.185.27.29 \
  https://<alias-host>.davinci-designer.com/ \
  -o /tmp/<alias-host>.html \
  -w 'code=%{http_code} cert=%{ssl_verify_result} time=%{time_total}\n'
```

Finally, verify from a normal browser without `--resolve`.

Local DNS caveat: 0dcloud may return `198.18.0.0/16` fake-IP DNS answers on the
workstation even after public DNS is correct. If a browser fails but the
`--resolve` test succeeds, verify whether the VPN/proxy path is intercepting
the site before changing AKS or nopCommerce again.

#### 6. Record The Result

For every alias, record:

- DNS record and resolved IP.
- Ingress namespace/name.
- TLS secret name.
- Certificate issuer, expiration, and SHA-256 fingerprint.
- nopCommerce `[Store]` row after the update.
- Browser smoke-test URL and result.

This is part of the DR evidence. A restore is not fully usable for internal
validation until the alias, certificate, nopCommerce store mapping, and browser
test are all recorded.

#### DigiWrap DR Alias Test

On 2026-06-25 UTC, the restored DigiWrap site was mapped to a
`davinci-designer.com` test hostname:

```text
Target hostname: digiwrap.davinci-designer.com
Ingress: digiwrap-qa-davincisite-com/digiwrap-davinci-designer
Service: digiwrap-qa-davincisite-com/digiwrap-qa-davincisite-com-gps
Ingress public IP: 172.185.27.29
TLS secret requested: digiwrap-davinci-designer-tls
```

nopCommerce was also updated in the DigiWrap SQL database so the restored app
accepts the new host as its canonical store URL:

```sql
UPDATE [Store]
   SET [Url] = N'https://digiwrap.davinci-designer.com/',
       [Hosts] = N'digiwrap.davinci-designer.com',
       [SslEnabled] = 1;
```

After restarting the DigiWrap deployment, a forced ingress test returned HTTP
200 for `https://digiwrap.davinci-designer.com/` when resolved directly to
`172.185.27.29`.

Spaceship DNS was then updated with:

```text
Type: A
Host: digiwrap
Value: 172.185.27.29
TTL: 60
```

Public DNS propagated through Cloudflare and Google resolvers, cert-manager
completed HTTP-01 validation, and the site loaded successfully in the browser.

```text
Certificate: digiwrap-qa-davincisite-com/digiwrap-davinci-designer-tls
TLS secret: digiwrap-qa-davincisite-com/digiwrap-davinci-designer-tls
Issuer: Let's Encrypt YR2
Not before: 2026-06-25T11:53:22Z
Not after: 2026-09-23T11:53:21Z
SHA-256 fingerprint: 06:22:6D:E7:DD:00:98:47:8A:66:1B:B3:BF:AC:84:4F:52:08:D9:7C:00:54:B8:39:38:3E:29:E3:BD:06:9C:1B
```

## Restore Acceptance Tests

Minimum pass criteria:

- The site starts without returning to install mode.
- Admin login works.
- Catalog pages load.
- Product images load.
- A test upload works.
- A test SQL write persists after pod restart.
- A test NFS write persists after pod restart.
- Ingress TLS certificate works for the DR hostname.
- No manual pod edits are required.
- The source tenant and source cluster are not required after backup artifacts
  and secrets have been copied.

## Test Cadence

For the build/test/destroy phase:

- Take a backup before every destructive test.
- Restore into a clean target subscription/tenant at least once per cluster
  iteration.
- Record actual restore time by phase: IaC build, SQL import, NFS extract, Helm
  install, smoke test.

For production:

- Nightly cold-consistent backup until online consistency is proven.
- Backup before releases, plugin changes, theme changes, and bulk catalog
  imports.
- Monthly restore drill into a non-production tenant/subscription.
- Quarterly full DR exercise with DNS cutover rehearsal.

## Automation Backlog

Build these scripts in order:

1. `backup-site.sh`
   - validates context
   - scales the site down
   - exports SQL
   - archives NFS
   - writes manifest/checksums
   - uploads artifacts
   - scales the site back up
2. `restore-site.sh`
   - verifies checksums
   - imports SQL
   - extracts NFS archive
   - applies target Helm values
   - runs smoke tests
3. `dr-test.sh`
   - creates target resource group
   - deploys IaC
   - calls restore
   - captures RTO/RPO
   - optionally destroys the target

All scripts should be runnable from `cloudBench` and should fail closed if the
current Azure tenant/subscription does not match the requested source or target.

## Open Decisions

- Whether the backup escrow lives in an OpenSoft backup subscription or a truly
  separate tenant.
- Whether we accept cold backups for production launch or need a lower-RPO
  online backup process before launch.
- Whether media stays on NFS for launch or moves to Blob Storage first.
- Whether the DR target is cold and built on demand, or warm with AKS/SQL/Files
  skeleton resources already deployed.
- Whether to use Velero or Azure Backup for AKS as the secondary Kubernetes
  inspection layer.

## Verified Source Notes

These Microsoft/Velero documents were checked on 2026-06-23:

- [Azure SQL automated backups](https://learn.microsoft.com/en-us/azure/azure-sql/database/automated-backups-overview?view=azuresql)
- [Restore Azure SQL Database from backups](https://learn.microsoft.com/en-us/azure/azure-sql/database/recovery-using-backups?view=azuresql)
- [Export Azure SQL Database to BACPAC](https://learn.microsoft.com/en-us/azure/azure-sql/database/database-export?view=azuresql)
- [Import BACPAC into Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/database-import?view=azuresql)
- [Import/export Azure SQL when public Azure services are off](https://learn.microsoft.com/en-us/azure/azure-sql/database/database-import-export-azure-services-off?view=azuresql)
- [Azure Files NFS snapshots](https://learn.microsoft.com/en-us/azure/storage/files/storage-snapshots-files)
- [Azure Files NFS protocol](https://learn.microsoft.com/en-us/azure/storage/files/files-nfs-protocol)
- [AKS backup support matrix](https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-cluster-backup-support-matrix)
- [Azure Files backup support matrix](https://learn.microsoft.com/en-us/azure/backup/azure-file-share-support-matrix)
- [Azure Key Vault backup and restore](https://learn.microsoft.com/en-us/azure/key-vault/general/backup)
- [Azure Blob immutable storage](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview)
- [Azure Blob versioning](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview)
- [Azure Blob object replication](https://learn.microsoft.com/en-us/azure/storage/blobs/object-replication-overview)
- [Velero Azure plugin](https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure/blob/main/README.md)
- [Velero file system backup](https://velero.io/docs/main/file-system-backup/)
