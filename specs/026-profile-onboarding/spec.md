# v1.6 Profiles onboarding

Status: implementation on `feature/profile-onboarding`; outside v1.5 release scope.

## User experience

Setup has three pages: Components, Requirements, and Profiles. Components retains
the existing benches, AI assistants, and tools columns. Requirements owns software
and container readiness. Profiles owns personal identity, GitHub links, company
identities, and access to existing AI account setup.

G opens Profiles and returns to the previous section/focus. P opens Requirements.
Arrow navigation also reaches Profiles after Requirements. Opening a profile
action never applies queued component changes.

First profile setup requests one personal email, encourages optional verified
personal GitHub linking, then offers company creation repeatedly. Each company
has a display name, company email, optional GitHub identity, and independently
configured organization sign-in. OpenSoft is one possible company; no OpenSoft
URLs or email domains are hardcoded or inferred.

Company configuration can be imported from an administrator-provided HTTPS URL
or local JSON file, or entered through the existing sign-in helper. The user
reviews issuer and public client ID before importing. Imported configuration
does not grant membership; browser approval and server authorization do that.

## Data and compatibility

- `~/.config/workbenches/profiles.json` (or XDG_CONFIG_HOME equivalent): version 1,
  one personal record and any number of company records. Stable company IDs are
  independent of display names; names that collide in AI scope are refused.
- Each profile stores email and optional GitHub numeric ID, login, and verification
  timestamp. Email is entered metadata, not proof of membership. GitHub linking
  verifies identity with `gh api user`; tokens stay in GitHub CLI storage.
- Company Keycloak configuration and short-lived sessions live under
  `workbenches/identities/<company-id>/`. Legacy workstation config/session files
  remain untouched and accessible through the Workstation account action.
- Private atomic writes use 0600 files. Passwords are entered only in provider
  authentication flows, never collected by this metadata wizard.
- Personal/company AI setup pre-fills ownership, email, and company name, with
  confirmation. Existing AI profiles remain; new identities append profiles.
- GitHub reuse is explicit. Authorizing another account can change GitHub CLI's
  active account and Git protocol preference; identity metadata is not automatic
  routing of GitHub CLI commands.
- Q/Ctrl+C cancels the current action and returns to setup. Completed profile
  steps remain saved. Normal return uses B; queued component changes survive.

## Boundaries

This change does not implement automatic per-project credential routing, a
credential broker, single-login recovery, or automatic Git author changes.
Project association and a remembered default profile require integration with
the separately maintained openRepoProject command and subsequent validation.
Company enrollment currently imports identity-server settings only; secret
mapping and provider grants remain in existing explicit AI/vault workflows.

## Acceptance

Personal onboarding, skipped GitHub, two companies, cancellation/resume, verified
GitHub metadata, private storage, independent company account roots, preservation
of legacy credentials and other AI identities, and Profiles navigation retaining
component selections must pass automated checks. Render the page at narrow and
standard terminal widths. Real provider/browser approval is a separate live QA
step; fixture checks must not be reported as live authentication evidence.
