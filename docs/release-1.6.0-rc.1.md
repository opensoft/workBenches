# workBenches 1.6.0-rc.1

Scope frozen on 2026-10-19 at Brett's request. This is a release candidate for
testing, not a stable release or authorization to activate company credential
sharing. v1.5.0 remains the latest stable product release.

## Source identity

- Feature input: `feature/profile-onboarding` at
  `edefc67c340603a783876cdf1b424b3d9f1093db`.
- Stable fixes: `main` at `5880c09bf019f3166316d957e8fa26cd98c2ed54`.
- Candidate branch: `release/1.6.0`; intended annotated tag: `v1.6.0-rc.1`.
- `VERSION` and `config/release-lock.json` identify `1.6.0-rc.1`.
- All 12 existing source pins are preserved; no bench checkout, running bench,
  credential, or provider configuration is changed by the source freeze.

Tags are immutable. Candidate fixes use a new candidate version/tag; stable
`v1.6.0` requires validation of its own exact commit and source lock. External
packages, vendor downloads, and mutable image references are not fully frozen.

## Included scope

- Multiple personal/company email identities and explicit identity defaults.
- Keyboard Profiles manager and reusable, verified GitHub account links.
- Independent company sign-in configuration and sessions.
- Opt-in credential broker/client, versioned publication and conflict recovery.
- Workstation synchronization controls and CPC maintenance/attention handling.
- Existing stable setup, launcher, Windows/WSL, and release-validation fixes.

No new provider mode is enabled by this candidate. Example profiles remain
disabled; company enrollment, publication, and managed paths require explicit
authorization and configuration. Existing direct-user vault recovery remains a
separate compatibility path, never a fallback for denied broker authorization.

## Evidence and remaining gates

The implementation evidence in the
[Profiles tasks](../specs/026-profile-onboarding/tasks.md) and
[company synchronization tasks](../specs/027-company-credential-sync/tasks.md)
predates this freeze and must not be represented as validation of this exact
candidate. Candidate test results and CI belong to the release PR/tag checks.

Before stable publication:

- [ ] Validate the exact integrated candidate with release, setup, Profiles,
  broker/client/CPC, and declared container/runtime tests.
- [ ] Exercise real GitHub browser approval and account linking/reuse.
- [ ] Exercise independent real company sign-in, sign-out, and reconnect.
- [ ] Complete live Profiles acceptance on the claimed workstation platforms;
  do not inherit v1.5 platform certification for new v1.6 workflows.
- [ ] Select and validate a supported provider mode and live managed-identity
  Key Vault deployment, including isolation, grants, conflicts, offline recovery,
  and login-required behavior. Unsupported modes remain disabled.
- [ ] Complete required review/CI and repeat release validation on the final
  clean main commit before tagging and publishing stable v1.6.0.

No real credentials or Azure resources are needed for fixture tests. Test
success does not establish provider permission to share subscription sessions.

## Testing this candidate

After the candidate tag is available:

```bash
curl -fsSL https://raw.githubusercontent.com/opensoft/workBenches/v1.6.0-rc.1/bootstrap.sh -o workbenches-bootstrap.sh
bash workbenches-bootstrap.sh --branch v1.6.0-rc.1 --directory "$HOME/projects/workBenches-1.6.0-rc.1" --setup
```

Use a separate checkout and preserve existing projects and credentials. Running
setup is a real workstation operation and applies only explicitly selected
changes. Selecting an older source tag does not automatically roll back installed
containers, tools, or user data.
