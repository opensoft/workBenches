# Credentials for workBenches installation and recovery

workBenches should install public software before asking for service credentials.
Then it should recover or obtain only the credentials needed by the user's
selected services and profiles. A Python or .NET bench can be installed without
an AI subscription, a cloud account, or a password manager login.

The requirements catalog and preview command are implemented. The shared
recovery container and non-Azure adapters below are a proposed next increment.
Current Azure recovery is described in [Credential recovery](credential-recovery.md).

## Common requirements

| Requirement | When needed | Credentials or information |
| --- | --- | --- |
| Local installation access | Install packages and build images | Docker client, reachable daemon, supported host; local sudo or OS approval if installing prerequisites. These are local permissions, not cloud credentials. |
| Git access | Public clone, private clone, publishing, workspace registry | No login for accessible public HTTPS repos. Private repositories need an authorized GitHub CLI session, scoped HTTPS token, or unlocked SSH key; organization SSO authorization where required. SSH access does not imply GitHub API access. |
| Private packages and images | Selected projects use private feeds or registries | Registry/feed URL, account and narrowly scoped pull/read credential; push/publish permission only when requested. |
| Organization and profile metadata | Work/personal profiles or recovery | Explicit organization ID, profile and account identity, trusted enrollment source, identity issuer/client ID, vault endpoint/region and item references. These identifiers are metadata, not secrets. |
| Recovery authentication | Recover an existing credential | One selected vault login/unlock, device/browser login or restricted service token; MFA when required. Obtain this outside the vault it unlocks to avoid a circular dependency. |
| Network access | Organization endpoints require VPN/proxy/private CA | VPN configuration or subscription, proxy authentication if required, trusted CA bundle. Establish this before contacting a private vault. |

There is no mandatory shared AI token. Common requirements are reusable categories;
their credentials remain specific to the account, organization, service and
permission. Docker itself normally needs no registry account to pull public
images; private registries and rate limits can make authentication necessary.

## Credentials for selectable options

All rows inherit the common conditional requirements above. Additional
credentials are for using the indicated feature, unless explicitly described
as local site initialization. Choose one supported authentication route; the
alternatives are not a shopping list of tokens to collect.

