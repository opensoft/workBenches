# Import profile files with Tools Rclone

v1.6.2 development: Rclone 1.75.2 is pinned by upstream image digest in the
Tools image. No host Rclone installation or Keycloak server is required.
From Profiles, open Personal or a company/identity and press **F Manifest files**.
Choose a local JSON or connect Google Drive/OneDrive, then browse for the file.
Select its provider, review the actual resulting names/emails and confirm.
The import merges metadata and runs that provider's existing launcher setup.
It does not download AI credentials, start provider sessions or apply queued
software selections. Use existing vault recovery/provider login separately.

## File contract and repeat pulls

Import one existing provider launcher manifest at a time:

```json
{
  "version": 1,
  "profiles": [
    {"name": "my-account", "email": "user@example.org", "family": "personal"}
  ]
}
```

Choose Claude, Codex, Gemini, Grok or GLM in the import menu. The selected scope
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
profile manifests. **Pull again** reuses the saved source and authorization,
subject to expiry/revocation and provider policy. Connect again if reapproval is
needed; old connections are preserved. A connection label is user-supplied and
is not a verified provider email or company-membership claim.

Cloud browsing supports connected-drive folders and remote-relative paths such
as `profiles/claude-profiles.json`. Paste a path with **P Enter path**. Arbitrary
OneDrive/Google sharing-link resolution and registry `ai/source.json` bundles with
external grant files remain the wider manifest-source proposal's work. This
connector imports already-selected provider manifests, not an entire tenant
registry. GitHub remains the existing registry route; selected-account routing
is separately tracked. No remote publishing, mirroring or credential transfer
is performed. Peer-workstation communication remains targeted for v1.8.

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
