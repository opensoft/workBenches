# Workstation requirements and optional accounts

`./setup.sh` opens on **Workstation**, the first step of the guided wizard,
before checking Docker or connecting to installed Tools. The requirements strip appears on
Workstation only; the navigation readiness mark remains visible on every step.
It blinks while checks run, shows `✓` when all required items are Up and `⚠`
when one needs attention. Optional Vault does not count toward readiness.

Read-only checks update the cached state in the background. Unknown components
show blinking Loading indicators and cannot be selected. Drawing the first
frame runs no JSON helper or container check, and later redraws update only
changed lines. A helper return or a terminal width/height change repaints.

After each check run, an unresolved requirement takes setup to Workstation and
focuses the first item needing attention. **P** returns to the previous step
and exact focus. From another step P visits Workstation; P again returns.
**R** refreshes without losing queued changes. **Q** cancels without applying,
stops pending checks and removes the private status snapshot. Existing services
stay running. Piped/noninteractive runs retain synchronous prerequisite checks.

Background work never installs or starts a missing/stopped Tools container.
Space selects install/start and D selects uninstall; Enter opens Review and only
Review Apply runs the plan. Selected prerequisites install before other work;
removals run last after successful work. V remains the explicit Vault account
shortcut. Required readiness is retained for component work, with exceptions for
selected prerequisite installs and service-only removal plans.

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

Workstation lists WSL 2 when applicable, Docker, Tools and optional Vault in
one **Containers** panel. Its **About** panel explains the selected service
and its current check details; PgUp/PgDn or [/] pages long text. Vault remains
optional. Use **G Profiles** for account setup.
The Requirements count is followed by a blank line; all service information is
in Containers. Rows have left selection boxes and right statuses such as
**Installed · Up**, **Installed · Down**, or **Not installed**. Unreachable
managed services say Unavailable when their installation cannot be verified.
Vault Up describes container health, separately from account sign-in.

V runs Vault's account action; G Profiles opens account setup. Check buttons
are replaced by the same Space/D → Review → Apply selection pattern as Benches.
All entries, including Docker and WSL, can be selected. Managed removal retains
images, volumes, credentials and projects, and refuses foreign ownership. Native
Linux Docker Engine removal retains its data/config and avoids purge/autoremove.
Docker Desktop uninstall deletes data, so the wizard refuses automatic removal
and points to host backup/uninstall steps. WSL removal must happen outside the
running distribution; the wizard never unregisters, shuts down or restarts WSL.
These manual cases are reported as incomplete, never as successful removals.

Connect opens the configured Keycloak browser approval page, prefilling the
device code when supported. The URL/code remain visible for a headless machine.
Canceling Connect returns to the TUI with queued changes preserved. Signed in
reflects the account session, separately from Vault container health. Sign out
removes the local workBenches session; it does not sign out the browser's Microsoft
account. Keycloak must be federated with the organization Microsoft tenant to
provide Microsoft sign-in. Provider-vault authorization remains separate.

Vault is the optional credential-access container for Azure Key Vault,
Bitwarden (including Vaultwarden servers), and 1Password. It is not a vault server.
The **Personal & companies**, **Workstation account** and **AI accounts** rows
live on Profiles, not Workstation. They open their existing actions immediately,
are gated on workstation readiness and never queue account settings for Apply.

D cannot remove workstation services or account/credential settings. R refreshes
readiness without losing queued component changes. Installation and removal
through `setup.sh` require Docker; standalone removal helpers retain their checks.

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
