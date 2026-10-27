# Import AI profile sources

The [hierarchical Profile menu](profile-navigation.md) separates Personal,
Company and local Workstation profiles. Personal/company editors open AI
profiles → model maker → accounts; Import / manage sources opens this importer.
Portable profile-information imports/exports are separate editor actions.

v1.6.2 development integrates feature 160's pinned Tools Rclone connector with
feature 161's shared personal/company source pane. No Keycloak server is required
for imports. From Profiles, open Personal, a company or an email identity and
select **AI profiles** (or press **F**).

Choose a local file, enter a path/public HTTPS URL, select a GitHub repository,
or connect/browse Google Drive or OneDrive. Review the actual resulting names,
emails, selected providers and collisions. Enter toggles a profile/provider;
**I Import selected** confirms. B returns and Q cancels. **Add one AI account
manually** uses the same scope, review and launcher configuration without a
registry or a second ownership questionnaire. Existing default logins do not
suppress the ownership/source choice during interactive account setup.

The pane uses the existing keyboard-driven 1.6.x profile layout with stacked
narrow-terminal details. Import merges metadata and configures local launchers;
it does not authenticate a provider or apply queued software selections.
**Recover Claude/Codex credentials** is a separate, scoped action.

## Native file picker and URL rules

On a local Linux desktop, use an installed Zenity or KDialog picker. macOS uses
AppleScript's native chooser. Windows hosts reached through WSL use a Windows
OpenFileDialog via PowerShell, then translate the selected path for WSL. The
adapter also handles Git Bash path conversion, but this is not a claim that the
whole setup supports native Windows/Git Bash execution. Tools calls the host
picker/read action; it never browses only the container filesystem.

Manual local paths are always available. No desktop packages are installed
implicitly; unavailable dialogs explain the fallback. SSH/headless sessions use
manual entry. Cancelling a dialog or field does not replace the saved source.
Native adapter branches have fixture tests; attended Linux/macOS/Windows dialog
qualification remains required before release.

HTTPS files must be final, public JSON URLs without redirects, URL credentials,
query tokens or fragments. Use a linked GitHub connection for private repository
files, or the cloud drive connector for private Drive/OneDrive files. Pasting a Drive/OneDrive sharing link offers the connected-drive browser instead
of resolving the URL or requesting a password/pasted token. Select the file
inside that drive; the sharing URL and query tokens are not saved.

## GitHub company catalogs

Select a verified GitHub connection, repository, manifest path (default
`ai/source.json`) and branch/tag/commit (default `HEAD`). Every read uses that
account's isolated native gh configuration/token; no ambient-account fallback
or global account switch occurs. The helper resolves one commit and reads both
catalog and grant file at that commit. A tenant registry requires
`ai/grants/users/<verified-login>.json`; missing grants or denied repository
access preserve the previous local set. Personal registry ownership must match
the verified account. GitHub access does not grant Key Vault/provider access.

Known account metadata such as owner, plan, status and authentication account ID
is validated before projection into local launcher manifests. Disabled/retired
entries are excluded, planned entries are not selected by default. The review
reports unsupported harness categories (currently OmniRoute) without importing
them as another provider. This importer supports Claude, Codex, Gemini, Grok and
GLM; other harnesses retain their separate credential workflows.

## File contract and repeat pulls

Import an existing version 1 provider launcher manifest:

```json
{
  "version": 1,
  "profiles": [
    {"name": "my-account", "email": "user@example.org", "family": "personal"}
  ]
}
```

A portable, administrator-approved multi-provider file can use
`{"version":1,"kind":"workbenches-ai-profile-bundle","profiles":{"claude":[...],"openai":[...]}}`.
A tenant registry with external grants must use the GitHub route; a local bundle
is reviewed metadata, not proof of grants or company membership.

Choose Claude, Codex, Gemini, Grok or GLM for single-provider files. The selected scope
determines local ownership and paths; remote paths/families do not redirect
credentials to another scope. Credentials and unknown fields are refused.
Existing matching profiles are kept, other-account naming collisions receive a
suffix shown before confirmation, and unrelated manifests remain unchanged.
Reservations include case-insensitive names/aliases and existing scoped/legacy
credential homes. Downloads are limited to 1 MiB; composed local metadata has an
8 MiB limit enforced before replacement, so a larger merged file remains readable.
Reruns add missing profiles; they do not delete accounts removed from the source
or overwrite the metadata of matching existing profiles.

