# nopCommerce on AKS Research

This note captures the current install strategy for running nopCommerce on the
OpenSoft AKS production candidate cluster. The goal is to build, run, test,
tear down, and repeat until the nopCommerce stack is stable enough to promote.

## Recommendation

Start with a small, production-shaped test rather than a local-only demo:

- Run nopCommerce in AKS from a pinned image, initially
  `nopcommerceteam/nopcommerce:4.90.4`.
- Use Azure SQL Database outside the cluster, in the same region as AKS.
- Connect AKS to Azure SQL through Private Link and private DNS.
- Use Azure SQL Redirect connection policy for lower latency and better
  throughput once the required port ranges are allowed.
- Add Redis before running more than one nopCommerce replica.
- Use Azure Blob Storage for media/images/thumbnails.
- Use the existing OpenSoft/GPS Azure Files NFS pattern for first-pass durable
  app files: one large private Azure Files NFS share, with one folder mounted per
  app.
- Avoid depending on local pod storage for durable state.
- Move plugins/themes into a custom image before production so the shared NFS
  folder contains data, not mutable application code.

Optimization decisions for nopCommerce caching, response headers, browser lazy
warming, and server-side warming are tracked in
`docs/nopcommerce-performance-optimization.md`.

## What nopCommerce Needs

nopCommerce 4.90 runs on .NET 9 and supports SQL Server, MySQL, and PostgreSQL.
The official Docker Hub image is published by `nopcommerceteam/nopcommerce`,
with recent tag `4.90.4`.

Sources:

