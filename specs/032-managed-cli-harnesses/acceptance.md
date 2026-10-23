# Acceptance record — 2026-10-23

All execution used declared Tools/workstation test containers. No real account
credentials, paid prompts, existing bench restarts or workstation-wide installs
were part of verification.

## Public distribution smokes

Each of these installed into an isolated temporary home, passed its noninteractive
publisher command, reported installed from its owned receipt, then removed its
managed payload/launcher. Credentials/projects were not used.

| Entry | Observed installed version | Path |
| --- | --- | --- |
| dsh | 0.2.1-rc.2 | npm |
| Kimi Code | 2.3.1 | npm |
| Qwen Code | 0.26.0 | npm |
| mini-SWE-agent | 2.4.6 | isolated uv/Python |
| Amp | 0.0.1792785637-g8d232a | publisher script |
| hax | 0.6.1 | publisher archive/checksum |
| Forge | 2.14.0 | publisher musl binary/asset digest |
| Plandex | 2.2.1 | CLI archive/asset digest |
| Junie CLI | 26.10.20 (3813.10) | publisher bundle; direct CLI launcher |

The final mini-SWE-agent run also exercised uv bootstrap from its official
installer without borrowing a preinstalled uv. Earlier smoke failures exposed
and corrected npm 12's empty-prefix requirements, unsupported `--version`
arguments, Python archive API compatibility and Forge's glibc baseline.

## Native boundary and bench lifecycle

A synthetic executable installed/verified/removed through the real Tools→native
callback and staging-home helper. Cancellation fixtures verify descendant
termination for both local processes and native callback groups.

`smoke-managed-harnesses.py --docker-recreation` passed in the declared
`tools-runtime` service: built a selected-dsh image from the mirrored runtime,
launched two fresh containers and checked dsh in both, then used the ordinary
bench resource validator with a private fixture catalog to install and remove dsh
in an initially empty running container as its non-root user. Desired IDs were
persisted and cleared. The created container and image tags were removed by
immutable ID/private tag; other benches were untouched.

This is live proof of runtime copying, target transport and image recreation.
It does not claim a full rebuild of every production bench image or authenticated
agent sessions. The other 61 enabled recipes are source-audited; they have not all
been installed end-to-end on every platform. Mentat is explicitly unavailable.

## Automated acceptance

The managed installer, target and UI suites cover owned-only deletion, rollback,
interruption, foreign launchers, redirected ancestors, receipts, npm publisher
identity/policy, download/archive rejection, native platform selection, exact
Docker IDs/users, cancellation, pending targets, desired-list privacy, image
freshness, native/Python allowlist parity and generated image runtime drift.

All 41 local setup/catalog/filter/layout/credential/lifecycle and managed
installer suites passed across the regression run and focused reruns. Two
fixtures initially lacked the new registry/module files; their copies were
updated and the affected prerequisite/cancellation suites passed unchanged
assertions. Fresh-runtime-home verification also rejected staging-bound shims;
Junie now launches its actual bundle entry rather than its HOME-bound updater
shim, and all nine public smoke checks passed the stricter launcher verification. OpenSpec strict validation passed. The code preserves the existing
114-layer budget rather than raising the limit. Release version, source locks,
1.7 human review/merge/publication gates and feature 031 credential runtime are
unchanged.

GitHub's first live component-lifecycle run exposed an outdated TUI key sequence
from before the category column and default Frontier filter: it never selected
Codex for removal. The fixture now tabs into results and moves one row from
Claude to Codex (Copilot is filtered out). The declared isolated Docker
component-lifecycle service passed install/uninstall/reinstall with unchanged
assertions preserving account data, source work, projects, shared bases and
volumes. This is an additional live suite beyond the 41 local fixture suites.
