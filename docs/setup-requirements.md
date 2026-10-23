# Workstation requirements and optional accounts

On the v1.6 `feature/profile-onboarding` branch, account entry points move to the
third **Profiles** page (**G**). Requirements keeps Docker, Tools, and Vault service
controls. See [Profiles](profiles.md) for personal-first onboarding, multiple
companies, and compatibility with the legacy workstation account described below.

`./setup.sh` opens the interactive TUI before checking Docker or starting Tools.
Requirements and unverified components initially show yellow, blinking
**Loading…** indicators. Read-only checks run in the background and update each
item as it becomes known. P opens Requirements and Q exits while checks run.
No JSON helper or container check runs as part of drawing the first frame.
Updates replace only changed lines; the header and unchanged rows stay in place.
The screen is cleared once on entry, after an interactive helper returns, or
when its width changes, rather than on every status or keyboard update.

Docker/WSL checks and automatic Tools startup happen behind this screen. Missing
requirements open the Requirements page after the initial check; Enter or Space
activates the indicated Install/Start action. Background work never asks for a
password or logs into an account. Privileged installation/configuration and
account sign-in happen only through explicit foreground actions.

Unknown items cannot be selected, and Apply waits for required checks to finish.
Refresh preserves queued changes and focus. Canceling the TUI stops its pending
checks and removes the private status snapshot; existing services stay running.
Piped/noninteractive runs retain the synchronous prerequisite checks.

Required:

- Docker installed, with an accessible daemon using Linux containers.
- On Windows, setup running inside a WSL 2 Linux distribution.
- A healthy **Tools** container, started automatically after Docker is available.
  Python 3, jq, Git, and curl run there; setup does not install them on the host.
  The host needs Bash and its normal OS utilities in addition to Docker.

On native Windows (for example Git Bash), setup offers WSL/Ubuntu installation
through an elevated Windows dialog. Finish any requested restart, open Ubuntu,
create the Linux user, and rerun setup there. For a WSL 1 distribution, the requirements screen shows the conversion command;
reopen the distribution after conversion.
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
The status strip shows **Docker**, **Tools**, and optional **Vault** as **Up**,
**Down**, or **Missing**. Up means the daemon/container is accessible and healthy.
Down means stopped, unhealthy, inaccessible, or blocked by Docker. Missing means
no installation/container exists. Vault Up does not mean signed in or unlocked. The page groups required
software separately from optional accounts and shows help for the focused row.
Press P again to return to the previous component, keeping your selections.
The main status strip also shows Vault’s current action: **[V Install]**,
**[V Start]**, **[V Connect]**, or **[V Sign out]**. Press V from any section
to activate it without leaving the current selection. This action remains
visible when the status strip wraps on a narrow terminal.

Service buttons follow the current state:

| Service | Missing | Down | Up |
|---|---|---|---|
| Docker | Install | Start | Check |
| Tools | Install | Start | Check |
| Vault | Install | Start | Connect, or Sign out when signed in |

Focus a service and press Enter or Space to activate its button immediately.
This does not apply queued bench/tool changes. Install/Start resolves required
Docker/Tools dependencies before starting Vault. Selecting Docker Install or
Start already approves that action, so setup does not ask the same question
again; local sudo/password and access-configuration prompts still apply.
Q cancels prerequisite setup.
Connect opens the configured Keycloak browser approval page, prefilling the
device code when supported. The URL/code remain visible for a headless machine.
Canceling Connect returns to the TUI with queued changes preserved. Signed in
reflects the account session, separately from Vault container health. Sign out
removes the local workBenches session; it does not sign out the browser's Microsoft
account. Keycloak must be federated with the organization Microsoft tenant to
provide Microsoft sign-in. Provider-vault authorization remains separate.

It includes three optional entries:

- **Vault**: the credential-access container for Azure Key Vault, Bitwarden
  (including Vaultwarden servers), and 1Password. Space creates/starts it now;
  recovery also starts it when needed. It is not a vault server.

- **workBenches account**: Keycloak browser sign-in or registration when the
  organization's realm allows it. An account is not required to install benches.
- **AI accounts**: existing profile setup, direct provider sign-in, or credential
  recovery from a supported vault; this can be configured later.

The separate account/profile entries retain their selection checkboxes for
application with Enter. Enter on a service row activates its service button. D cannot
remove required software or account/credential settings. R refreshes readiness
without losing selected component changes. Installation and removal through
`setup.sh` require Docker; standalone removal helpers retain their own checks.

## Managed containers

The Tools image is `workbenches/tools:2026.10.15-v1`; the persistent container is
`workbenches-tools`. Docker resource names use lowercase and container names
cannot contain `/`. Vault uses `workbenches/vault:2026.10.15-v1` and
`workbenches-vault`. Images build locally on first use; the Azure/Bitwarden/
1Password image takes longer and is optional. Existing stopped helpers are
started, and owned outdated helpers are recreated without deleting user data.
Foreign containers with these names are preserved and reported Down.

The four command shims live under `~/.cache/workbenches/tools/bin` (or
`XDG_CACHE_HOME`). Their PATH applies only to setup and its children; shell
profiles and host packages are unchanged. Tools uses the current user identity,
home, checkout, temporary directory, SSH agent when present, and selected local
Docker socket. Native application probes/package actions use a private host
callback, so the TUI continues to report workstation applications accurately.
Bench setup scripts also run on the workstation, preserving native WSL, GPU,
and desktop path checks while using the four container command shims.
Sudo password entry stays on the host terminal.

Vault has a read-only root, a temporary in-memory session directory, and only a
private recovery-jobs bind mount. It has no Docker socket or host-home mount.
Each recovery owns and removes its login cache; validated missing credentials
are written to the selected local profile. Azure device approval, vault unlock,
and the organization's access permissions still apply. Existing credentials
are preserved. No vault master password is stored for future setup runs.

To inspect or start helpers outside the TUI:

```bash
bash scripts/manage-setup-services.sh status tools
bash scripts/manage-setup-services.sh start tools
bash scripts/manage-setup-services.sh status vault
bash scripts/manage-setup-services.sh start vault
```

The selected Docker engine must be local and run Linux containers. Helper builds
use host networking; helper containers use a dedicated bridge with MTU 1280 to
avoid the TLS stalls observed on Raven's default bridge. These do not change the
Docker daemon configuration. `WORKBENCHES_TOOLS_BUILD_NETWORK` and
`WORKBENCHES_SERVICES_MTU` override those settings. Container/image/network names
can also be overridden with `WORKBENCHES_TOOLS_*`, `WORKBENCHES_VAULT_*`, and
`WORKBENCHES_SERVICES_NETWORK` for separate installations.

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

Connect opens the verification page in the browser and prefills the device
code when the server supports it. A headless user opens the displayed URL and
enters the code manually. The user signs in and approves. Passwords and MFA stay in the browser. Ctrl+C cancels
the pending approval. The CLI confirms identity with the realm's userinfo
endpoint and stores its short-lived access token and session metadata in a
private (0600) `account-session.json`. Expired sessions offer **Connect**;
this initial version does not persist refresh tokens or renew sessions.

Account login and vault recovery are separate. Login alone does not grant
tenant membership, vault access, vendor tokens, or AI subscriptions. Credential
recovery continues to use the selected vault's authentication and permissions;
the shared credential broker described in `keycloak-credential-broker.md` remains
a separate service design.
