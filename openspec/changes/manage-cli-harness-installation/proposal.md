# Managed CLI harness installation for 1.7

Brett requested planning, documentation and implementation of automatic
installation for all newly cataloged manual CLI harnesses on 2026-10-23. He
selected **workstation and selected bench containers** as the execution scope.
The reviewed wizard baseline has 71 manual terminal entries in addition to its
existing managed CLI actions. This change owns installer behavior, separately
from feature 031's planned credential work.

Extend the existing Space/D → Review → Apply workflow with a source-qualified
recipe for every terminal entry, install/update/remove dispatch, exact target
reporting and preservation of credentials/projects. Package/product identity,
platform support and runnable verification are separate from login. Ambiguous
or unavailable upstream distributions must be reported explicitly rather than
installing an unrelated similarly named package.

Use typed recipes and private, user-owned installation prefixes with installation
receipts, atomic promotion and safe rollback/removal. Keep existing Claude/Codex
actions and GUI/editor/extension rows unchanged. Do not run models, sign in,
install every tool by default or grant new credential privileges.

Selected benches are install/update selections in the current reviewed plan.
Apply to matching running containers without restarting active sessions. Persist
their desired harness list and include it in personalized image builds, so stopped
or recreated benches receive the same requested tools. Report live-container
application, image preparation and pending restart separately; never claim an
unavailable target was installed. No selection means workstation only.

New capability: managed-cli-harnesses. Changes affect catalog compilation,
selection allowlists, dependency planning, installer/status/removal dispatch,
bench personalization/fingerprints and lifecycle acceptance. The selection JSON
shape stays compatible; the validated component-key allowlist expands only for
source-qualified terminal products. No source pins or release tags are changed.

One Speckit feature owns implementation:
`specs/032-managed-cli-harnesses/`. Its tasks are the sole executable checklist.
Existing 1.7 review, native/live and publication gates remain. Archive after
implementation and integration, not after creating this proposal.
