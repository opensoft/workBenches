# Credential recovery during workstation setup

For the common requirements, per-option credentials, password-manager adapter
inventory and broader recovery roadmap, see
[Credentials for installation and recovery](setup-credential-requirements.md).
Preview selections with `python3 scripts/plan-setup-credentials.py --list`.

Setup needs an organization-approved recovery mapping before it can know which
identity authority and credential store to contact. Installing Azure CLI alone
cannot discover an organization's secret store or grant access to its secrets.

## Select credential stores during setup

After Docker verification and profile directory creation, interactive setup asks:
"Do you have AI assistant tokens or profile credentials stored in a vault?"
Users can select several supported services:

| Service | Implemented authentication and retrieval |
| --- | --- |
| Azure Key Vault | Entra tenant device-code sign-in; existing approved tenant/subscription/vault mapping. |
| Bitwarden | Personal API `client_id`/`client_secret`, followed by master-password unlock; fetch JSON from secure notes by exact item UUID. |
| Vaultwarden | Same Bitwarden CLI adapter with an explicit HTTPS instance URL; requires compatible personal API login/unlock support and organization policy. |
| 1Password | Service-account token scoped to the required vault; fetch JSON from an explicit `op://vault/item/field` reference. |

The selector lists only these implemented adapters. Other stores can use native
provider sign-in; the larger inventory is not a promise of installed support.
Q, Ctrl-C, or closed input cancels setup. Declining recovery or selecting none
continues with native provider sign-in. Authentication does not create AI keys
or bypass the vault's grants, MFA, account policies, or decryption requirements.

Run the selector separately with:

```bash
python3 scripts/setup-credential-recovery.py --interactive
python3 scripts/setup-credential-recovery.py --list
```

The selector asks for an owner-only mapping file for each selected store. Default
paths are under `~/.config/workbenches/`: `ai-credential-keyvault.json`,
`ai-credential-bitwarden.json`, `ai-credential-vaultwarden.json`, and
`ai-credential-1password.json`. The Azure override `AI_CREDENTIAL_KV_MANIFEST`
still works. Start from the corresponding `config/ai-credential-*.example.json`;
Vaultwarden uses the Bitwarden example with its own HTTPS server. Copy the chosen
example, edit its metadata/item references, and protect it with `chmod 600`.
No passwords or tokens belong in these mapping files.

Password-manager items must contain the complete credential JSON in the selected
secure note or field, matching the destination harness (Claude OAuth, Codex
OAuth/API-key auth JSON, Pi auth JSON, or OmniRoute API-key JSON). This increment
restores mapped credential files into local profiles; it does not import profile
definitions from a vault or convert arbitrary password items into auth files.
Organization/profile metadata continues to come from profile onboarding.

