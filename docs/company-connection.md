# Connect a company to openBenches

Company sign-in connects to an organization-controlled identity provider. It is
separate from GitHub, AI-provider login, broker authorization and vault access.
Current support is Keycloak-compatible HTTPS public-client device authorization
with same-origin device/token/userinfo endpoints; arbitrary OIDC provider support
is not implied.

## Employees: use company setup

Open Profiles → your company → **C Sign in**. If the company is unconfigured,
choose **Use company setup link or file**. Your administrator supplies the JSON
file or final HTTPS enrollment URL. Review the full issuer and registered Client
ID and confirm that these came from your administrator. Discovery checks issuer
and supported endpoints; it does not prove that the application is registered.
The subsequent existing browser/device sign-in confirms access. **R Connection
setup** reopens this wizard to repair settings without starting sign-in.
Passwords and MFA stay in the browser.

Application registration is normally done once per organization. Employees do
not each register another client. Already-configured companies go directly to
their current sign-in flow. **I Enrollment** remains an explicit review/import
action without automatically starting sign-in.

## Administrators: register the application

Choose **Administrator — register openBenches with my provider**, enter the
realm's HTTPS issuer, and open **View full registration checklist**. Explicit
actions can open the provider's administration console or copy the instructions;
manual instructions remain available if the native browser/clipboard is absent.
The wizard does not create clients or request administrator credentials.

For the existing Keycloak device-flow implementation:

| Setting | Value |
| --- | --- |
| Application/display name | openBenches |
| Protocol/type | OpenID Connect public client |
| Client authentication | Off; no client secret in the CLI |
| OAuth 2.0 Device Authorization Grant | On |
| Password/direct grant and implicit flow | Not required; do not enable for this CLI |
| Requested scopes | openid profile email |
| offline_access | Only for explicitly opted-in company synchronization |
| Website callback URI | Not used by this device flow |

Client ID identifies this application registration at this provider, not your
user ID, email or company ID. Keycloak allows an administrator-chosen ID; other
providers can generate it. `openworkbenches-cli` is an example, not an application
automatically registered everywhere. Enter the actual registered value.

The issuer is the realm URL, for example `https://identity.example.org/realms/company`,
not the administration console or an interactive login page. The guide derives
an administration link only for a validated Keycloak-style realm URL. Supported
endpoint discovery must pass before settings are saved in the connection wizard.
Client registration remains unverified until device authorization succeeds.

## Reuse and safety

Before saving, **Export non-secret company enrollment file** can write a new
private JSON descriptor. It contains only issuer/clientId and optional
organizationId/credentialBrokerUrl; no session, token, password or client secret.
Exports refuse existing or symlinked destinations. Share this administrator
configuration through your normal trusted company channel; export is not an
authentication or authorization result.

Imports are size-bounded and refuse redirects, unsupported fields and malformed
URLs. The explicit Enrollment action reviews settings offline; actual sign-in
still performs discovery/device validation. Back/Q/cancellation preserve saved
identities and other companies' sessions. Decline or failed validation leaves
the previous configuration untouched. Configuring the company does not publish
AI credentials or grant access to a broker/vault.

References: [OIDC registration](https://openid.net/specs/openid-connect-registration-1_0.html),
[device authorization](https://www.rfc-editor.org/rfc/rfc8628.html).
