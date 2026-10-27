# Profiles in the v1.6.2 development wizard

Open G Profiles. The Profile panel contains Personal, Company and Workstation.
Its About panel follows only the highlighted choice. Enter opens that kind's
profile list; the last entry adds a new profile. Highlight an existing profile
to see its own About information; Enter opens its fields and actions. PgUp/PgDn
scrolls About without leaving the list. B returns one level; Q cancels the
current profile action and retains already saved changes.

Personal and Company editors include AI profiles. Open a model maker
(Anthropic, OpenAI, Google, xAI or Z.ai), then its accounts. Account lists include
scoped imports and an Add account action. Existing source selection and credential
recovery remain available through Import / manage sources. This UI does not add
support for other providers or authenticate an AI account by displaying it.

Workstation profiles are named configurations on this local computer. Opening
their list initially adds the local workstation and retains access to its legacy
workstation sign-in. Additional presets get their own metadata/sign-in root.
They do not enumerate machines over the Internet or Tailscale; that remains
v1.8 peer-service work. Workstation profiles do not offer AI account ownership.

## Profile URL/location and portable files

Every editor offers Profile URL / location, Import profile and Export profile.
Choose a local path, public final HTTPS JSON URL, a selected-account GitHub file,
or a file browsed through Google Drive/OneDrive. Drive sharing links offer the
browser connector rather than saving link tokens. GitHub export requires a
branch, not HEAD/a tag/a commit. Export refuses to replace an existing provider
manifest, tenant registry or unrelated document; select an empty JSON placeholder
or a matching portable-profile file instead.

The file contract is version 1, kind `openbenches-profile`, with `profile` and
`aiProfiles` objects. See `config/profile-portable.example.json`. Profile type
must match the selected Personal/Company/Workstation profile. The portable file
contains display information and model-maker account metadata; it cannot change
stable local IDs, credential homes, GitHub account links or company sign-in
settings. Workstation files have an empty `aiProfiles` object. Provider launcher
manifests/bundles still import through AI profiles, not Import profile.

Imports validate the whole file, review selected AI accounts, then confirm the
profile information. Failed launcher configuration restores previous profile
metadata and provider manifest bytes. Importing does not restore credentials;
that remains an explicit, scoped action. Existing account metadata is merged
using the source importer's existing collision/preservation behavior.

Export previews its destination and sends metadata only. Local files are private
and symlink destinations are refused. Ordinary HTTPS sources export to a chosen
local file. GitHub uses the saved verified account, explicit branch and reviewed
blob SHA; it can create a new JSON file or update one the account can write.
Branch protection and denied permissions are reported without changing local
profile data. No ambient GitHub account switch is used.

Drive export creates a new file or updates a file selected in the connected-drive
browser. Choose New profile file in a folder to name a new JSON destination.
A read-only connection first asks for explicit browser reconnection with write
permission and reselects the destination in that connection. Previous read-only
authorization is retained. Google requires an administrator OAuth application;
company policy may deny write access. No passwords or pasted tokens are accepted.
The upload checks reviewed content immediately before writing and reads it back
afterward. Rclone does not provide an atomic conditional write here: a concurrent
external edit can still race the check. GitHub's file SHA provides a stronger
conditional update. Creation uses Rclone's immutable flag to refuse replacement
of a file created concurrently at the new destination.

## Compatibility and acceptance

The existing version-2 profile store gains optional descriptions, source locators,
local-workstation records and personal AI scope markers. The legacy personal AI
family remains pinned to the identity that originally owned it, even if the
default email identity changes. Additional personal profiles receive independent
stable scopes. Existing company IDs, provider credential directories, sessions
and runtime roots are retained. Private browser connections are not exported.

Automated tests use disposable profiles and fake provider operations. Actual
browser consent, production GitHub/Drive publication and live credential restore
remain attended acceptance; fixture success is not a claim those occurred.

API references: [GitHub file updates](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents),
[Rclone single-file upload](https://rclone.org/commands/rclone_copyto/),
[Google Drive permissions](https://rclone.org/drive/#drive-scope).
