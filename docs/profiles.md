# Profiles (v1.6 development)

This feature is on `feature/profile-onboarding`, outside the v1.5 release.

The broader [v1.6 plan](release-1.6.0.md) also targets broker-controlled company
credential publication/synchronization and a scheduled CPC maintenance worker.
Broker/client/CPC code and company synchronization controls are implemented on
this branch, with real deployment/provider QA pending. See the
[synchronization guide](company-credential-sync.md) and
[specification](../specs/027-company-credential-sync/spec.md).

Setup has three pages. Components selects software; Requirements manages Docker,
Tools, and Vault readiness; **Profiles** manages personal and company identities.
Press **G** to open Profiles and **Enter** on **Personal & companies**. Resolve
required software readiness first. Profiles actions do not apply queued installs.

First enter your personal email, then optionally connect your personal GitHub
account. GitHub CLI (`gh`) must be installed on the native workstation. Connect
can authorize in the browser or reuse the active authenticated account. The
verified account is shown for confirmation before linking. A link records a
verified identity at that time; it is not a live permission or token-health check.
Authorizing a different GitHub account can change GitHub CLI's active account and
HTTPS/SSH preference. Workstation credentials remain in GitHub CLI's own storage.

Next add as many companies as needed. Each gets its own name and work email.
Open a company to link/reuse GitHub, import organization enrollment, connect or
sign out of the company account, or configure AI accounts. Membership is verified
by the organization's sign-in service, never by the email domain alone.

An administrator can supply a local JSON file or HTTPS URL with this content:

```json
{
  "issuer": "https://identity.example.org/realms/company",
  "clientId": "openworkbenches-cli",
  "organizationId": "company",
  "credentialBrokerUrl": "https://credentials.example.org"
}
```

Choose **I Import enrollment** and review the displayed realm and public client
before saving. Redirects are refused; use the final trusted URL. Alternatively,
**C Company sign-in** prompts for the realm and client if none is configured.
Passwords and MFA stay in the browser. Each company's local session is separate.
After successful company sign-in, setup shows the email confirmed as verified by
the sign-in server and offers to use it for that company profile. It does not
replace your personal email or infer company membership from an email domain.
A current existing workstation login with a retained verified email also supplies
a suggested company email during company creation. Older sessions did not retain
email; reconnect once to obtain it. Missing/unverified email leaves manual entry
available. Starting the Vault container alone supplies no account identity.

**A AI accounts** opens existing provider-profile setup with your identity's email
and ownership prefilled for confirmation. Company sign-in, GitHub access, vault
authorization, and AI provider authentication remain separate. Adding a new AI
identity preserves previously configured provider profiles; an existing profile
name is preserved rather than replaced.

Use **B** to return from a profile or manager. **Q** or Ctrl+C cancels the action;
completed steps remain saved and the TUI preserves queued component selections.
Existing v1.5 workstation account files remain available through **Workstation account**;
they are not automatically assigned to a company or migrated.

Metadata lives in `~/.config/workbenches/profiles.json`; company account files live
under `~/.config/workbenches/identities/<company-id>/`. `XDG_CONFIG_HOME` overrides
the configuration root. Metadata and sessions use private atomic writes. Tokens
are not stored in profiles.json. Company Keycloak sessions remain in the existing
account helper's private session format.

Project-to-profile selection and automatic per-project account routing are not
implemented in this increment. Profiles do not modify global Git author identity.
