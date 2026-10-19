# workBenches 1.6.0-rc.2

Prepared on 2026-10-19 after merging PRs #168 and #169 into `release/1.6.0`.
This supersedes rc.1 for candidate testing. The rc.1 tag remains unchanged;
v1.5.0 remains the stable release. All 12 bench source pins are unchanged.

## Changes since rc.1

- Consume the complete upstream openRepoTools snapshot at
  `586dea25e073caadc33002e0157376788678dee0`, including #237's deferred-hook
  activation fix. First startup reconciles hooks after workspace links exist.
- Preserve the common image-layer budget and update lifecycle acceptance to
  follow the current Profiles screen.
- Explain the optional personal credential-registry owner in advanced enrollment.
- Support selected host-shell installation on Arch, Manjaro, and EndeavourOS.

The [rc.1 scope and limitations](release-1.6.0-rc.1.md) still apply. Managed
company/provider examples remain disabled; fixtures do not certify live sharing.
Global Git helpers and SSH keys are not changed by the reviewed bootstrap port.

## Validation gates

Results must identify the actual tested commit; earlier PR runs are supporting
regression evidence, not proof of this candidate's exact commit. Automated
results are linked from the candidate preparation PR and release PR #167.

- [ ] Exact candidate source-lock and release regression checks.
- [ ] Exact candidate setup, Profiles, and declared broker/client/CPC fixtures.
- [ ] Exact candidate Tools-runtime and component-lifecycle containers.
- [ ] Raven: real browser/device-code handoff, multiple GitHub links/reuse,
  company sign-in/sign-out/reconnect, and fresh/repeat setup selections.
- [ ] Raven: validate selected Arch host-shell installation, including rerun.
- [ ] Eagle: equivalent live acceptance on Windows/WSL, with commit and results.
- [ ] Validate a supported provider mode and live managed-identity deployment,
  including tenant isolation, grants, conflicts, offline and login-required states.
- [ ] Review/CI and repeat source validation on the final clean main commit.

## Test from an isolated checkout

After the candidate tag is available:

```bash
git clone --branch v1.6.0-rc.2 https://github.com/opensoft/workBenches.git "$HOME/projects/workBenches-1.6.0-rc.2"
cd "$HOME/projects/workBenches-1.6.0-rc.2"
python3 scripts/release-workbenches.py check --tag v1.6.0-rc.2
./setup.sh
```

Setup changes the workstation according to the selections you approve. Preserve
existing projects and credentials; a separate source checkout does not isolate
user-level configuration. Record commit, platform, selected actions, and results.
Do not include tokens, device codes, or private account details in evidence.

Only after these gates pass: prepare final 1.6.0 version/lock, merge #167, validate
the final main commit, and publish the immutable stable tag and GitHub release.
