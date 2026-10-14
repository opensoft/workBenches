# Workstation requirements and optional accounts

`./setup.sh` identifies the OS in its title and verifies workstation requirements
before showing component selection. Missing requirements open a guided screen:
Enter configures, R rechecks, and Q cancels without starting installation.
Existing requirements do not trigger an installation or account prompt.

Required:

- Docker installed, with an accessible daemon using Linux containers.
- On Windows, setup running inside a WSL 2 Linux distribution.
- Python 3, jq, Git, and curl for the setup manager. Missing tools are offered
  through the existing OS package installer before opening the TUI.

On native Windows (for example Git Bash), setup offers WSL/Ubuntu installation
through an elevated Windows dialog. Finish any requested restart, open Ubuntu,
create the Linux user, and rerun setup there. A WSL 1 distribution can be
converted using the requirements screen; reopen it after conversion.
See [Microsoft's WSL installation guide](https://learn.microsoft.com/en-us/windows/wsl/install).

Inside WSL, a missing Docker installation offers Docker Desktop through WinGet.
Start Docker Desktop, use Linux containers and its WSL 2 backend, and enable
the current distribution in Settings → Resources → WSL Integration. Recheck
readiness after changing settings. See [Docker's WSL integration guide](https://docs.docker.com/desktop/features/wsl/use-wsl/).
Linux setup can offer to start an installed local Docker service or add the
current user to its Docker group. Group changes require signing out and back in;
Docker group membership grants administrator-equivalent machine access.
Remote and rootless context failures do not start the system Docker service.

The main TUI has a **Requirements** page: press P, or move right from Tools.
It shows required items and their current state, plus two optional entries:

- **workBenches account**: Keycloak browser sign-in or registration when the
  organization's realm allows it. An account is not required to install benches.
- **AI accounts**: existing profile setup, direct provider sign-in, or credential
  recovery from a supported vault; this can be configured later.

Space selects optional account configuration for application with Enter. D cannot
remove required software or account/credential settings. R refreshes readiness
without losing selected component changes. Installation and removal through
`setup.sh` require Docker; standalone removal helpers retain their own checks.

## Organization Keycloak configuration

The initial deployment is the OpenSoft tenant's QA subscription; production
Keycloak will be configured later. Keep deployment URLs in organization-provided
configuration. Changing the issuer/client ID invalidates the local signed-in
status and requires approval against the new deployment.

An administrator must provide a reachable HTTPS realm and a public client with
OAuth 2 device authorization enabled. Enable realm user registration if users
may create their own account, or provision their identities centrally.
The CLI does not create a Keycloak server, administrator account, or client.
See [Keycloak's device authorization documentation](https://www.keycloak.org/securing-apps/oidc-layers).

Copy `config/account-provider.example.json` to
`~/.config/workbenches/account-provider.json` (under `XDG_CONFIG_HOME` when set)
and replace the example issuer/client ID. An organization may also supply
`WORKBENCHES_ACCOUNT_ISSUER` and `WORKBENCHES_ACCOUNT_CLIENT_ID`. If settings are
missing, optional account setup asks for them; Enter skips configuration.

The user opens the displayed verification URL, enters the device code, signs in
or registers, and approves. Passwords and MFA stay in the browser. Ctrl+C cancels
the pending approval. The CLI confirms identity with the realm's userinfo
endpoint and stores its short-lived access token and session metadata in a
private (0600) `account-session.json`. Expired sessions show **sign in**;
this initial version does not persist refresh tokens or renew sessions.

Account login and vault recovery are separate. Login alone does not grant
tenant membership, vault access, vendor tokens, or AI subscriptions. Credential
recovery continues to use the selected vault's authentication and permissions;
the shared credential broker described in `keycloak-credential-broker.md` remains
a separate service design.
