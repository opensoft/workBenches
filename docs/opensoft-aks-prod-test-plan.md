# OpenSoft AKS Production Candidate Test Plan

This document tracks the AKS configuration we intend to harden into the new
OpenSoft Azure production platform. The current process is intentionally
iterative: build a candidate cluster, run tests, tear it down completely, adjust
the plan, and rebuild until the configuration is boring, repeatable, and cheap.

## Current Intent

- Subscription: `sub-os-credits-partnersuccess-2026`
- Tenant: OpenSoft
- First test cluster name: `aks-os-drtest-test-01`
- First test region: `westus`
- First test plan: `PlanA1` adjusted for West US constraints
- Processor family: `Dlsv6` for the first West US build; keep Dlsv7 as the
  preferred candidate where Azure allows it
- Workload posture: one small regular system node, cold regular fallback, and
  Spot app capacity that scales from zero.

Use a dedicated resource group for each build/test/destroy cycle so teardown can
remove the whole resource group safely. Do not place unrelated resources in the
test resource group.

## First Test Build Result

The first OpenSoft DR target setup was provisioned on 2026-06-23 in the existing
credits subscription because `sub-os-sandbox-drtest-2026` was not yet available
in the OpenSoft tenant to the current operator.

```text
Subscription: sub-os-credits-partnersuccess-2026
Subscription ID: 13bd2833-45a6-4e51-8f24-83e0598f4cae
Platform resource group: rg-os-sandbox-drtest-test
Workload resource group: rg-os-workload-nopcommerce-test
Backup staging resource group: rg-os-backups-drtest-test
Region used for runtime resources: westus
AKS cluster: aks-os-drtest-test-01
Kubernetes: 1.34
SQL server: sql-os-nopcommerce-test-03
SQL database: sqldb-os-nopcommerce-test2-test-01
NFS storage account/share: stosnopdrtst01 / nopcommerce-test
Backup storage account/container: stosbkdrtst01 / nopcommerce-dr
```

Actual node pools:

| Pool | Type | Size | Min | Max | Billing |
|---|---|---:|---:|---:|---|
| `sysres` | System | D2ls_v6 | 1 | 1 | Linux PAYG |
| `sysfb` | User fallback | D2ls_v6 | 0 | 2 | Linux PAYG |
| `sysspot` | Spot user | D2ls_v6 | 0 | 1 | Linux Spot |
| `appsmlspt` | Spot user | D2ls_v6 | 0 | 5 | Linux Spot |
| `appmedspt` | Spot user | D4ls_v6 | 0 | 5 | Linux Spot |
| `applgspt` | Spot user | D8ls_v6 | 0 | 5 | Linux Spot |

West US was selected because Azure SQL server creation was blocked in `eastus`
and `eastus2` for this subscription, while `westus` succeeded. AKS in `westus`
does not allow `D2ls_v7`, but it does allow the matching Dlsv6 family, so this
test uses Dlsv6 consistently.

## Validated Constraints

These constraints were found with ARM preflight validation in the OpenSoft
subscription on 2026-06-23. Validation does not create the cluster.

- `Standard_D2s_v5` is not allowed for AKS in OpenSoft `eastus`.
- `Standard_B2s` is not allowed for AKS in OpenSoft `eastus`.
- `Standard_D4als_v7` and `Standard_D8als_v7` are not allowed for AKS in
  OpenSoft `eastus`.
- `Standard_D2ls_v7`, `Standard_D4ls_v7`, and `Standard_D8ls_v7` validated.
- `westus` allowed the Dlsv6 family for AKS but rejected `Standard_D2ls_v7`.
- Azure SQL logical server creation was blocked in `eastus` and `eastus2`, but
  succeeded in `westus`.
- Spot pools must be user pools. They should be tainted so only workloads that
  explicitly tolerate Spot land there.

Keep node pools in the same CPU family where practical. For the original East
US candidate that meant using the `Dlsv7` family consistently:

```text
Standard_D2ls_v7
Standard_D4ls_v7
Standard_D8ls_v7
```

For the first West US build, use the matching Dlsv6 family consistently:

```text
Standard_D2ls_v6
Standard_D4ls_v6
Standard_D8ls_v6
```

## PlanA1

PlanA1 is the first test configuration. It keeps the idle cost low but preserves
a cold regular fallback pool that can scale up when Spot is unavailable or a
workload should not run on Spot.

Pricing is VM compute only, based on Azure Retail Prices API values for
`eastus`, using 730 hours per month. It excludes managed disks, load balancer,
public IPs, NAT gateway, Log Analytics, ACR, bandwidth, and any AKS support tier
charges.

