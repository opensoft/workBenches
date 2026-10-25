# v1.6.2 development — guided company connection

Issue: [#213](https://github.com/opensoft/workBenches/issues/213).
Development version only; no v1.6.2 release is published by this change.

## Installer fixes

Docker group onboarding now waits for the user's decision about signing out
and uses normal Omarchy/UWSM logout rather than forcibly terminating the login
session. Other environments retain acknowledged manual instructions. The
replacement desktop logout has fixture coverage; an attended successful
logout and return to the greeter remain unverified.

Applying selections resumes output below the complete navigation frame.
Installation reserves a fixed progress panel with scrolling live output,
plain-text fallback for small terminals and terminal restoration on exit.

Verification on 2026-10-25 passed 133 Python tests across Docker prerequisites,
progress, asynchronous setup, requirements, consent, release automation and
release versioning, plus both setup cancellation and bench-status shell suites.
These checks used an isolated source snapshot to preserve installation logs.

## Credential recovery scope

Release scope decision (Brett, 2026-10-24): v1.6.2 uses direct Azure Key Vault
recovery with interactive Azure device-code sign-in. Configure the selected
Claude/Codex profiles and the private Key Vault mapping, sign in to the mapped
Azure tenant, then restore the mapped secrets into those profiles. This route
does not require a company IdP registration or a credential broker. The signed-in
Azure user needs permission to read the mapped secrets, and tenant policy must
allow device-code sign-in. Profile creation alone does not retrieve credentials.

The existing implementation invokes `az login --tenant <tenant> --use-device-code`
when authentication is needed. Recovery checks the tenant, secret ownership tags,
provider format and exact secret version; existing local credentials are
preserved unless replacement is explicitly requested. See
[`setup-credential-recovery.py`](../scripts/setup-credential-recovery.py) and
[`backup-ai-profile-credentials-to-kv.sh`](../scripts/backup-ai-profile-credentials-to-kv.sh).
An attended restore and launcher check with the intended vault is still required;
fixture tests are not live acceptance.

Broker deployment, company credential synchronization, provider adapter
qualification and CPC refresh maintenance move to openProfiler, with pinned
workBenches integration targeted for v1.7 or v1.8 after qualification; see
[integration #229](https://github.com/opensoft/workBenches/issues/229). Existing broker
code remains opt-in; it is not a prerequisite or acceptance claim for the
v1.6.2 direct recovery route. This scope decision does not remove inherited code
or change the historical v1.6.0 release notes.

## Planned manifest-source scope — approved 2026-10-25

Workstation access is local to the computer running workBenches in v1.6.2.
Personal and company scopes are to support manifest import from local/hosted
files or a GitHub repository, with a remembered source and linked connection.
Private remote source authentication is browser-only; local files use filesystem
permissions and public files need no artificial sign-in. OneDrive/Google Drive
links require provider-specific authenticated retrieval, not just a copied URL.

Existing GitHub browser connections and company Keycloak sessions provide part
of the foundation. The scoped source-import/refresh workflow, binding repository
reads to the chosen GitHub connection, and Microsoft/Google file connectors are
not implemented by the company-connection wizard. Do not claim this expanded
scope is complete. See the [governed proposal](../openspec/changes/profile-manifest-sources/proposal.md).
Whether updates also include publishing remote edits is pending clarification.

Workstation-to-workstation communication is deferred to v1.8 through a service
shipped with workBenches, respecting openProfiler's reusable profile-management
ownership. No peer service is required for v1.6.2 file/repository imports.

## Guided company connection

First-time company login now explains application registration and opens a
guided connection menu: administrator enrollment import, registration guidance
and existing registration. The guide covers the current public-client/device
flow and offers explicit native browser/clipboard actions with manual fallback.
Existing configured companies retain their sign-in behavior.

Settings are reviewed in full, discovery is checked without claiming that a
client registration is verified, and the existing browser/device flow handles
actual sign-in. Non-secret enrollment exports are private, atomic and do not
overwrite existing files. Shared import validation rejects secrets/unknown
fields, redirects, invalid URLs and oversized input.

This does not implement arbitrary identity-provider support or automatic client
registration, collect administrator credentials, change broker/vault grants or
authenticate an AI-provider profile. It preserves existing device-flow trust
checks, cancellation, saved Profiles and company isolation. See the
[company connection guide](company-connection.md) and
[implementation verification](../specs/033-company-connection-wizard/quickstart.md).
