# v1.6.1 — private bench GitHub authentication

This patch promotes the private-bench fix tested by Brett on Raven on
2026-10-24. Its runtime changes are the reviewed `76595a1`/`e07ac4c` changes
from PR #211, on top of the v1.6.0 finalization. Source pins remain unchanged.

Git inside Tools can use native `gh auth git-credential` for GitHub HTTPS
operations while retaining SSH preference and existing Git helpers. Clone
failure includes actionable repository-access/sign-in guidance, and retries
complete interrupted private submodule setup without discarding existing work.

The source label is v1.6.1; the earlier local v1.6.1-rc.1 preview used the same
fix with development metadata. No guided company-registration behavior ships
in this patch. That onboarding issue belongs to v1.6.2.

## Verification and release boundary

PR #211 has passing source-freeze, Workstation Setup regression/Tools/credential/
lifecycle checks and exact-head Codex review for `e07ac4c`. Brett exercised the
candidate and requested release as-is. Final metadata/source checks must also
pass. Full protected native/live QA is a separate release gate; missing or
unconfigured QA cannot be described as passed. Any owner-authorized manual
publication exception must be recorded explicitly rather than fabricating evidence.

Company provider sessions, AI-provider credentials, broker grants and vault
authorization remain separate. Unsupported credential-sharing modes remain
disabled, and opening Profiles does not publish existing credentials.
