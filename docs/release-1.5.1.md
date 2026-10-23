# v1.5.1 patch preparation

Patch fixes are developed from `main` and merged through PRs. Profile onboarding,
company credential sync, and workstation enrollment remain v1.6 work on separate
branches. v1.5.0 stays immutable; this document does not announce a new release.

## Patch changes

- #104: clear `LANES_WORKSTATION` in the tmux child command before assigning an
  answered value. An unnamed workstation can no longer inherit the tmux server's
  stale identity. The regression failed before the fix and passed afterward;
  configured workstation values remain explicitly passed through.
- #105: extend the existing OpenSpeckit Bash CI workflow to cover the remaining
  lane-default, lane-start, SessionStart, model-preservation, and statusline
  suites. Existing name-guard and Amendment 11 suites remain enabled.
- PR #163, already on main: preserve annotated release tags during CI checkout
  and allow validation of an existing immutable release tag by workflow dispatch.

## Backlog verification

- #66: current setup registers separate host and container Vibe Annotations URLs.
  The Claude launcher synchronizes managed MCP entries before run, login, or
  status. An added launcher regression starts with a container URL, performs a
  host status invocation, and verifies loopback repair while preserving personal
  MCP entries and account metadata. The test passes without another runtime fix.
  This verifies configuration repair, not availability of a user's MCP service.
- #106: shared-image fingerprinting now includes every file's contents, mode,
  and symlink target across the dev build context, plus its base fingerprint.
  Builds record the fingerprint as an image label. An added regression changes
  only a vendored dev-image helper and verifies invalidation. It passes.
  Direct bench start still refreshes Layer 3 only; rebuilding shared images
  remains a setup operation. Do not claim automatic shared-source refresh on
  every launch or close that broader expectation without a separate decision.
- #107 (historical patch triage; now addressed on the v1.6 candidate): the
  previous pinned openRepoTools installer placed the bare-user name-guard
  hook before workspace linking supplies its target. Its canonical exact hook
  strings and all-or-nothing install contract are upstream-owned. The upstream fix landed in openRepoTools PR #247 at `586dea2`; the v1.6
  candidate updates the complete vendored payload and tests the host/container
  integration. This does not add the change to the immutable v1.5.0 release. Do not
  patch the vendored copy or introduce another settings writer in workBenches.

## Validation and release gates

Local validation passed: nine launcher suites, including 49 lane-default
scenarios / 209 assertions and 111 Amendment 11 scenarios / 465 assertions;
shared MCP profile synchronization; all 12 shared-image regression tests; shell
syntax and whitespace checks. PR #164 records CI validation of this change.

Before publishing 1.5.1, resolve its agreed scope, set VERSION, regenerate and
review the source lock, repeat release and full Workstation Setup checks on the
final clean main commit, then create a new annotated v1.5.1 tag and pass tag CI.
See [the release process](releases.md). This work does not extend platform claims:
macOS and cold Windows provisioning remain unvalidated.
