# Hierarchical profile navigation

Approved by Brett Heap, 2026-10-27, in the interactive wizard review. The
Profile pane contains exactly Personal, Company and Workstation. Lists and
editors use a list above an About panel, showing only the selected item's
information. Each list ends with its corresponding Add profile action.

Personal/company editors contain an AI profiles section: model maker, then
that maker's accounts belonging to the selected profile. Preserve stable IDs,
existing credential homes, company connections and GitHub account isolation.
Workstation profiles describe configurations on this local workstation; peer
access remains v1.8 scope. A workstation login is separate from its metadata.

Every profile has an editable name, description and saved file location/URL.
Portable files contain profile and AI-account metadata, never tokens or native
credential paths. Imports require review. Explicit exports upload using the
selected browser-connected GitHub/Drive account; ordinary HTTPS exports are
local files. GitHub updates use the reviewed blob SHA; Drive uploads re-read
content immediately before writing and cannot promise provider-level CAS.
Existing read-only Drive authorizations require explicit browser reconnection
with write permission. Never grant write permission silently.

Implementation and verification belong to `specs/162-profile-navigation/`.
This extends the unshipped 1.6.2 wizard, not a published release contract.