| TUI option | Additional credentials and metadata |
| --- | --- |
| `pyBench` | None for Python tooling. Private Python/package-index credentials, publishing token, database/service secrets and Sonar token only for projects using those services. |
| `javaBench` | None for Java tooling. Private Maven/Gradle repository credentials, signing key for publishing, Sonar token where enabled. |
| `dotNetBench` | None for .NET tooling. Private NuGet/Azure Artifacts credentials, signing certificate for publishing, Sonar token where enabled. |
| `cppBench` | None for compiler/CMake tooling. Private Conan/vcpkg/artifact credentials, signing material and Sonar token where enabled. |
| `flutterBench` | None for Flutter SDK tooling. Firebase/Google project login if used; Android keystore and unlock passwords for signed releases; Apple developer membership, signing certificate/profile and App Store Connect authorization for Apple distribution; Sonar token where enabled. Apple builds also need an appropriate Apple build host. |
| `frappeBench` | Local site provisioning needs database administrator access and a site Administrator password; generate new instance secrets for a new site. Existing sites need their own access. Private/custom apps, integrations, mail and Sonar require their respective credentials. Never reuse a demo default for an installed site. |
| `cloudBench` | Only selected clouds: Azure/Entra login plus tenant/subscription; AWS SSO/role session plus account/region; Google Cloud login/ADC plus project/location. Kubernetes needs authorized context and cluster login. Terraform/Pulumi remote state, Vault, Teleport and Infracost need access only when selected. Grant read access for inspection and additional write permissions for requested changes. |
| `gentecBench` | Proposed requirements: BaseSpace identity/API authorization and accessible project when using that service; private data storage access if used. Confirm against the actual bench before implementation. |
| `simBench` | Proposed requirements: none for local models and public data; token and accepted model license for gated downloads; credentials for optional hosted inference/private storage. Confirm against the actual bench before implementation. |
| `claude_cli` | Claude/Console browser login for an eligible account, **or** `ANTHROPIC_API_KEY`, **or** supported cloud/gateway authentication and deployment metadata. [Claude authentication](https://code.claude.com/docs/en/authentication). |
| `codex_cli` | ChatGPT browser/device login for an eligible account, **or** OpenAI API key and enabled project billing. Device login depends on account/workspace permission. Use each profile's own credential home. [Codex authentication](https://developers.openai.com/codex/auth). |
| `copilot_cli` | GitHub Copilot-authorized account and supported OAuth login, **or** supported token. A fine-grained personal token needs the **Copilot Requests** account permission; repository permissions are separate. Git SSH keys are insufficient. BYOK is a distinct provider route. [Copilot authentication](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli). |
| `antigravity_cli` | Google sign-in, **or** Gemini API key with the matching model-provider setting, **or** supported enterprise Google Cloud ADC configuration; appropriate account access and project metadata for the chosen route. [Antigravity authentication](https://antigravity.google/docs/cli/install). |
| `opencode_cli` | Auth for each chosen provider, including approved endpoint/model metadata. API key or supported OpenCode OAuth/plugin login; an OmniRoute deployment needs its own endpoint and credential. No credential interchange with Codex/Claude is implied. [OpenCode providers](https://opencode.ai/docs/providers/). |
| `pi_cli` | Per-provider API key or supported Pi `/login` OAuth session. Pi has its own auth state; recover only a payload approved for the same profile and harness. [Pi documentation](https://github.com/earendil-works/pi/tree/main/packages/coding-agent). |
| `spec_kit` | None to install. Git credentials only for private source; the agent selected to execute workflows needs its own credentials. |
| `openspec` | None to install. Selected AI agent credentials for AI workflows. |
| `vscode` | None for local editing. Optional Microsoft/GitHub login for sync, extension-specific logins, and remote-host access where used. |
| `warp` | Account login for AI/collaboration features; local terminal installation can proceed separately. |
| `wave` | None for terminal use. Provider-specific API key/endpoint for AI features, installed through Wave's secrets facility; SSH credentials only for remote connections. |
| `amnezia_vpn` | Client installation needs no VPN secret. Connecting needs an authorized imported client configuration/access key. Self-hosting a new server additionally needs server SSH access. |
| `0dcloud_vpn` | Client installation is separate from access. Connecting needs the user's provider account/subscription configuration or URL; treat subscription URLs as secrets. |

The twelve selectable TUI benches come from `config/bench-config.json`, including
`goBench`, `rustBench`, and `365Bench`. Go/Rust need no language-tool credentials; private
packages, publishing, signing and Sonar remain conditional. Microsoft 365 needs
tenant identity and the specific Graph/M365/Power Platform/Business Central
delegated permissions or application identity for the workload. Admin consent
and environment IDs may be needed; do not request a global administrator login
for ordinary bench installation.

The genetics and simulation URLs in the catalog did not yield public `main`
READMEs during this audit. Their inventory entries are provisional. Missing
repository access, branch names, or implementations must be resolved before
marking those benches ready to install.

## Additional AI tools installed in the base image

Installing these binaries does not require signing in to every service. Prompt
for credentials only when the user selects a tool/provider for use.

| Tool or profile | Additional access |
| --- | --- |
| Gemini / `pgemini` | Google login, Gemini API key, or Vertex/Google Cloud access with project and location. [Gemini authentication](https://geminicli.com/docs/get-started/authentication/). |
| Grok / `pgrok` | Grok login; device authentication is available for headless use. API-key/provider routes depend on the configured CLI/provider. [Grok CLI](https://docs.x.ai/build/cli/reference). |
| GLM / `pglm` / `chelper` | Z.AI key, correct Coding Plan/API endpoint and account entitlement. The coding helper configures other harnesses. [Z.AI](https://docs.z.ai/devpack/overview). |
| Kimi | Kimi Code device OAuth or Kimi Platform API key. [Kimi setup](https://moonshotai.github.io/kimi-code/en/guides/getting-started.html). |
| Qwen | Current Alibaba ModelStudio/Coding Plan or selected provider key, region, endpoint and model. Do not promise the discontinued Qwen OAuth route. [Qwen authentication](https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/). |
| Aider | Selected model provider key/cloud access, or a configured local model endpoint with no remote credential. [Aider providers](https://aider.chat/docs/llms.html). |
| OpenHands | Selected LLM credentials and endpoint/model; hosted services may additionally require their own login. [OpenHands setup](https://docs.openhands.dev/openhands/usage/cli/installation). |
| Amp | Amp account login or `AMP_API_KEY`. [Amp accounts](https://ampcode.com/docs/cli). |
| Cursor agent | Cursor browser login or `CURSOR_API_KEY`. [Cursor authentication](https://cursor.com/docs/cli/reference/authentication). |
| MiniMax / `mcode` / `mcode-tools` | MiniMax account login with matching region/credits, or configured BYOK provider credentials. Tools using the shared MCode login need that login too. [MiniMax Code](https://github.com/MiniMax-AI/minimax-code). |
| Letta | Selected provider API key/coding-plan access; separate Letta login for cloud backup/services when used. [Letta setup](https://docs.letta.com/quickstart). |
| NotebookLM / `notebooklm` / `nlm` | Google browser login and tool-specific session state. Existing setup uses browser automation; it needs a browser-capable host/runtime and does not imply an official Google recovery API. |
| `omo` | OpenCode provider configuration; no additional universal OMO token. |
| `herdr` | Workspace manager; underlying agents/remote workspaces need their own credentials. Installer checksum is metadata, not a secret. |
| Optional DeepSeek harness | Selected provider key and endpoint/model. Validate the installed preview version's configuration before adding automated recovery. |
| MCP servers | Separate OAuth grant or service API token **per server and profile**; local unauthenticated servers need none. Sharing definitions does not share grants. See [Shared MCP profiles](shared-mcp-profiles.md). |

## Password and identity service adapters

Azure, Bitwarden/Vaultwarden account sign-in or API-key login plus unlock, and
1Password account sign-in or service-account recovery are implemented in the
[setup vault selector](credential-recovery.md). The other integrations and
authentication routes below are candidates. An organization
selects its actual store and supplies a mapping from approved profile names to
item IDs/fields. Never discover credentials by exporting an entire vault.

The initial five open source password-manager integrations are **Bitwarden,
KeePassXC, Passbolt, pass, and Psono**. This is a coverage shortlist, not a market
ranking. Vaultwarden uses a Bitwarden-compatible adapter; KeePass databases are
covered by the KDBX adapter. Proton Pass is another open source candidate.

| Service | Tools and initial access | Container suitability and constraints |
| --- | --- | --- |
| Azure Key Vault | `az`; tenant/subscription/vault/item/version metadata; authorized Entra login | Already implemented with Docker fallback. Secret-read permission must be granted remotely. |
| Keycloak plus credential broker | OIDC client and HTTP/JWT libraries; issuer, public client ID, broker URL, approved group/profile grants | Browser PKCE or enabled device flow proves identity. Broker separately authorizes and retrieves secrets. No Keycloak administrator password or CLI client secret for a public workstation client. [Keycloak OIDC](https://www.keycloak.org/securing-apps/oidc-layers). |
| Bitwarden Password Manager | `bw`; server/region, user login plus master-password unlock and supported MFA, or API/SSO login followed by unlock | Implemented: account sign-in with supported verification codes, or advanced API-key login + unlock; guided secure-note selection or exact UUID mappings. SSO remains separate. API login alone cannot decrypt vault data; trusted-device-only members cannot decrypt with this CLI. [Bitwarden CLI](https://bitwarden.com/help/cli/). |
| Bitwarden Secrets Manager | `bws`; restricted machine-account access token and secret IDs | Separate product and access model from `bw`; suitable for org automation with an administrator-issued restricted token. [Secrets Manager CLI](https://bitwarden.com/help/secrets-manager-cli/). |
| Vaultwarden | `bw`; self-hosted endpoint and user vault login/unlock | Uses the implemented Bitwarden account/API-key adapter with an explicit HTTPS endpoint. Requires compatible server/account policy; do not assume Secrets Manager support. [Vaultwarden](https://github.com/dani-garcia/vaultwarden). |
| 1Password | `op`; scoped service-account token or Connect endpoint/token; alternatively sign-in address, email, Secret Key and account-password prompt | Implemented: manual account sign-in or service-account token in a temporary container; guided item/field selection or mapped references. Connect/desktop routes remain separate. [Remote authentication](https://developer.1password.com/docs/cli/sign-in-manually/), [service accounts](https://developer.1password.com/docs/service-accounts/use-with-1password-cli/). |
| LastPass | `lpass`; username, master-password prompt and supported MFA | Validate current CLI and organization SSO/MFA compatibility before enabling; retain native/manual login fallback. Do not enable plaintext-key or MFA-trust options. [LastPass CLI](https://lastpass.github.io/lastpass-cli/lpass.1.html). |
| KeePassXC / KeePass | `keepassxc-cli`; selected KDBX file, password/key file and any configured hardware challenge | CLI access suits containers when required unlock material is available. Hardware/desktop unlock should remain on the host. Copy/read only the chosen database and retrieve mapped entries. [KeePassXC CLI](https://github.com/keepassxreboot/keepassxc/blob/develop/docs/man/keepassxc-cli.1.adoc). |
| Passbolt | API client/OpenPGP; instance URL, user key identity, private-key unlock, allowed resource IDs | Authentication and decryption are separate; API responses can require local OpenPGP decryption. Validate JWT/GPG and MFA policy. [Passbolt API](https://www.passbolt.com/docs/api/). |
| pass | `pass`, GPG; selected encrypted store, authorized decrypting identity and unlock | Prefer host decryption with an already unlocked agent; avoid copying a user's entire keyring. Container path needs a scoped decrypting identity. [pass](https://www.passwordstore.org/). |
| Psono | `psonoci`; server URL, API key ID/secret and mapped secret IDs | Select least-privilege read/decryption mode; suitable for scoped automation. [Psono CLI](https://doc.psono.com/user/psonoci/usage.html). |
| Keeper | `ksm`; application/record grants and one-time enrollment token | Enrollment creates a client-device identity; keep its configuration private and revoke it when appropriate. [Keeper CLI](https://docs.keeper.io/keeperpam/secrets-manager/secrets-manager-command-line-interface). |
| Dashlane | `dcli`; user login, master password or supported SSO and device/MFA registration | Master-password route needs evaluation; SSO requires browser GUI and OS keychain, so use host-assisted login. Admin reporting keys do not imply vault-secret access. [Dashlane login](https://cli.dashlane.com/personal/authentication). |
| Proton Pass | `pass-cli`; authorized Proton login and vault/item/field references | Candidate CLI adapter; validate fresh-device/MFA and credential-store behavior in a headless runtime. [Proton Pass CLI](https://protonpass.github.io/pass-cli/). |
| NordPass, Enpass, RoboForm, OS wallets | Native application-assisted selection or secure local entry | Planned manual/host integration until a supported secret-retrieval API/CLI and account policy are validated; do not assume browser-cookie extraction. |
| OpenWallet | Depends on which product is intended | If this means OpenWallet Foundation, identify the concrete wallet/protocol first. Digital identity presentation can authenticate an org user; it does not supply arbitrary password-vault secrets. [OpenWallet Foundation](https://openwallet.foundation/2023/02/23/linux-foundation-europe-announces-formation-of-openwallet-foundation/). |
| SOPS registries / Vault / cloud secret stores | SOPS/age plus authorized registry access; Vault/cloud CLI or API and narrowly scoped store identity | Preserve existing SOPS custody; backend-specific authorization and decrypting identity are required. Add AWS Secrets Manager/GCP Secret Manager adapters when selected. |

## Proposed recovery container

The first increment uses the official Azure image and separate version-pinned
Bitwarden/1Password images, built only when selected. The supported menu,
authentication restrictions and runtime isolation are documented in
[Credential recovery](credential-recovery.md). The broader bundle described
below remains a roadmap.

Use a dedicated recovery image, separate from AI/development images. Its core
should contain CA certificates, Python, HTTP/OIDC clients, JSON tooling and the
validated adapters. Package the supported CLI tools as version-pinned modules:
Azure, AWS/GCP, Bitwarden, 1Password, LastPass, KDBX/GPG, Passbolt, Psono, Keeper,
Dashlane, Proton Pass, SOPS/age and Vault. Support a full image containing the
validated modules and smaller images containing only the selected modules.
Keep desktop-only and hardware-key flows as host integrations.
Make the recovery image available for anonymous pull or pre-provision it offline,
so obtaining it does not require the registry credential it is meant to recover.
Verify module versions, downloads, supported architectures and redistribution
terms; never place credentials in image builds or layers.

1. Read selections, then compute common plus additional requirements. Resolve
   dependencies: VPN/proxy before private org endpoints; public software before
   private registries; authorized recovery before profiles are marked ready.
2. Verify Docker CLI, daemon access, architecture and the chosen Docker context.
   Use a local daemon for recovery by default; remote contexts require an
   organization-approved handling policy for secrets. If unavailable, offer
   Docker installation, host tools or native provider login.
3. Obtain the trusted org descriptor or user-selected vault endpoint. Authenticate
   to that store with its native unlock or browser/device flow. Show the service,
   account and permissions the operator is authorizing.
4. Run the selected adapter with `--rm`, host UID/GID, read-only root filesystem,
   dropped capabilities, no-new-privileges and a private temporary session. Use
   tmpfs for container caches, a `0700` staging directory when output must reach
   the host, and only explicitly selected read-only inputs. Never mount the
   host home, Docker socket, whole SSH/GPG directories or browser profile.
5. Retrieve only mapped items granted to this user/profile. Validate issuer,
   audience, account/tenant, credential type, payload shape, destination and
   validity. A local metadata file cannot grant remote permissions.
6. Have a host-side installer write approved results atomically to the intended
   profile or native secret store. Preserve existing credentials by default.
   The recovery container should have no write access to arbitrary host files.
7. Validate access without spending AI credits or changing resources. Report
   `ready`, `login required`, `access denied`, `expired`, or `unsupported`, with
   account/permission hints and no credential values. Remove session caches on
   success, failure and cancellation. Q/Ctrl-C must stop without installing.

Docker CLI existence alone is insufficient: the daemon can be unavailable or
remote. A container also cannot bypass MFA, missing org grants, unavailable
decryption keys, or provider token policy.

## Native login and credential records

When recovery is unavailable, launch the selected provider's native browser or
device login. The user enters their login/MFA on the provider's page or into
the native vault tool's protected prompt. workBenches should ask for the
account/profile and authentication route, rather than collecting AI account
passwords itself. Creating a new API key is a separate provider-authorized
operation with scopes, billing and expiry; do not automatically mint keys for
every installed binary. Never treat a subscription session as a general API key.

Use metadata records containing owner/org, profile, provider/harness, issuer and
audience where applicable, auth type, permitted scopes, expiry, secret reference
and approved destination. Store secret values only in the selected native
credential home or secret service. Pass values through protected input/files,
not CLI arguments, setup logs, Git manifests or AI prompts. Keep personal and
organization credentials separate; never copy OAuth state between harnesses
without a validated provider-specific contract. Restored sessions may still
require renewal or device enrollment.

## Preview the selected requirements

```bash
python3 scripts/plan-setup-credentials.py --option dotNetBench --option codex_cli
python3 scripts/plan-setup-credentials.py --option cloudBench --option pi_cli --json
python3 scripts/plan-setup-credentials.py --list
```

The preview reads only `config/credential-requirements.json`. It never scans
the user's credential files, reads secret environment variables, contacts a
vault or authenticates. Conditional requirements remain conditional until the
user chooses a provider, feature and profile. The TUI is not yet wired to this
catalog. The separate vault selector lists only the implemented routes documented
in [Credential recovery](credential-recovery.md), not all candidates in this inventory.
