# Credential recovery during workstation setup

For the common requirements, per-option credentials, password-manager adapter
inventory and broader recovery roadmap, see
[Credentials for installation and recovery](setup-credential-requirements.md).
Preview selections with `python3 scripts/plan-setup-credentials.py --list`.

Setup needs an organization-approved recovery mapping before it can know which
identity authority and credential store to contact. Installing Azure CLI alone
cannot discover an organization's secret store or grant access to its secrets.

## Select credential stores during setup

Setup opens Workstation and checks Docker and the managed Python/jq/Git/curl
Tools environment in the background. Queue components on Benches, Agents and
Tools. Enter opens Review; only Enter on Review applies after required services
are ready. An empty Review finishes without changes. Node/npm are checked only
for selected npm-based tools.
AI CLI installation succeeds without account setup and reports authentication
pending when needed. Select **AI accounts** to configure profiles and choose
**sign in directly**, **recover from a vault**, or **configure later** after
installation. Existing profiles and credentials are preserved during repeat
installs, without opening a vault. Personal profiles need an account email;
GitHub identity is needed only for explicit registry enrollment.

Users can select several supported services:

| Service | Authentication and retrieval |
| --- | --- |
| Azure Key Vault | Tenant device-code sign-in; guided tenant/subscription/vault/secret mapping or existing approved mapping. |
| Bitwarden | Account email/master password and supported verification codes; advanced personal API-key login. Pick notes, login passwords, or custom credential fields by name. |
| Vaultwarden | Bitwarden adapter with the user's explicit HTTPS instance URL. |
| 1Password | Account address/email/Secret Key/password; advanced scoped service-account token. Pick a vault item and credential field. |

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

Stores reuse existing mappings automatically; stores without mappings start guided
setup. Append I to a service number to import advanced JSON, or A to use automation
login (for example, 2I or 4A). Missing destinations come from
the configured profiles for selected tools. Bitwarden/1Password authentication
and item selection happen inside the temporary container; only item titles,
IDs, and field labels are displayed. Confirm each item/profile association.
The host validates all returned destinations and payloads before installation,
then saves the mapping atomically with mode `0600`. Existing credential files
and mapping files are preserved. Skip individual profiles with S. Recovery runs only when AI accounts is selected, after component installation.
Each vault item/profile destination still requires explicit confirmation.

Advanced JSON import remains available. Default mapping paths are under
`~/.config/workbenches/`: `ai-credential-keyvault.json`,
`ai-credential-bitwarden.json`, `ai-credential-vaultwarden.json`, and
`ai-credential-1password.json`. `AI_CREDENTIAL_KV_MANIFEST` still overrides the
Azure path. Examples live at `config/ai-credential-*.example.json`; protect
imported mappings with `chmod 600`. Mappings contain metadata, never tokens.

Items normally contain complete credential JSON matching the selected harness.
For Codex and OmniRoute, guided recovery also accepts a raw API key and converts
it to the harness's auth JSON. Bitwarden supports notes, login passwords, and
uniquely named text/hidden custom fields; 1Password uses the chosen field. Only field labels are displayed. Stored
field locators are metadata, with no decrypted values in mappings. Profile
definitions come from onboarding, not arbitrary vault items.
Local credential presence is shown per profile; live provider access is not tested.

Bitwarden account sign-in supports authenticator, email, and YubiKey OTP methods;
new-device email verification is prompted when requested by the CLI. CLI-incompatible
SSO/trusted-device policies should use the organization's supported authentication
route or direct AI provider sign-in. 1Password manual sign-in still requires its
Secret Key and account password. Desktop-app integration and Connect are separate
from this container adapter. Automation credentials remain available for admins.
Native CLI prompts are relayed through known, hidden-input prompts; unsupported
prompts fail rather than displaying raw CLI output or hanging indefinitely.
See [Bitwarden CLI sign-in](https://bitwarden.com/help/cli/) and
[1Password manual sign-in](https://developer.1password.com/docs/cli/sign-in-manually/).

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

Guided Azure setup asks for tenant, subscription, vault, company ownership tag,
and exact secret names for approved profiles. Existing secrets must carry the
matching workBenches ownership tags; setup does not infer custody from email.
An administrator can instead supply an owner-only manifest at
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

For advanced Bitwarden mappings, `itemId` is the exact item UUID. `itemField`
selects `notes` (the backward-compatible default), `password`, or `custom`.
Custom fields also require `customField` with the exact, unique field name.
`credentialFormat` is `json` by default, or `api-key` for Codex/OmniRoute.
