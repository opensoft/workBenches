# Credential recovery during workstation setup

Setup needs an organization-approved recovery mapping before it can know which
identity authority and credential store to contact. Installing Azure CLI alone
cannot discover an organization's secret store or grant access to its secrets.

## Current Azure recovery

An administrator supplies an owner-only manifest at
`~/.config/workbenches/ai-credential-keyvault.json`, or the operator selects a
manifest with `AI_CREDENTIAL_KV_MANIFEST`. Start from
`config/ai-credential-keyvault.example.json` and set the organization's tenant,
subscription, vault, and approved provider/profile secret mappings. The manifest
contains metadata, never passwords or tokens. Protect it with mode `0600`.

`setup-ai-profiles.sh` creates the profile directories and attempts recovery
from that manifest before provider sign-in. `WORKBENCHES_SKIP_CREDENTIAL_RECOVERY=1`
skips this step. OmniRoute bootstrap also supports the runtime fallback when
its authorized registry mapping is available.

The escrow command selects its runtime in this order:

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
Other adapters can target an organization vault or encrypted personal recovery
store without requiring Azure tooling. An unsupported provider should offer
manual provider login, rather than attempt an Azure sign-in.

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
