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

The **Personal & companies** entry opens a keyboard-driven manager. At normal
terminal widths it shows a profile tree on the left and selected details on the
right; narrow terminals show details above a scrolling list. Use arrows to move,
Enter to open, B to go back, and Q/Ctrl+C to cancel without losing saved steps.

- **A Add personal** creates another named personal email identity.
- **C Add company** creates a company with its first work email identity.
- Open Personal or a company and use **A Add identity** for additional emails,
  **D Default** for its default identity, or Enter to manage an identity's accounts.
- On an identity, use **G Link GitHub**, **E Edit**, **D Default GitHub**,
  **U Unlink**, or **A AI accounts**. GitHub defaults are chosen from the linked
  accounts shown in that identity's list.
- **G GitHub accounts** on the main manager opens the shared connection library.
  Connect once, then choose the personal or company identity that uses the account.
  Repeat to link the same account to other identities. Companies are not inferred
  from email domains or GitHub usernames.

## GitHub connection

GitHub CLI (`gh`) must be installed on the native workstation. Choose a connection
already in the library, **Use an account already in GitHub CLI**, or **Connect
another GitHub account**. Existing native accounts are listed and individually
verified without switching GitHub CLI's active account. Ambient GH_TOKEN and
GITHUB_TOKEN overrides are not used to choose or verify the account.

For a new account, the TUI automatically copies the one-time device code to the
native clipboard, then opens GitHub's device page in your browser. Paste the code
and continue. It also displays the URL/code and reports when either automatic
action is unavailable. **O Open browser** and **C Copy code** retry those actions;
you can always use the displayed URL/code manually. Select the intended account in
your browser. The TUI receives the verified username and numeric account ID,
then lets you select an identity to link. It never asks you to type a username,
password, or token. B cancels browser sign-in and returns to the account library.

Each new connection uses a separate native `GH_CONFIG_DIR` under
`~/.config/workbenches/github-auth/github-<uuid>/`. GitHub CLI owns its credential
storage and may use a system keyring or its private configuration-file fallback.
This leaves the native default account/configuration and Git protocol selection
unchanged. GitHub tokens never enter `profiles.json`.

Connections display **Connected**, **Sign-in required**, or **Check failed**, with
a last-check time in details. These describe the last explicit verification,
not continuously monitored authentication. Use **C Check** or **R Sign in again**
in the account library, or open a linked account for those actions. Authorization
in a browser signed into a different GitHub account creates a separate connection;
existing links keep their original numeric account ID. Unlinking an identity
preserves other links and GitHub CLI credentials.

Defaults apply only to workBenches profile metadata. They do not change global
Git author identity or the active native GitHub CLI account. Per-project account
routing is not implemented by selecting a default.

Private bench installation uses working SSH access first, then HTTPS. For
GitHub HTTPS operations, setup keeps existing Git credential helpers and adds
the native `gh auth git-credential` helper as a command-local fallback. This
also works when Git runs in Tools and native gh uses the workstation keyring;
setup does not write global Git configuration or switch the active account.
An isolated Profiles connection is not automatically selected for Git operations.
If access fails, sign in to the native GitHub CLI with an authorized account
(`gh auth login --hostname github.com`), verify repository and organization SSO
access, then retry the install. Existing worktrees and credentials are preserved.

## Company sign-in and AI profiles

A company has multiple email identities and GitHub links, plus a separate scoped
company sign-in/session used for credential synchronization. Open the company for
**C Sign in**, **I Enrollment**, **S Sign out**, and **Y Sync**. Membership is
verified by the organization's sign-in service, never by the email domain alone.
A verified company login email can be added as another identity without replacing
other emails. Personal email is kept separate.

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
After successful company sign-in, setup offers to add the email confirmed as
verified by the sign-in server as a company identity. It does not
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

Use **B** to return from an identity, company, or manager. **Q** or Ctrl+C cancels the action;
completed steps remain saved and the TUI preserves queued component selections.
Existing v1.5 workstation account files remain available through **Workstation account** (L in the manager);
they are not automatically assigned to a company or migrated.

Metadata lives in `~/.config/workbenches/profiles.json`; company account files live
under `~/.config/workbenches/identities/<company-id>/`. `XDG_CONFIG_HOME` overrides
the configuration root. Metadata and sessions use private atomic writes. Tokens
are not stored in profiles.json. Company Keycloak sessions remain in the existing
account helper's private session format.

Project-to-profile selection and automatic per-project account routing are not
implemented in this increment. Profiles do not modify global Git author identity.

## Storage migration

Profile metadata now uses schema version 2: personal/company scopes contain lists
of named email identities; GitHub connections are stored once and linked by
numeric account ID. Each scope has a default identity, and each identity can
have a default GitHub connection. Existing company IDs, account roots, enrollment
settings, broker configuration, and sessions are preserved.

Opening the interactive manager migrates version 1 metadata atomically and keeps
an owner-only `profiles.v1.json` backup on its first write. Summary reads do not
write or migrate the file on disk. Migrated GitHub links are kept but show
Sign-in required until checked against the native GitHub CLI. The old code should
not be used to edit the new version-2 metadata. Piped/nonterminal use retains a
line-oriented fallback; the normal setup flow uses the terminal manager.
