# Tasks

- [X] T001 Record approved navigation, scope compatibility and export contracts.
- [X] T002 Implement stacked panes, profile-kind lists and editable metadata.
- [X] T003 Implement maker/account navigation with stable owner isolation.
- [X] T004 Implement reviewed portable imports and explicit bound-account exports.
- [X] T005 Verify regression/PTY/transport cases in Tools and reload the preview.

Verification on 2026-10-27: 215 tests passed across navigation (25), multiple
identities (14), Profiles (16), sources (26), cloud (33), company connection (19),
guided setup (43), requirements (18), async startup (8) and versioning (13).
OpenSpec strict validation passed. The declared tools-runtime Compose service
passed native GitHub/browser/clipboard, Rclone read-only consent/denied callback,
host adapters, service restart, OAuth relay and real TUI startup/cancellation.
Its optional Vault image smoke test was disabled; no live restore is claimed.

The existing right-hand preview was reloaded from this feature worktree.
Visual checks confirmed the Profile overview, Personal Profiles, editable profile
information and the model-maker list showing existing scoped account counts.
Existing personal/company/identity IDs were preserved. GitHub/Drive write tests
use fixtures; no production upload, consent upgrade or credential restore was
performed. Changes remain a local development feature, not a published release.
