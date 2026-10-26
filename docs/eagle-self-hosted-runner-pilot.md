# Eagle GitHub Actions runner pilot plan

## Goal

Evaluate EAGLE as a small, office-hosted GitHub Actions runner for Opensoft projects, beginning with one harmless, private-repository pilot. This plan makes no changes to EAGLE, GitHub organization settings, workflows, or runner registrations.

## Current evidence and decision

The current computer reports hostname `EAGLE`, Windows 11 build `10.0.26300`, model `NucBox_EVO-X2`, approximately 120 GB RAM, and an automatic/running OpenSSH server. That is enough to justify a capability assessment, but not to establish that EAGLE is continuously available, isolated, or suitable for executing repository code. OpenSSH is unrelated to GitHub runner connectivity and is not needed for this pilot.

EAGLE can potentially host a **Windows** self-hosted runner. It is not the Linux host described as the preferred organization-wide pool in `docs/opensoft-org-local-runners-plan.md`. Treat it as a single-runner, one-job-at-a-time pilot only. If EAGLE is Brett's everyday workstation, do not run repository jobs directly on its host OS. Prefer a disposable Hyper-V guest per job, with no shared folders, host credentials, personal files, or host Docker/admin access. The runner should register as ephemeral, execute one job, then be destroyed. If secure per-job isolation and reliable automatic cleanup are impractical on Windows, stop and use a dedicated Linux runner host or Azure ephemeral runners instead.

## Stage 1 — read-only preflight on EAGLE

Before installing anything, verify:

1. Whether EAGLE is a daily-use device or can be dedicated to CI; expected powered-on hours, office Internet/power reliability, and available disk capacity.
2. Windows edition and whether Hyper-V and nested virtualization are supported and enabled. Check free disk, virtualization support, current patch state, and whether policy permits local VMs.
3. Whether a clean Windows guest can be created and destroyed automatically for every job, and whether the guest can reach GitHub and required package feeds over outbound HTTPS without inbound firewall openings.
4. Whether this pilot needs Windows-specific tooling. For the org-wide Linux plan, EAGLE should not be labeled as a Linux runner or advertised to Linux jobs.
5. Whether GitHub will dispatch a manual job while the reported billing hold exists. A successful local build does not establish that GitHub will schedule a self-hosted job or produce the required PR check.

Record evidence without collecting secrets. Do not expose SSH, RDP, or other inbound services for runner operation.

## Stage 2 — security and organization setup (owner action)

Proceed only if the preflight supports per-job isolation and the device can be kept reliably available.

1. In GitHub, create a dedicated runner group restricted to one approved private pilot repository and a unique label such as `eagle-windows-x64`. Do not grant access to all Opensoft repositories for the pilot.
2. Keep public repositories and repositories that run untrusted fork pull requests off this runner. Do not place secrets, cloud identities, production/QA access, personal credentials, or broad organization tokens on the general test runner.
3. Provision a dedicated least-privilege runner identity in a clean guest. Use an ephemeral registration token only during provisioning. Prefer GitHub's ephemeral runner lifecycle so a runner accepts one job and deregisters afterward.
4. Configure the host-side controller to launch a clean guest per run, provision/register the runner, wait for completion, collect only approved job results, destroy the guest and its disks, and confirm cleanup even after cancellation or failure.
5. Keep host and guest patching, runner logs, and cleanup status observable. Use outbound-only networking and restrict egress to GitHub and the package feeds needed by the pilot.

If the pilot requires deployment or cloud credentials, stop: that requires a separate protected runner design, explicit repository/workflow restrictions, environment approval, and narrowly scoped OIDC permissions.

## Stage 3 — harmless end-to-end test

Use a private pilot repository with no production secrets and a manual-only workflow. The job should print a fixed non-sensitive marker, report runner OS/architecture and tool versions, run one small validation command, and exit. It should not build/publish an image, deploy, access a database, query a secret store, or access the office LAN.

The pilot workflow targets the exact runner group and label, for example:

```yaml
on:
  workflow_dispatch:

jobs:
  runner-smoke-test:
    runs-on:
      group: Eagle Pilot
      labels: eagle-windows-x64
    permissions:
      contents: read
    steps:
      - run: |
          Write-Output 'eagle-runner-smoke-test'
          $PSVersionTable.PSVersion.ToString()
```

Validate in order:

1. GitHub accepts the manual dispatch and queues it to the intended runner group.
2. The job runs on the isolated guest and reports Windows as expected; it does not run on the host.
3. The job has no unexpected token permissions, secrets, cloud identity, host mounts, or office network reachability.
4. The guest is destroyed after success, cancellation, and a deliberately induced non-sensitive failure; the ephemeral runner no longer appears online.
5. Repeat once to prove a fresh guest is used. Confirm the exact required PR check is successful if a PR check is part of the pilot.

If GitHub does not dispatch due to the billing restriction, do not interpret local execution as a successful runner test. Resolve the account-level restriction or choose an approved CI/status integration before deciding whether to proceed.

## Acceptance and stop conditions

Accept EAGLE for a limited Windows pilot only after all five end-to-end checks above pass, the guest isolation and teardown are demonstrated, and EAGLE's owner accepts the availability and maintenance burden. Do not expand runner-group repository access based on a single smoke test.

Stop and do not register the runner if per-job isolation is unavailable, the host is used for ordinary personal work without a reliable isolation boundary, jobs can access the host/office network, GitHub cannot dispatch jobs, or cleanup cannot be proven after failure. Move to a dedicated Linux host or Azure ephemeral pool for broader organization use.

## Rollback

Disable scheduling to the Eagle pilot group, remove the runner registration, revoke any temporary registration credentials, destroy remaining guest VMs/disks, and verify that no runner remains online. Restore the pilot workflow's prior runner target only if the previous CI path is available and funded; otherwise keep the check visibly blocked and resolve the runner or billing issue.

## References

- Organization runner groups and repository access: https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access
- Selecting groups and labels in workflows: https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/use-in-a-workflow
- Ephemeral self-hosted runner guidance: https://docs.github.com/en/actions/reference/runners/self-hosted-runners
- Self-hosted runner security: https://docs.github.com/en/actions/reference/security/secure-use
- Opensoft-wide local runner strategy: `docs/opensoft-org-local-runners-plan.md`
