## Context
The approved tenant Smallstep plan introduces an access service and wallet signing adapter. workBenches distributes the client and discovery instructions, not CA keys or authority.
## Goals / Non-Goals
Goals: pinned isolated install, explicit environment, discoverable command, no credentials in images. No active container recreation or implicit agent enrollment.
## Decisions
Vendor the small wheel with its source provenance and complete dependency hash lock. Install in an isolated virtual environment using uv. Keep capability and operator environment configuration separate. The existing tenant code owns behavior; this repository owns distribution.
## Risks / Trade-offs
A local source/image change does not update a running bench. Endpoints and identity grants remain disabled until controlled enrollment. Source changes require a new wheel/checksum/provenance as one release unit.
