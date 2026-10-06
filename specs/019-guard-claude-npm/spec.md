# Claude npm runtime integrity

Authorized by Brett Heap on 2026-10-06. Governing change:
`openspec/changes/guard-claude-npm-updates`.

Approve Claude's npm postinstall for runtime updates while preserving existing
settings. Include optional dependencies. Repair installed user packages offline
and verify their exact executable/version. Support every Layer 3 and Wave bench,
including mounted homes. Do not modify native installs, provider credentials,
running sessions, or container identity.

Acceptance: blocked-hook regression reproduces failure; repair succeeds only
with an exact runnable package; idempotent config preserves other settings;
native selection stays unchanged; all existing managed benches are individually
verified or explicitly reported blocked.
