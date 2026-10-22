# Design

## Context

The first inventory found 280 active repositories, 238 active workflow definitions and 196 definitions containing Linux hosted selectors. The inventory includes public repositories and OS matrices. Historical workflow records with missing source files are not edited. The current midNet service supports only two pinned workflows and lacks general hosted-image compatibility.

## Decisions

1. Use explicit self-hosted Eagle selectors. Do not rely on collision with GitHub-hosted labels or fallback, which can return jobs to the billing-blocked pool.
2. Keep OS/architecture requirements truthful. Portable Linux jobs migrate first; native Windows/macOS/hardware jobs require compatible execution. The user authorized a disposable Windows VM only without restarting Eagle, Docker or WSL, and confirmed there is no Mac. Native selectors use distinct platform labels; unavailable platforms remain queued.
3. Run general Linux workers inside a fresh rootless Docker backend. Provide only private workspace paths inside that backend for Docker actions/service containers. Sudo and Docker privilege remain within the user namespace, not Eagle's host.
4. Keep host authentication in the Windows controller. No host mounts, shared host Docker socket, bench credentials or private/LAN/metadata access enter general jobs. A separate fleet gateway supports public package endpoints; existing midNet isolation remains intact during migration.
5. Inventory and select repository access explicitly per organization. Preserve public-fork approval controls and deployment environments. Keep existing specialized self-hosted groups intact.
6. Poll repositories with a bounded interval and API budget, then provision only demanded pool/profile capacity. Bound aggregate resources and verify worker/backend/private-volume/registration cleanup before reuse.
7. Prepare narrow workflow PRs, read repository instructions, preserve non-routing content and matrix coverage, request Codex review and merge through repository policy. No protected deployment is approved by the migration.
8. Track the exact detached once-listener exec. Unregister only after its exit; GitHub's forced-delete endpoint is not a busy-job barrier. A root-owned pre-job hook waits for the Windows controller to persist a job deadline before services or action code start. Recovery observes the same exec. STOP stops replenishment and lets an existing listener finish one job; a registered idle listener is not forcibly retired merely because a busy read is false. Recheck the queued candidate before starting a listener so a cancelled demand does not intentionally leave idle capacity.

## Risks and gates

Container jobs differ from hosted VMs: swap, host sysctl, KVM, systemd, native Windows and macOS require explicit compatibility handling. Unsupported jobs stay visibly blocked with exact requirements. Public jobs use fresh user namespaces and retain existing GitHub approval rules. Broadening routing never broadens host credential access.

## Rollback

Retain old selectors and exact blob/head identities in the migration manifest. Revert routing PRs and disable only fleet-owned registrations/groups. Drain active jobs and preserve benches. Never restart shared Docker/WSL to complete migration.