- [nopCommerce technology and system requirements](https://docs.nopcommerce.com/en/installation-and-upgrading/technology-and-system-requirements.html)
- [nopCommerce Docker Hub image](https://hub.docker.com/r/nopcommerceteam/nopcommerce)
- [nopCommerce Dockerfile](https://github.com/nopSolutions/nopCommerce/blob/develop/Dockerfile)
- [nopCommerce docker-compose.yml](https://github.com/nopSolutions/nopCommerce/blob/develop/docker-compose.yml)

nopCommerce is not completely stateless. Its installer and runtime require write
access to several paths, including:

- `App_Data`
- `App_Data/DataProtectionKeys`
- `App_Data/appsettings.json`
- `App_Data/plugins.json`
- `Plugins`
- `Plugins/Uploaded`
- `wwwroot/files`
- `wwwroot/images`
- `wwwroot/images/thumbs`
- `wwwroot/images/uploaded`
- `wwwroot/sitemaps`

Source: [nopCommerce local installation permissions](https://docs.nopcommerce.com/en/installation-and-upgrading/installing-nopcommerce/installing-local.html)

## SQL Design

Use Azure SQL Database as the primary data store. Do not run SQL Server as an
ordinary pod for this production-candidate test. A SQL container is useful for
local development, but the AKS test should exercise the real network and PaaS
database shape.

Initial SQL shape:

- Azure SQL logical server in the same region as AKS.
- One nopCommerce database created before install.
- SQL authentication for the first test, stored in Kubernetes Secret or pulled
  from Key Vault later.
- Private endpoint in the AKS VNet or a directly peered data subnet.
- Private DNS zone: `privatelink.database.windows.net`.
- Disable public network access after private connectivity is proven.

Connection string baseline:

```text
Server=tcp:<server>.database.windows.net,1433;Initial Catalog=<database>;User ID=<user>;Password=<password>;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;ConnectRetryCount=3;ConnectRetryInterval=10;Max Pool Size=200;
```

nopCommerce stores the database provider and connection string under
`DataConfig`. Its docs show `SqlServer`, `MySql`, and `PostgreSQL` as valid data
providers, and all `appsettings.json` settings can be overridden by environment
variables.

Source: [nopCommerce appsettings.json DataConfig](https://docs.nopcommerce.com/en/developer/tutorials/appsettings-json-file.html)

## SQL Connectivity and Speed

The special connection concern is real. Azure SQL has two connection policies:

- `Redirect`: client connects directly to the database node after the initial
  gateway connection. Microsoft recommends this for lowest latency and highest
  throughput.
- `Proxy`: traffic stays through the Azure SQL gateway. Microsoft says this
  increases latency and reduces throughput.

For Azure-originated clients, the default is generally Redirect for public
connectivity. With Private Link, explicitly use Redirect once the network allows
it.

For Azure SQL Private Link with Redirect, allow:

- inbound to the VNet hosting the private endpoint on ports `1433-65535`
- outbound from the AKS client VNet on ports `1433-65535`

If we only allow port `1433`, Private Link can fall back to Proxy behavior, which
is safer to bring up but slower.

Sources:

- [Azure SQL connectivity architecture](https://learn.microsoft.com/en-us/azure/azure-sql/database/connectivity-architecture?view=azuresql)
- [Azure SQL Private Link](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview?view=azuresql)
- [Private endpoint DNS zones](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

Validation commands inside a test pod:

```bash
getent hosts <server>.database.windows.net
nc -vz <server>.database.windows.net 1433
```

Expected DNS behavior: the SQL FQDN resolves through
`privatelink.database.windows.net` to a private IP.

## Redis and Multi-Replica Behavior

Before running more than one nopCommerce replica, configure distributed cache.
nopCommerce supports SQL Server and Redis for distributed cache, and Redis is the
preferred first test because it avoids putting session/cache pressure on the SQL
database.

Recommended first production-candidate setting:

```json
"DistributedCacheConfig": {
  "Enabled": true,
  "DistributedCacheType": "Redis",
  "ConnectionString": "<redis-host>:6380,password=<secret>,ssl=True,abortConnect=False",
  "InstanceName": "nopCommerce"
}
```

For nopCommerce 4.70 and newer, `Redis Synchronized Memory` is also available
and should be tested after basic Redis is working. The docs describe it as higher
performance because local memory is used for cache and Redis is used for
synchronization.

Sources:

- [nopCommerce appsettings DistributedCacheConfig](https://docs.nopcommerce.com/en/developer/tutorials/appsettings-json-file.html)
- [nopCommerce on Azure multi-instance notes](https://docs.nopcommerce.com/en/installation-and-upgrading/installing-nopcommerce/installing-on-microsoft-azure.html)

## Media and File Storage

Use Azure Blob Storage for product images, thumbnails, and media. nopCommerce
4.90 moved Azure Blob configuration into a plugin flow. The Azure Blob plugin
requires:

- connection string
- container name
- endpoint
- append-container-name behavior

Sources:

- [nopCommerce Azure install notes](https://docs.nopcommerce.com/en/installation-and-upgrading/installing-nopcommerce/installing-on-microsoft-azure.html)
- [nopCommerce appsettings Azure Blob notes](https://docs.nopcommerce.com/en/developer/tutorials/appsettings-json-file.html)

For production, do not serve high-traffic catalog images from an AKS-mounted file
share. Put the media in Blob Storage and front it with the final public delivery
path, likely Azure Front Door or CDN after the application behavior is proven.

### OpenSoft QA Storage Optimization Research

The restored OpenSoft QA stack currently mirrors the FarHeap pattern:

```text
Azure Files Premium NFS
  share: nopcommerce-qa
  one folder per restored site
  mounted into each pod at:
    /app/App_Data
    /app/Plugins
    /app/Themes
    /app/wwwroot
```

This works for restore fidelity, but it is not the best long-term performance
model. It places app configuration, deployable plugin/theme code, generated
static bundles, public media, and temporary upload paths on one shared
filesystem.

The official nopCommerce Azure guidance supports Azure Blob Storage for
nopCommerce media. For nopCommerce `4.80` and below, this is configured with
`AzureBlobConfig` in `appsettings.json`; for `4.90` and above, the configuration
moves to the Azure Blob Storage plugin UI. The restored OpenSoft QA sites are
`4.80.x`, and their `App_Data/appsettings.json` files already contain an empty
`AzureBlobConfig` section, so this is directly testable without upgrading
nopCommerce first.

The official web-farm guidance explains why the current NFS shape exists: a
multi-node nopCommerce deployment must replicate `/App_Data`, `/Plugins`,
`/Themes`, and `/wwwroot` if those folders are mutable on disk. In AKS, we used
NFS as the replication mechanism. The better design is to reduce what is mutable
on disk:

- Store product images, thumbnails, public downloads, and media in Azure Blob
  Storage.
- Front public media with Azure Front Door or CDN after the Blob behavior is
  proven.
- Bake `Plugins` and `Themes` into the container image or deploy them as a
  versioned artifact during release, instead of keeping hundreds of MiB of
  plugin files per site on NFS.
- Keep only the minimum runtime-mutated `App_Data` files on a small persistent
  volume or externalize them to secrets/config/Blob where nopCommerce supports
  it.
- Use Redis or Redis Synchronized Memory for multi-replica cache behavior before
  scaling any storefront above one pod.

Current OpenSoft QA file measurements from the 9-site restore:

| Site | App_Data | Plugins | Themes | wwwroot | Images | Files |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `digiwrap-qa-davincisite-com` | 6.7 MiB | 209.0 MiB | 1.9 MiB | 184.1 MiB | 110.7 MiB | 4 KiB |
| `eds1-qa-davincisite-com` | 6.7 MiB | 181.7 MiB | 445 KiB | 98.2 MiB | 10.8 MiB | 4 KiB |
| `eds2-qa-davincisite-com` | 6.7 MiB | 186.6 MiB | 445 KiB | 89.0 MiB | 10.7 MiB | 4 KiB |
| `eds3-qa-davincisite-com` | 6.7 MiB | 187.2 MiB | 445 KiB | 71.4 MiB | 10.4 MiB | 4 KiB |
| `irs-qa-davincisite-com` | 6.7 MiB | 196.9 MiB | 445 KiB | 96.3 MiB | 11.2 MiB | 4 KiB |
| `qa1-overnightprints-eu-4-80-3` | 6.7 MiB | 225.5 MiB | 4.5 MiB | 200.2 MiB | 28.8 MiB | 33.5 MiB |
| `qa2-overnightprints-eu-4-80-3` | 6.7 MiB | 224.9 MiB | 4.5 MiB | 86.3 MiB | 21.3 MiB | 4 KiB |
| `staging-rentapress-com` | 6.7 MiB | 213.6 MiB | 2.0 MiB | 196.6 MiB | 23.9 MiB | 3.2 MiB |
| `vds1-qa-davincisite-com` | 6.7 MiB | 182.0 MiB | 445 KiB | 86.9 MiB | 10.4 MiB | 4 KiB |

This shows two separate optimization targets:

1. Public media belongs in Blob/Front Door, not on an AKS-mounted NFS path.
2. `Plugins` are the largest repeated payload. They should become a deployable
   artifact or image layer rather than runtime shared storage.

Recommended target storage model:

```text
SQL:
  nopCommerce data, settings, orders, catalog, users

Blob Storage:
  product images
  thumbnails
  public downloadable files
  optional Data Protection Keys container

Container image / release artifact:
  nopCommerce runtime
  Plugins
  Themes
  static baseline assets

Small persistent volume or external config:
  App_Data/appsettings.json
  App_Data/plugins.json
  minimal mutable runtime files

Ephemeral pod disk:
  WebOptimizer cache
  temp files that can be regenerated
```

Do not start by replacing Azure Files NFS with Blob CSI for the same full
filesystem tree. AKS supports Blob CSI, but nopCommerce has native Blob media
support, and native media support is a cleaner fit than pretending object
storage is a POSIX filesystem. Blob CSI can be useful for bulk archive or
unstructured data mounts, but it should not be the first production design for
nopCommerce application folders.

QA pilot plan using the current `sub-os-qa-platform` stack:

1. Use `digiwrap-qa-davincisite-com` as the first test site because
   `https://digiwrap.davinci-designer.com/` is already working.
2. Create a new media storage account/container for QA media, separate from the
   backup staging account `stosbkdrqa01`.
3. Copy DigiWrap media from `/app/wwwroot/images/uploaded`,
   `/app/wwwroot/images/thumbs`, and `/app/wwwroot/files` into the media
   container.
4. Configure the DigiWrap deployment using environment overrides for
   `AzureBlobConfig__ConnectionString`, `AzureBlobConfig__ContainerName`,
   `AzureBlobConfig__EndPoint`, and `AzureBlobConfig__AppendContainerName`
   instead of editing the restored file by hand.
5. Restart only the DigiWrap deployment and verify that generated image URLs
   move to the Blob/Front Door endpoint and that product/category images load.
6. Run timing tests against key pages and media URLs before and after the
   change.
7. If Blob media works, remove the `/app/wwwroot/images` dependency from NFS for
   DigiWrap and repeat the smoke tests.
8. Build a second pilot image that bakes DigiWrap `Plugins` and `Themes` into an
   image layer, leaving only `App_Data` on persistent storage.
9. After both pilots pass, redesign the Helm values so production sites no
   longer mount the full four-folder NFS tree.

### OpenSoft QA DigiWrap Blob Media Pilot Result

Implemented on 2026-06-25 against the current OpenSoft QA DR cluster:

```text
Subscription: sub-os-qa-platform
Cluster: aks-os-drtest-qa-01
Namespace: digiwrap-qa-davincisite-com
Deployment: digiwrap-qa-davincisite-com-gps
Storage account: stosnopmediaqa01
Container: digiwrap-media
App secret: digiwrap-media-blob
Public media endpoint: https://stosnopmediaqa01.blob.core.windows.net/digiwrap-media/
```

The implementation is captured in
`scripts/pilot-opensoft-digiwrap-blob-media.sh` so the pilot can be repeated
after a rebuild. The script:

- creates the QA media storage account and public blob container if missing
- seeds the current DigiWrap thumbnail/media files from the mounted NFS PVC with
  a temporary in-cluster Azure CLI job
- creates the app-facing `AzureBlobConfig__*` Kubernetes secret
- patches only the DigiWrap deployment to use Azure Blob media settings
- optionally replaces the broad `/app/wwwroot` NFS mount with targeted writable
  mounts for `/app/wwwroot/files`, `/app/wwwroot/sitemaps`, and an `emptyDir`
  `/app/wwwroot/bundles`

Live pilot outcome:

- 618 blobs were uploaded: 612 generated thumbnail files, 3
  `images/uploaded` placeholder files, and 6 `files` placeholder/index files.
- The DigiWrap homepage changed from local `/images/thumbs/...` URLs to Blob
  URLs such as
  `https://stosnopmediaqa01.blob.core.windows.net/digiwrap-media/0001554_digital-tissue-paper_600.jpeg`.
- The warmed homepage returned HTTP 200 in about 0.9-1.3 seconds.
- Sample Blob media returned HTTP 200 with correct `image/png` and `image/jpeg`
  content types.
- The broad `/app/wwwroot` NFS mount was removed for DigiWrap. The deployment
  now mounts only `App_Data`, `Plugins`, `Themes`, `wwwroot/files`,
  `wwwroot/sitemaps`, and an ephemeral `wwwroot/bundles`.
- After the mount change created a new pod, the first warm-up request was slow
  at about 30 seconds, then steady-state requests returned to about one second.
- No app log errors were observed during the pilot; the only warning was the
  expected ASP.NET port override message from the container image.

This proves the first storage optimization: generated public image URLs no
longer depend on the restored NFS `wwwroot/images/thumbs` tree for DigiWrap.
It does not yet prove admin image upload behavior because that still needs an
authenticated admin test.

### OpenSoft QA Homepage Warm and Prefetch Pilot Result

Implemented on 2026-06-26 against the current OpenSoft QA DR cluster:

```text
Subscription: sub-os-qa-platform
Cluster: aks-os-drtest-qa-01
Script: scripts/apply-opensoft-nopcommerce-cache-pilot.sh
Namespace: nopcommerce-cache
CronJob: opensoft-nopcommerce-homepage-warmer
Schedule: every 2 minutes
```

This pilot deliberately avoids ingress full-page caching. nopCommerce pages can
vary by cookies, cart state, language, customer role, and admin state, so caching
HTML at ingress needs a much stricter design. The implemented low-risk behavior
is:

- Patch every mounted theme that has `Views/Shared/Head.cshtml` and install
  `opensoft-prefetch.js`.
- Detect restored themes automatically instead of hard-coding a single theme.
  The 9-site restore currently includes `DefaultClean`, `Venture`, `ONPTheme`,
  and `Traction`.
- Remove the older ONP fallback loader from `ONPTheme/Content/js/onp-theme-script.js`
  once the standard theme script reference is present, so ONP pages do not run
  the warm-fetch script twice.
- Warm-fetch a small host-tuned number of same-origin, above-the-fold links
  after browser idle using explicit low-priority `fetch()` requests.
- Current idle limits are: DigiWrap `0`, Overnight Prints `1`, Rentapress `2`,
  EDS QA `2`, and default `1`.
- Warm-fetch the exact same-origin link on hover, focus, or touch intent using
  high-priority `fetch()` when it has not already been warmed.
- DigiWrap intent warming is currently disabled because its target warm fetches
  did not complete before click and could compete with navigation.
- If a user clicks a link while a warm fetch for that same URL is still in
  flight, the script aborts the warm fetch before navigation.
- Skip admin, login, register, logout, cart, wishlist, checkout, customer,
  order, password recovery, and search paths, including localized paths such as
  `/en/cart`.
- Add `dns-prefetch` and `preconnect` for cross-origin media, such as the DigiWrap
  Blob media endpoint.
- Avoid running on data-saver or very slow network modes.
- Run a Kubernetes CronJob that warms every ingress hostname through
  `ingress-nginx` from inside the cluster, using the real Host header and TLS
  route.

The script is idempotent:

- It compares the live theme script before writing.
- It updates existing theme references without duplicating them.
- It restarts only deployments whose theme files changed.
- It updates the warmer `ConfigMap` and `CronJob` declaratively from discovered
  ingress hosts.

Verification on 2026-06-26:

- All nine nopCommerce deployments rolled out successfully and were `1/1`.
- All 11 ingress host bindings returned HTTP 200 from a clean warmed CronJob
  run.
- Clean warmed homepage timings were mostly below 0.5 seconds, with
  `staging.rentapress.com` at about 1.2 seconds.
- All 11 host bindings served JavaScript containing either the warm-fetch
  implementation or the ONP loader.
- Headless browser smoke tests passed for `digiwrap.davinci-designer.com` and
  `qa1.overnightprints.eu`.
- The browser created expected warm fetches:
  - DigiWrap: likely product-page warm fetches plus Blob preconnect.
  - ONP: likely product-category warm fetches.
- No OpenSoft warm-fetch console errors were observed.
- The guard rules prevented warming localized cart/wishlist paths and
  literal `/null` media hints.

Acceptance criteria for the storage pilot:

- Home page and catalog pages return HTTP 200.
- Product/category images load from Blob or Front Door.
- Admin image upload writes to Blob and survives pod restart.
- A pod restart does not require NFS for `wwwroot/images`.
- Plugin list and active theme survive pod restart with plugin/theme content
  supplied by the image or release artifact.
- DR restore becomes SQL import plus Blob restore/copy plus image tag selection,
  with NFS no longer containing public media or bulk plugin payload.

## Disk Strategy

The current hypothesis is that nopCommerce needs "some local disk." More
precisely:

- It needs writable paths during install and runtime.
- It does not need durable local node disk for product media if Blob is enabled.
- Local pod storage is fine for temporary cache/bundle output.
- Durable app state should be externalized to SQL, Blob, Redis, or a PVC.

## Observed FarHeap QA Reference

The existing FarHeap QA cluster has running nopCommerce/GPS installs and is the
best concrete reference for the first OpenSoft test.

Observed cluster:

- Subscription: `Microsoft Sponsorship FH 2026`
- Resource group: `aks-davincisite-qa`
- Cluster: `aks-davincisite-qa`
- Region: `westus`
- Kubernetes: `1.33.3`
- Node pool: `nodepool1`, system mode, `Standard_D4s_v6`, `2` nodes
- Network/runtime: Azure CNI/Cilium, Azure Linux 3.0 nodes, containerd
- Ingress: `ingress-nginx`
- Certificates: `cert-manager` with `letsencrypt-prod`

Observed nopCommerce/GPS workload shape:

- One namespace per site/store.
- One Helm release per site/store, chart `gps-2.2.3`.
- Images are mostly `nopcommerceteam/nopcommerce:4.80.3`; one observed site
  uses `4.80.8`.
- Each site runs one pod/replica.
- Deployment strategy is `Recreate`, which fits the mutable shared file layout.
- Container requests are `500m` CPU and `512Mi` memory.
- Container limits are `1` CPU and `2Gi` memory.
- Idle observed memory was about `600Mi` to `770Mi` per nopCommerce pod, with
  very low idle CPU.
- Service is `ClusterIP` on port `80`.
- Ingress terminates through NGINX and routes public hostnames to each service.
- `HostingConfig__UseProxy` is set for nopCommerce behind ingress.

Observed NFS storage shape:

- Static PV per app/site.
- PVC per namespace.
- `ReadWriteMany`.
- `Retain` reclaim policy.
- Each PVC requests `1Gi`, while the backing Azure Files NFS share is the shared
  larger storage object.
- NFS server: Azure Files endpoint.
- NFS path pattern:

```text
/<storage-share>/gps-qa/<site-name>/
```

Observed mount options:

```text
nfsvers=4.1
sec=sys
nconnect=8
```

Observed nopCommerce volume mounts:

```text
/app/App_Data/plugins.json
/app/App_Data/DataProtectionKeys
/app/Plugins
/app/Themes
/app/wwwroot
```

Observed SQL/config shape:

- Azure SQL server and elastic pool are supplied through Helm values.
- Each site has its own database name.
- The deployment sets `ConnectionStrings__ConnectionString` as an environment
  variable.
- The chart includes config maps for database creation, login creation, store
  update, plugin sync, plugin list, and snapshot actions.

OpenSoft implication: Plan for the first OpenSoft nopCommerce test to be
single-replica, Helm-driven, and NFS-backed like this reference. Then harden
from there by moving secrets to Kubernetes Secrets or External Secrets, moving
plugins/themes into an image, and moving media to Blob if the plugin path works
cleanly.

## DR Strategy

Detailed backup and restore steps now live in
`docs/opensoft-nopcommerce-dr-runbook.md`. Keep this section as the design
summary and use the runbook for the actual cross-tenant test.

The DR design needs two lanes:

1. Operational restore inside the same tenant/subscription.
2. Portable rebuild into a different tenant/subscription.

Azure-native backup features are useful for lane 1, but they are not enough by
themselves for lane 2. The cross-tenant DR test must be able to recreate the
platform from code and portable data exports.

### Source of Truth

The production platform should be rebuildable from:

- infrastructure as code for resource groups, VNet, AKS, storage, SQL, Redis,
  identity, Key Vault, ingress public IP, and DNS bindings
- Helm chart plus environment-specific values for each nopCommerce site
- portable SQL database exports
- portable Azure Files NFS folder exports
- secret material restored from Key Vault/secure escrow into the target tenant
- a small restore manifest describing backup timestamp, site name, database,
  file backup object, app image tag, Helm chart version, and target settings

Do not rely on the source AKS cluster as the source of truth. Kubernetes objects
can be backed up for convenience, but the rebuild should work from Git/IaC plus
data backups.

### SQL Backups

Use both native Azure SQL backups and portable exports:

- Enable Azure SQL automated backups and point-in-time restore for operational
  recovery.
- Configure long-term retention for compliance and long rollback windows.
- Export each nopCommerce database to BACPAC on a schedule for cross-tenant DR.
- Copy BACPAC files to a backup storage account that is not dependent on the
  source AKS cluster or source resource group.

Azure SQL point-in-time restore is excellent for same-server recovery, but
Microsoft documents that cross-server, cross-subscription, and cross-geo PITR are
not currently supported for Azure SQL Database. Geo-restore handles some regional
cases, but it is not the portable cross-tenant restore path we want. BACPAC
export/import is slower, but it is portable and testable in a clean tenant.

Sources:

- [Azure SQL automated backups](https://learn.microsoft.com/en-us/azure/azure-sql/database/automated-backups-overview?view=azuresql)
- [Restore Azure SQL Database from backups](https://learn.microsoft.com/en-us/azure/azure-sql/database/recovery-using-backups?view=azuresql)
- [Azure SQL long-term retention](https://learn.microsoft.com/en-us/azure/azure-sql/database/long-term-backup-retention-configure?view=azuresql)

### NFS/File Backups

Use both Azure Files NFS snapshots and portable file exports:

- Enable Azure Files NFS snapshots for quick operational file restore.
- For cross-tenant DR, run a scheduled export from each app folder on the NFS
  share to immutable/versioned blob storage.
- Store file backups as a versioned archive, for example:

```text
backups/nopcommerce/<site>/<timestamp>/files.tar.zst
backups/nopcommerce/<site>/<timestamp>/manifest.json
backups/nopcommerce/<site>/<timestamp>/sha256.txt
```

Use `tar` for the file export so Linux permissions, symlinks, case-sensitive
paths, and directory structure survive the move. That matters more than raw
object-level copying for this NFS-backed nopCommerce layout.

Azure Backup for Azure Files is valuable for SMB shares, but Microsoft
documents that Azure Backup does not currently support NFS Azure file shares.
Microsoft also documents that AKS backup does not support Azure Files NFS
persistent volumes. That means portable DR needs its own file export/sync path.

Sources:

- [Azure Files backup support matrix](https://learn.microsoft.com/en-us/azure/backup/azure-file-share-support-matrix)
- [Back up Azure Files](https://learn.microsoft.com/en-us/azure/backup/backup-azure-files)
- [Restore Azure Files](https://learn.microsoft.com/en-us/azure/backup/restore-afs)
- [Azure Files NFS snapshots](https://learn.microsoft.com/en-us/azure/storage/files/storage-snapshots-files)
- [AKS backup support matrix](https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-cluster-backup-support-matrix)

### Kubernetes Backups

Use Kubernetes backups as a convenience layer, not the primary DR mechanism.

Recommended approach:

- Install Velero or Azure Backup for AKS after the first app is stable.
- Back up Kubernetes objects, namespaces, Helm release metadata, config maps,
  ingress, services, PVC/PV definitions, and selected secrets if policy allows.
- Store Velero backups in a dedicated backup storage account/container.
- Do not depend on Azure Files volume snapshots for cross-tenant DR.
- Prefer restoring workloads from Helm/Git in the target tenant, then attaching
  restored SQL and NFS data.

Velero can write backups to Azure Blob and can be configured with Azure backup
locations across resource groups/subscriptions. It is useful for migration and
inspection, but the OpenSoft DR runbook should still be able to rebuild from IaC
and portable SQL/file backups.

Sources:

- [Azure Backup for AKS](https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-cluster-backup)
- [Restore AKS using Azure Backup](https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-cluster-restore)
- [Velero Azure plugin](https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure/blob/main/README.md)
- [Velero backup locations](https://velero.io/docs/v1.9/locations/)
- [Velero file system backup](https://velero.io/docs/v1.10/file-system-backup/)

### Backup Consistency

nopCommerce writes to both SQL and NFS. A clean backup should avoid taking a SQL
snapshot and file snapshot while the app is actively mutating plugins, themes,
images, or configuration.

For the first DR tests, use a conservative backup window:

1. Put the store in maintenance mode or block public writes.
2. Scale the nopCommerce deployment to `0`.
3. Export SQL database to BACPAC.
4. Export the site's NFS folder to `files.tar.zst`.
5. Write `manifest.json` with image tag, chart version, source namespace,
   database name, SQL export path, NFS export path, and checksums.
6. Scale the deployment back to `1`.
7. Run a smoke test.

After the process is proven, decide whether we can use online backups for lower
RPO. For now, correctness matters more than shaving minutes.

### Cross-Tenant DR Test Runbook

The target tenant test should prove that the source tenant is not required.

1. Create or select a clean target tenant/subscription.
2. Deploy baseline Azure resources from IaC:
   - resource groups
   - VNet/subnets/private DNS
   - AKS PlanA1 or current candidate plan
   - Azure Files Premium/NFS share with private endpoint
   - Azure SQL logical server/database or elastic pool
   - Redis
   - Key Vault
   - ingress public IP/DNS placeholder
3. Restore secrets into the target Key Vault or External Secrets backend.
4. Import the selected SQL BACPAC into the target Azure SQL database.
5. Create the target app folder in Azure Files NFS.
6. Extract `files.tar.zst` into that target app folder.
7. Install baseline platform components:
   - ingress-nginx
   - cert-manager with a Let’s Encrypt `ClusterIssuer`
   - external-secrets
   - monitoring/logging
   - Velero/Azure Backup agent if used for inspection
8. Helm install the nopCommerce site with target-tenant values:
   - target SQL server/database
   - target NFS server/share/path
   - target Redis
   - target host name
   - same image tag and chart version from the manifest
9. Test with a temporary DR hostname before touching production DNS.
10. Run acceptance tests:
    - app boots without install mode
    - admin login works
    - catalog pages load
    - product images load
    - uploads work
    - SQL writes work
    - NFS writes work
    - restart pod and verify state persists
11. Record actual RTO, data age/RPO, restore gaps, and manual steps.
12. Tear down the target tenant resources or keep them as the next DR target.

Ingress and TLS are required platform dependencies, not optional site features.
When rebuilding the OpenSoft AKS target, install cert-manager before creating
site ingress resources, create the `letsencrypt-prod` `ClusterIssuer`, and set
each site ingress `spec.tls` to the DR or production hostname. The first DR test
proved this with `drtest.davinci-designer.com` and the TLS secret
`drtest-davinci-designer-tls`.

On AKS, annotate the `ingress-nginx` LoadBalancer service so Azure uses TCP
health probes on ports `80` and `443`. HTTP probes to `/` can fail before the
right host rule is selected and make the public IP look dead even when NGINX and
the app are healthy.

### DR Acceptance Criteria

The DR process is not real until it is tested end-to-end.

Minimum pass criteria:

- A new tenant can run the site without access to the old AKS cluster.
- Restore uses only Git/IaC, secret escrow/Key Vault restore, SQL export, and
  NFS file export.
- No manual pod edits are required.
- DNS can be pointed at the restored ingress after validation.
- The restore runbook is repeatable by cloudBench.
- The team knows the measured RTO and RPO.

### DR Decisions To Make

- Backup target: source tenant backup account, separate OpenSoft backup
  subscription, or third-party/off-Azure escrow.
- Backup frequency: nightly, before release, and before risky admin/plugin
  changes at minimum.
- Retention: short operational retention plus monthly/quarterly long-term
  retention.
- Whether production media remains on NFS or moves to Blob before the first DR
  test.
- Whether the DR target is warm enough to keep SQL/AKS skeleton resources ready,
  or cold and built entirely on demand.

### Existing OpenSoft/GPS Pattern

The existing GPS application pattern is:

- one Azure Files Premium/NFS share connected privately to the AKS network
- minimum share size of `100Gi`
- NFS interface exposed to AKS apps
- each application mounts only one folder inside the large shared file share
- capacity can be expanded centrally as the environment grows
- multiple apps share the same storage account/share design instead of attaching
  many independent disks

This is a good fit for the first nopCommerce AKS tests because nopCommerce needs
writable shared state during install and early runtime proving. It also avoids a
pile of per-app Azure Disks.

The guardrails are:

- treat the shared Azure Files account/share as a shared performance and failure
  domain
- give each app its own folder and PVC/PV mapping; do not mount the whole share
  casually into every pod
- keep folder names, ownership, and permissions explicit
- avoid using the NFS share as the long-term high-traffic media serving path if
  the nopCommerce Azure Blob plugin works cleanly
- benchmark nopCommerce file-heavy actions against the share before assuming it
  is fine for production plugin/theme/media behavior

Microsoft's current AKS/Azure Files docs align with this shape: Azure Files can
provide RWX volumes for multiple pods, NFS is supported through the Azure Files
CSI driver, Premium/NFS shares have a `100Gi` minimum, and private endpoints can
keep storage traffic inside the virtual network.

Sources:

- [Azure Files persistent volumes in AKS](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-files)
- [Azure Files for AKS workloads](https://learn.microsoft.com/en-us/azure/storage/files/azure-kubernetes-service-workloads)
- [Azure Files NFS](https://learn.microsoft.com/en-us/azure/storage/files/files-nfs-protocol)

AKS storage choices:

- Azure Disk: good performance, `ReadWriteOnce`, one node/pod writer. Better for
  a single-replica first test.
- Azure Files NFS: shared `ReadWriteMany`, multiple pods can mount it. This is
  the existing OpenSoft/GPS pattern and should be the first nopCommerce test
  storage shape.
- Azure Blob CSI/NFS/blobfuse: possible for shared blob-backed mounts, but the
  nopCommerce plugin is the cleaner media path.
- `emptyDir`: good for scratch/cache only. Data is lost when the pod is replaced.

Sources:

- [AKS storage options](https://learn.microsoft.com/en-us/azure/aks/concepts-storage)
- [Azure Files for AKS workloads](https://learn.microsoft.com/en-us/azure/storage/files/azure-kubernetes-service-workloads)
- [AKS storage best practices](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-storage)
- [Azure Disk persistent volumes](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-disk)

First test PVC layout:

```text
/mnt/opensoft-nfs/nopcommerce-test2/App_Data          persistent
/mnt/opensoft-nfs/nopcommerce-test2/wwwroot/files     persistent or Blob-backed later
/mnt/opensoft-nfs/nopcommerce-test2/wwwroot/sitemaps  persistent or generated by one admin pod
/tmp                                                   emptyDir
```

Avoid mounting an empty PVC over `/app/Plugins`, `/app/Themes`, or all of
`/app`, because that can hide files already present in the container image. For
production, bake plugins and themes into a custom image instead of installing
them manually into a running pod.

## Web Farm and Admin Behavior

nopCommerce's web farm docs call out distributed cache and file replication for
multi-instance setups. The docs also state that file-replication-sensitive paths
include `/App_Data`, `/Plugins`, `/Themes`, and `/wwwroot`.

On AKS, the equivalent design is:

- run all immutable application code, plugins, and themes from the image
- use Blob for media
- use Redis for cache/session coordination
- use a single admin-safe rollout process for plugin/theme changes
- avoid sticky reliance on one pod's filesystem

Source: [nopCommerce web farms](https://docs.nopcommerce.com/en/installation-and-upgrading/installing-nopcommerce/web-farms.html)

If ingress or a load balancer terminates TLS before nopCommerce, set
`HostingConfig.UseProxy=true` and verify forwarded header behavior.

Source: [nopCommerce HostingConfig](https://docs.nopcommerce.com/en/developer/tutorials/appsettings-json-file.html)

## Proposed Test Phases

### Phase 1: Single Replica Install

Goal: prove that nopCommerce installs and survives pod restart.

- 1 nopCommerce replica
- Azure SQL Database via private endpoint
- SQL auth secret
- Azure Files NFS-backed PVC/folder for `App_Data`
- no Blob plugin yet, unless install path is smooth
- no horizontal scale yet

Acceptance checks:

- install completes
- `App_Data/appsettings.json` persists
- restart pod does not return to `/install`
- admin login works
- product/category page loads
- database migration tables exist
- NFS read/write latency is acceptable for install, admin, plugin, sitemap, and
  media-related file operations

### Phase 2: Blob and Redis

Goal: make the app cloud-native enough for more than one pod.

- enable Azure Blob plugin for media
- enable Redis distributed cache
- configure proxy headers
- add health endpoints and ingress

Acceptance checks:

- uploaded image persists after pod restart
- image URL comes from expected blob/front-door path
- Redis keys appear during traffic
- no new guest customer spam from health probes

### Phase 3: Multi-Replica

Goal: prove horizontal operation.

- 2 nopCommerce replicas
- Spot user pool allowed
- regular fallback pool available for non-Spot workloads
- PodDisruptionBudget
- anti-affinity if more than one regular node exists

Acceptance checks:

- traffic works across both pods
- admin/config change behavior is understood
- scheduled tasks do not duplicate
- Spot eviction does not corrupt app state

### Phase 4: Custom Image

Goal: remove mutable runtime application code.

- build OpenSoft nopCommerce image
- include approved plugins/themes
- keep only environment/config/secrets external
- stop relying on runtime plugin install for production

Acceptance checks:

- fresh cluster install is repeatable
- image rollback restores prior code
- no manual file changes are required in pods

### Phase 5: Performance Test

Goal: verify SQL and storage are not the bottleneck.

- load test catalog pages, cart flow, checkout path, admin image upload
- compare SQL Private Link Proxy versus Redirect if possible
- compare Azure Files versus Blob plugin for media behavior
- collect p95/p99 response times and SQL DTU/vCore metrics

## Open Questions

- Does nopCommerce 4.90 work cleanly with `DataConfig` supplied entirely through
  environment variables in AKS, or do we still need `App_Data/appsettings.json`
  persistence after install?
- Can we use Azure SQL managed identity authentication through nopCommerce's
  existing SQL provider without code changes?
- Which Redis option should become production default: Redis or Redis
  Synchronized Memory?
- Should media be public blob, private blob behind app, or Blob/Front Door/CDN?
- Which plugin/theme changes must be baked into the image before the first
  serious production test?
- Should the existing single Azure Files NFS share remain the long-term
  production storage pattern for nopCommerce, or should nopCommerce media move
  fully to Blob while NFS is limited to install/config state?
