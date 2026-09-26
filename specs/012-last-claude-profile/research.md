# Research: Remember Last Claude Profile

## Decision: Store the canonical name under the profile home

**Rationale**: `${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}` already scopes every profile lookup and supports isolated test homes. A sibling `.last-profile` record naturally follows that override and contains no credential material.

**Alternatives considered**: Shell environment variables do not survive unrelated terminals; per-profile storage makes finding the last profile circular; Key Vault adds network and secret-custody machinery for a local convenience pointer.

## Decision: Use atomic same-directory replacement with mode 0600

**Rationale**: A temporary regular file followed by rename prevents readers from seeing partial content when concurrent terminals update the selection. Restrictive permissions match adjacent profile state and avoid leaking even non-secret account naming unnecessarily.

**Alternatives considered**: Direct truncation can expose empty or partial state; file locking adds a dependency and is unnecessary because last-writer-wins is the desired concurrency rule.

## Decision: Persist after preflight but before handoff or exec

**Rationale**: Alias resolution, directory validation, CLI availability, runtime configuration, and setup-token validation have succeeded at that point. Interactive launch paths replace the current process, so recording after exit is not reliable.

**Alternatives considered**: Persisting during parse records typos and broken profiles; persisting after Claude exits delays the update for long-running sessions and misses `exec` paths.

## Decision: Gate the shared hook with a process marker

**Rationale**: `pclaude` and `lclaude` intentionally share profile settings, credentials, and sessions. A conditional managed command avoids settings-file races while keeping lane-aware enforcement. The marker is explicitly threaded into tmux children using the launcher's existing environment composition.

**Alternatives considered**: Removing/re-adding the hook per launch races concurrent sessions; separate configuration directories split the profile; changing openRepoTools broadens ownership and deployment scope.

## Decision: Migrate the legacy exact command in place

**Rationale**: Existing settings use the exact unconditional command as the managed-key identity. The runtime merge can recognize both old and new forms, remove only the old managed hook, append the new form once, and retain grouped foreign commands and entry metadata.

**Alternatives considered**: Leaving both commands would still block profile-only prompts; wholesale replacement of `UserPromptSubmit` would destroy operator-owned hooks.