Bitwarden API credentials authenticate the user but do not unlock the vault;
the master password is required separately. Trusted-device-only Bitwarden
accounts cannot decrypt through the documented CLI. This adapter does not yet
implement email/password or SSO login. The 1Password adapter currently requires
an administrator/user-created service-account token; Connect and desktop sign-in
remain outside this adapter. These restrictions are shown in the service menu.
See [Bitwarden API-key authentication](https://bitwarden.com/help/personal-api-key/),
[Bitwarden unlock](https://bitwarden.com/help/cli/), and
[1Password service accounts](https://developer.1password.com/docs/service-accounts/use-with-1password-cli/).

## Temporary credential containers

Interactive setup recovery requires a reachable **local Unix-socket Docker context** before
contacting a vault. Remote contexts are rejected. It uses the official Azure CLI
image for Azure, and builds only the selected password-manager image from
`credential-container/Dockerfile`. Tools use public downloads, so building does
not require the registry credentials being recovered. Bitwarden CLI `2026.9.1`
and 1Password CLI `2.40.0` are pinned. Images are cached; runtime containers and
staging directories are temporary. The Bitwarden image includes Node and is
larger than the 1Password image; no single image bundles all candidate tools.

Password-manager containers run with `--rm`, the host UID/GID, a read-only root,
dropped capabilities, no-new-privileges, and a bounded tmpfs for login caches.
Only the selected mapping (read-only) and a private output directory are mounted.
Passwords and bootstrap tokens are entered without echo inside the container;
they are not Docker environment arguments, build inputs, or setup logs. CLI
payloads and errors are captured rather than relayed into logs. Neither the host
home, Docker socket, nor destination profile directories are mounted.

The host validates owner-only mappings, exact sources, profile names and approved
destinations before fetching. It validates the entire recovered batch's bounded
JSON payloads before installing anything, rejects symlinks/unsafe ancestors,
and creates owner-only files atomically. Existing credentials are preserved,
including credentials created while recovery runs. Containers only stage files;
the host performs installation. Session/staging data is removed on completion,
failure, or cancellation. Restored OAuth sessions can still require renewal;
successful restoration does not verify a live AI subscription or spend credits.

Standalone password-manager restore:

```bash
python3 scripts/recover-vault-credentials.py --service bitwarden --manifest ~/.config/workbenches/ai-credential-bitwarden.json
python3 scripts/recover-vault-credentials.py --service 1password --manifest ~/.config/workbenches/ai-credential-1password.json
```

Validate the public tool images through the declared test bench:

```bash
docker compose -f devcontainer.test/docker-compose.yml --profile credential-recovery build credential-bitwarden credential-1password
docker compose -f devcontainer.test/docker-compose.yml --profile credential-recovery run --rm --no-deps credential-bitwarden
docker compose -f devcontainer.test/docker-compose.yml --profile credential-recovery run --rm --no-deps credential-1password
```

## Azure recovery

`setup.sh` verifies Docker installation and daemon access before host setup,
AI profile onboarding or recovery. Missing Docker offers an interactive install,
including Arch/Omarchy. The user enters any local password directly into sudo.
Declining or cancelling stops setup, and failed daemon access must be resolved
before setup continues. Standalone escrow commands retain the runtime selection
below, including native Azure CLI operation without Docker.

An administrator supplies an owner-only manifest at
`~/.config/workbenches/ai-credential-keyvault.json`, or the operator selects a
manifest with `AI_CREDENTIAL_KV_MANIFEST`. Start from
`config/ai-credential-keyvault.example.json` and set the organization's tenant,
subscription, vault, and approved provider/profile secret mappings. The manifest
contains metadata, never passwords or tokens. Protect it with mode `0600`.

`setup-ai-profiles.sh` creates the profile directories and offers the selector
before provider sign-in. Noninteractive setup retains recovery from an existing
Azure manifest with automatic CLI runtime selection, preserving an existing
host Azure login; it does not prompt for password-manager authentication.
`WORKBENCHES_SKIP_CREDENTIAL_RECOVERY=1` skips this step.
OmniRoute bootstrap also supports the runtime fallback when
its authorized registry mapping is available.

Interactive setup explicitly selects the Docker runtime even if host `az`
exists. Unattended setup and the standalone escrow command retain automatic
runtime selection in this order:

1. Existing host `az`, including a previously installed workBenches user-local CLI.
2. A temporary container from the official Microsoft Azure CLI image when the
   Docker daemon is reachable.
3. With an interactive operator's agreement, a user-local Python virtual
   environment if neither host CLI nor Docker is available.

The user-local installer is `bash scripts/setup-azure-cli.sh`. It requires
Python 3.10+ and working `venv`/pip support, installs Microsoft's `azure-cli`
package, and leaves system Python and shell configuration untouched. The
installer and container default to CLI version `2.91.0`. Organizations can set
`WORKBENCHES_AZURE_CLI_IMAGE` to an approved image tag or digest.

Container commands run as the host user's UID/GID and mount only the private
temporary work directory. That directory holds snapshots, downloads, and a
temporary Azure login cache shared between commands in one recovery operation.
The host home and Docker socket are never mounted. Containers use `--rm`;
the operation removes its temporary directory and login cache on exit. The
downloaded container image remains cached by Docker.

`restore --azure-login` signs in to the exact manifest tenant using device-code
authentication when the selected subscription is not available in the current
session. It suppresses the account result and shows browser sign-in instructions
on stderr. Tenant policy may reject device-code authentication; recovery then
fails without modifying credential targets and setup retains provider login.
A different reported tenant is rejected rather than silently accepted.

The existing restore checks still validate subscription/tenant, vault, profile
ownership and paths, secret metadata, exact version, bounded payload shape,
and owner-only atomic installation. Recovery preserves existing credentials
unless the operator explicitly supplies `--force`. Local profile/grant metadata
helps select profiles; the remote store must enforce the user's actual access.

## Organization discovery and other providers

The next onboarding increment should accept an administrator-provided enrollment
URL or local organization descriptor, rather than infer an organization or
custody authority from an email domain. Validate and confirm the descriptor's
origin before using its endpoints. Keep identity and storage as separate fields:

```json
{
  "schemaVersion": 1,
  "organizationId": "example-org",
  "identity": {
    "issuer": "https://login.example.org/realms/example",
    "clientId": "workbenches-cli"
  },
  "credentialStore": {
    "provider": "credential-broker",
    "endpoint": "https://credentials.example.org"
  }
}
```

This is a proposed descriptor, not an implemented configuration format. Provider
adapters should support `discover`, `authenticate`, `list-authorized-profiles`,
and `restore`. Azure Key Vault should retain its existing manifest contract.
The implemented password-manager adapters use their explicit mapping contracts
above without Azure tooling. Additional adapters can target an organization
vault or encrypted personal recovery store. Unsupported providers retain native
provider login.

## Keycloak and organization authorization

Keycloak can provide organization membership, browser sign-in, MFA, and identity
brokering to an organization's existing identity provider. An organization-hosted
credential service should validate the issued token's issuer, signature,
audience, expiry, organization membership, and per-profile permission before
retrieving a secret. Authentication alone does not authorize every secret in an
organization. A Keycloak token also does not automatically grant Azure Key Vault
access; the credential service needs its own narrowly authorized backend identity.

Store AI provider credentials in a dedicated secrets backend behind that service,
not in ordinary Keycloak user attributes. Keep organization and personal stores
independent. A hosted offering would require administrator enrollment, explicit
member grants, isolation between organizations, audit events without payloads,
revocation/offboarding, and an agreed recovery/retention policy. Installing a
workstation must not create an organization credential store automatically.

References: [official Azure CLI container](https://learn.microsoft.com/en-us/cli/azure/run-azure-cli-docker),
[tenant and device-code sign-in](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively),
[Microsoft Azure CLI package](https://pypi.org/project/azure-cli/),
[Keycloak organization and identity administration](https://www.keycloak.org/docs/latest/server_admin/).