| Pool | AKS pool name | Type | Size | Min | Max | Billing | Monthly min | Monthly max | Yearly min | Yearly max |
|---|---|---|---:|---:|---:|---|---:|---:|---:|---:|
| system-small-regular | `sysres` | Regular system | D2ls_v7 | 1 | 1 | Linux PAYG | $85.41 | $85.41 | $1,024.92 | $1,024.92 |
| system-small-spot | `sysspot` | Spot user | D2ls_v7 | 0 | 1 | Linux Spot | $0.00 | $15.78 | $0.00 | $189.41 |
| system-regular-fallback | `sysfb` | Regular user | D2ls_v7 | 0 | 2 | Linux PAYG | $0.00 | $170.82 | $0.00 | $2,049.84 |
| app-small-spot | `appsmlspt` | Spot user | D2ls_v7 | 0 | 5 | Linux Spot | $0.00 | $78.92 | $0.00 | $947.04 |
| app-medium-spot | `appmedspt` | Spot user | D4ls_v7 | 0 | 5 | Linux Spot | $0.00 | $157.84 | $0.00 | $1,894.04 |
| app-large-spot | `applgspt` | Spot user | D8ls_v7 | 0 | 5 | Linux Spot | $0.00 | $316.35 | $0.00 | $3,796.19 |
| **PlanA1 total** |  |  |  |  |  |  | **$85.41** | **$825.12** | **$1,024.92** | **$9,901.45** |

## Dev/Test Pricing Note

This plan uses Linux AKS node pools. Azure Dev/Test pricing does not reduce the
Linux VM meters below the Linux PAYG rates. Dev/Test can reduce Windows and SQL
dev/test costs, but it is not a meaningful discount for these Linux AKS nodes.

For `Standard_D2ls_v7` in `eastus`:

```text
Linux PAYG:       $0.117/hr
Windows PAYG:     $0.209/hr
Windows Dev/Test: $0.117/hr
```

## PlanB Reserve Study

PlanB is the reserve-backed variant to revisit after Azure exposes or confirms
reservation pricing for the v7 sizes in the portal.

Desired PlanB changes:

- Reserve one `D2ls_v7` small regular system node for 3 years.
- Reserve one `D4ls_v7` regular app fallback node for 3 years.
- Keep regular app fallback overflow at `0` to `2` PAYG nodes.

The Azure Retail Prices API did not return 1-year or 3-year reservation rows for
`D2ls_v7` or `D4ls_v7` on 2026-06-23, so PlanB should not be treated as priced
until the reservation purchase flow confirms the exact monthly equivalent.

## Build/Test/Destroy Loop

Each iteration should follow the same loop:

1. Update this document with the candidate plan and assumptions.
2. Run ARM or Bicep validation against the target subscription and region.
3. Create the cluster in a dedicated test resource group.
4. Install only the baseline platform pieces required for the test.
5. Run the acceptance checks below.
6. Capture actual cost, scaling, scheduling, and reliability observations.
7. Tear down the entire test resource group.
8. Confirm no `aks-os-drtest-test-01` resources remain.
9. Adjust the plan and repeat.

## Acceptance Checks

Minimum checks for each build:

- Cluster creates without manual portal intervention.
- All node pools reach expected min/max settings.
- Spot pools are tainted and regular workloads do not land there by accident.
- Test workloads with Spot tolerations schedule onto Spot pools.
- Test workloads without Spot tolerations schedule onto regular pools when
  regular capacity is enabled.
- Cluster autoscaler scales Spot pools from zero.
- Cluster autoscaler scales cold fallback pools from zero.
- Workloads survive Spot eviction according to their intended reliability class.
- Teardown deletes all cluster-managed resources, node resource groups, disks,
  public IPs, load balancer resources, identities, and role assignments created
  for the test.

## Teardown Rule

The safest teardown is deleting the dedicated resource group for the iteration.
Before deletion, confirm the resource group contains only resources created for
that iteration.

After teardown, verify:

```bash
az aks show -g <test-resource-group> -n aks-os-drtest-test-01
az resource list -g <test-resource-group> -o table
```

Both commands should show that no test cluster resources remain.

## Open Questions

- Use the nopCommerce deployment research in
  `docs/nopcommerce-aks-install-research.md` when adding the first storefront
  workload to this AKS test cycle.
- Use `docs/opensoft-nopcommerce-dr-runbook.md` to prove backup and restore into
  a different tenant/subscription before treating the platform as production
  ready.
- Confirm whether the Azure portal offers reservations for `D2ls_v7` and
  `D4ls_v7`, even though the Retail Prices API did not expose reservation rows.
- Decide whether the production promotion should remain in `eastus` or use a
  second region after the test cycle is stable.
- Include `ingress-nginx` and `cert-manager` in every repeatable AKS build. A
  rebuilt cluster is not browser-testable until it has an ingress controller,
  a Let’s Encrypt `ClusterIssuer`, and a TLS-enabled ingress for the DR/test
  hostname. Still decide the remaining baseline add-ons: external-dns, workload
  identity, monitoring, backup, and policy.
- Decide whether production should keep cold fallback at `0` to `2` or reserve
  one regular app fallback node after we observe Spot behavior.
