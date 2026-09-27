# Design

## Context

See `proposal.md` for motivation. The shared launcher already resolves aliases to canonical profile names and has a single `run` path used by both wrappers. `pclaude` forces no-lane mode; `lclaude` opts back into lane resolution. Per-profile `settings.json` is shared by both launch modes, so deleting the lane-name hook for one mode would race or weaken the other.

## Goals / Non-Goals

**Goals:**

- Keep one remembered profile per operating-system user and profile-home override.
- Resolve the remembered value through the same profile metadata path as explicit input.
- Preserve the existing wrapper split and all explicit action/profile syntax.
- Make one shared hook safe for both profile-only and lane-aware processes.

**Non-Goals:**

- Remembering a different profile per repository, terminal, lane, or tmux window.
- Synchronizing the remembered choice through Key Vault or profile credential escrow.
- Changing Claude credentials, transcripts, lane records, or lane selection precedence.

## Decisions

### Store one canonical name under the Claude profile home

The launcher will store one line in `${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}/.last-profile`. The value is non-secret, follows an existing profile-home override automatically, and does not pollute an individual profile directory. Writes use a same-directory temporary regular file, mode `0600`, followed by atomic rename. Reads reject symlinks, non-regular files, empty values, and additional lines. A bare launch treats a profile home that has never been created as ordinary missing state. Writers serialize with `flock` on an open descriptor for the validated, user-owned profile-state directory. The kernel releases that advisory lock automatically when the holder exits, including abrupt termination, so recovery never has to identify or unlink a stale lock pathname.

Alternatives considered: shell startup variables would not follow profile changes reliably; storing the value inside every profile would make lookup circular; Key Vault is inappropriate for a local non-secret convenience pointer.

### Remember only accepted run launches

The canonical name is persisted in the `run` arm after profile resolution and runtime preflight, immediately before interactive tmux handoff or direct Claude execution. List, login, and status operations do not change it. This avoids surprising switches caused by diagnostics while still recording a launch that uses `exec` and therefore cannot report a later interactive success.

Alternatives considered: remembering at argument parse time would preserve typos and failed profiles; waiting for Claude to exit would prevent interactive `exec` launches from recording the choice until too late.

### Let the user-facing wrappers request a run with an omitted profile

Bare `pclaude` and bare `lclaude` inject the `run` action while the underlying `claude-profile` command preserves its existing empty-invocation list behavior. Only `run` permits an omitted profile, in which case the action parser loads the remembered canonical name. Explicit actions and profiles keep precedence, including `pclaude list`, `pclaude status PROFILE`, and `pclaude PROFILE`.

Alternatives considered: changing the underlying command's empty default would broaden a user-facing request into an unnecessary compatibility change; resolving the state entirely inside each wrapper would duplicate validation.

### Gate the shared name-guard command by launch mode

No-lane mode will export `WORKBENCHES_CLAUDE_PROFILE_ONLY=1` into Claude and tmux children. The managed `UserPromptSubmit` command will first return success when that marker is set; otherwise it executes the existing `lanes-edit.sh guard`. Runtime configuration will migrate the legacy unconditional managed command to the gated command while preserving foreign hooks and grouped-entry metadata.

Alternatives considered: removing the hook during `pclaude` launch would mutate shared settings and race a concurrent `lclaude`; separate settings directories would split credentials and sessions; changing vendored `lanes-edit.sh` would make workBenches depend on an unrelated upstream rollout.

## Risks / Trade-offs

- **A launch that passes preflight but Claude immediately fails still becomes last-used** → This is the earliest reliable point before `exec`; the next explicit profile launch replaces it.
- **A copied or hand-edited state file may be stale** → Resolve it through profile metadata on every use and emit an actionable error.
- **Changing the managed hook command can duplicate or drop grouped hooks if migration is careless** → Extend the existing nested-array merge tests to cover legacy replacement, foreign hooks, metadata, and idempotence.
- **Mode markers can be lost across tmux re-exec** → Add the marker to the existing explicit child environment composition and test both direct and re-exec paths.

## Migration Plan

1. Install the updated wrappers and launcher through the existing workBenches image/setup path.
2. On each profile's next use, runtime configuration replaces its legacy managed guard command with the gated form.
3. The first valid explicit profile run creates the remembered-profile record; until then, bare commands fail with guidance and do not guess.
4. Rollback restores the previous launcher; the harmless `.last-profile` record can remain because older versions ignore it.