Sources and private Rclone authorization are retained under
`~/.config/workbenches/manifest-sources/<scope-id>/` (XDG_CONFIG_HOME supported).
The source record contains its path/provider/connection reference and checksum,
not OAuth tokens. Each connection has its own mode-0600 Rclone config inside a
mode-0700 directory. Rclone tokens are protected by filesystem permissions;
this is not a claim of keyring-backed encryption. They are never exported into
profile manifests. **Refresh** reuses the saved source and authorization,
subject to expiry/revocation and provider policy. Connect again if reapproval is
needed; old connections are preserved. A connection label is user-supplied and
is not a verified provider email or company-membership claim.

Cloud browsing supports connected-drive folders and relative paths such as
`profiles/claude-profiles.json`; **P Enter path** in the drive browser is available.
Arbitrary sharing-link resolution is not implemented. No remote publishing,
mirroring, peer service or implicit credential transfer is performed.

## Scoped credential recovery and collisions

Provider manifests remain at `~/.config/workbenches/{claude,openai}-profiles.json`
for launcher compatibility. Saved source metadata records scope, provider,
locator, linked connection, checksum, last successful import and profile counts.
GitHub sources also record the resolved commit. Local source metadata contains
no credential values, tokens or transient signed URLs.

Recovery mappings for this pane are private files under
`~/.config/workbenches/manifest-sources/<scope-id>/`. Existing global mappings
continue to work for the older unscoped recovery command. An explicit
`AI_CREDENTIAL_KV_MANIFEST` override remains supported. Selected scopes filter
all recovery destinations to their imported profiles; another company's files
are not restored by this action. Imported references prefill editable Azure
vault/secret defaults, while tenant/subscription and ownership tags still need
review and Azure authorization.

A local collision suffix must not change the original vault identity. Azure
restore mappings may carry `vaultProfile` for the canonical tagged account while
`profile` and `credentialPath` identify the local launcher/home. Secret name,
company/provider/canonical profile tags and provider format are still checked.
This alias mapping supports restore only; backup/verify with different local and
vault profile names is refused. Existing credentials are not replaced unless
explicitly requested through the recovery command. Review whether production
provider sessions are eligible for the intended usage; file presence is not live
provider qualification.

## Browser login and OAuth applications

The temporary login container uses the same Tools image. It mounts only the
new connection directory and active private native-callback session. Its root
is read-only and its OAuth callback is published only at host loopback port
53682, only for the login lifetime. The relay forwards to Rclone's own loopback
listener inside the container. The workstation browser performs provider login;
no password, pasted token, service account or browser-cookie scraping is used.
If the browser cannot open automatically, use the displayed local authorization
URL. Cancel/timeout removes the login container and callback listener. A busy
callback port reports failure; it never takes over another listener.

Google's Rclone shared client ID is retiring during 2026, so configure a Google
OAuth desktop application before connecting. An administrator enables Drive API,
configures its consent screen/test users or required verification, and creates
desktop OAuth credentials. Store that app's client ID/secret locally in this
owner-only file, never in a repository, chat or source manifest:

`~/.config/workbenches/cloud-profile-apps.json`

```json
{
  "drive": {
    "client_id": "GOOGLE_DESKTOP_APP_CLIENT_ID",
    "client_secret": "GOOGLE_DESKTOP_APP_CLIENT_SECRET"
  }
}
```

Set the file to mode 0600. OneDrive can use Rclone's default delegated app when
tenant policy permits; an administrator may configure `onedrive` with the same
two app-setting keys. App configuration is distinct from the user's login.
The import requests Google `drive.readonly` or Microsoft `Files.Read` plus
`offline_access`; organization consent restrictions still apply. Other Microsoft
drives/SharePoint libraries may need separately reviewed permissions, not a
silent elevation. Source access is not vault permission or company membership.

Current verification uses disposable provider/native fixtures and actual Tools
transport/host-loopback relay tests. An attended real Google/Microsoft browser
consent and manifest pull remains required before claiming live qualification.

References: [Google Drive](https://rclone.org/drive/),
[OneDrive](https://rclone.org/onedrive/),
[configuration protocol](https://rclone.org/commands/rclone_config_create/).

## Implementation evidence

Feature 161 integrates PR #230's connector source (8810d24); it does not claim that
PR is merged or that v1.6.2 is published. Read-only GitHub qualification fetched
the Opensoft catalog and caller grants at commit
`5e5e3b7523981754b772bd5587f1457c33d0b0f5` and validated its active entries in
memory; no local manifests were applied and no vault values were accessed.
The declared Tools runtime Compose suite passed, including native profile-file
reads and cloud browser/callback fixtures. Live production cloud consent,
platform dialogs and attended vault/provider launch acceptance remain separate.

Native API references: [Apple file chooser](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/PromptforaFileorFolder.html),
[Zenity file selection](https://help.gnome.org/users/zenity/stable/file-selection.html.en).
