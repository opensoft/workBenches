# Personal/company manifest sources and remembered browser connections

Authority: Brett Heap, 2026-10-25. For v1.6.2, workstation access means the
local workstation only. Personal and company profiles may import manifests from
files or GitHub repositories, with browser-only authentication for private remote
sources. Workstation-to-workstation communication moves to v1.8 through a service
shipped with workBenches. Feature 161 implements the bounded local/source UI on top of feature 160; live provider qualification and the limits recorded in docs/cloud-profile-import.md remain explicit.

File sources include local JSON and hosted file links, including the OneDrive
and Google Drive examples in the preceding discussion. Local files use OS access;
private remote files require the source provider's browser authorization.

Preserve each source's personal/company association, stable source locator and
verified connection reference so a later visit can check access and re-import
updates. Retain provider sessions in supported protected local storage; never
store passwords/tokens in manifests, source URLs or exported identity metadata.
Company Keycloak login is separate from authorization to GitHub/Drive or a vault.

The existing GitHub account library is a building block. Its isolated connection
must actually be used for repository reads; ambient native GitHub login is not
equivalent. Microsoft/Google file authorization and retrieval need new adapters.
Do not make Keycloak or a network service a prerequisite for local imports.

This scope extends company-set import tracked by #227. Implementation is tracked in `specs/161-profile-source-tui/`; its tasks.md owns the
only executable checklist for this increment. Do not reopen completed feature 033 wizard tasks or
claim provider qualification from those tests. No release publication is implied.

Implementation authorization on 2026-10-25: add Rclone to Tools for connection
and profile-file pulls. Bounded implementation owner:
`specs/160-rclone-manifest-import/`; its tasks.md is the sole executable checklist
for this connector. It does not deliver all future source providers/link formats.

Clarification pending: whether "update it" includes editing/publishing the remote
manifest, in addition to re-importing source changes. Remote write permissions
and publishing remain undesigned until answered; read/import requirements below
are independent of that decision.
