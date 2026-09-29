# Implementation Plan: Launch Only the Newest Published Claude Code

**Branch**: `016-launch-current-claude` | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: opensoft/workBenches#119, governed by the ratified OpenSpec change `launch-current-claude` (opensoft/workBenches#120, merged at `c2403eb`), task 1.2.

## Summary

At the one point where `claude-profile` resolves the executable, apply design.md Decision 4's precedence: an operator `CLAUDE_BIN` pin, else `claude-current --porcelain` (`--offline` for a launch that starts no session), else the #109 native ordering and the `PATH` lookup with one notice. Resolve lazily, once, in the process that starts Claude, and hand `lane-start` the path, the `CLAUDE_RESOLVED_BIN` marker and `CLAUDE_VERIFIED_VERSION`. Print `claude-restart-check`'s line first in the status line. Install a user-owned Claude Code copy at npm latest in Layer 3. Cover each outcome with stubbed resolvers and mocked Docker.

## Technical Context

**Language/Version**: Bash; the launcher's resolution logic stays Bash 3.2-compatible (no `mapfile`, associative arrays or `readlink -f` in the new code)
**Primary Dependencies**: `claude-current` and `claude-restart-check` from `opensoft/openRepoTools` (#134), called from `PATH`, never vendored; `jq`, `tmux` and Docker as today
**Storage**: None; the resolver owns its cache and lock
**Testing**: Bash regression suites in `devcontainer.test/`, with stub resolvers, a stub restart check, a fake tmux, mocked Docker, and fake npm, node and claude
**Target Platform**: Linux workBenches containers and hosts; macOS hosts degrade to the fallback and to no restart line
**Project Type**: Shared CLI launcher, status line, and a personalized image layer
**Performance Goals**: One bounded `npm view` per session launch (0.6 s measured, 10 s bound in the resolver); none for a launch that starts no session; the status line check reads only `/proc`, bounded here at 1 s
**Constraints**: Keep the #109 ordering and every behavior the existing suites assert; keep the direct `exec` line byte-identical; no host-absolute paths in committed files; never touch the Layer 0 install; no running container is recreated
**Scale/Scope**: One launcher, one status line script, the Layer 3 Dockerfile and build script, and their suites

## Constitution Check

The repository constitution is still an unfilled template, so it imposes no concrete gate. Repo-local and user-global instructions apply: an isolated feature worktree, no host-specific paths in committed files, bench-local validation, and preservation of unrelated work. Rechecked after design: no exception is needed.

## Project Structure

### Documentation

```text
specs/016-launch-current-claude/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── quickstart.md
└── tasks.md
```

### Source Code

```text
base-image/files/claude-profile
base-image/files/claude-statusline-command.sh
user-layer/Dockerfile
user-layer/build.sh
devcontainer.test/test-claude-profile-binary-selection.sh
devcontainer.test/test-claude-profile-amendment-11.sh
devcontainer.test/test-claude-tmux-statusline.sh
devcontainer.test/test-claude-statusline-snapshots.sh
devcontainer.test/test-layer3-claude-version.sh
devcontainer.test/test-layer3-codex-version.sh
devcontainer.test/test-ensure-layer3-freshness.sh
.github/workflows/ai-cli-layer3.yml
.github/workflows/speckit-git-bash.yml
```

**Structure Decision**: Resolution stays in the shared launcher, so direct, lane and tmux-wrapped launches get the same executable from one function. The restart notice stays a thin call site in the shared status line; the detection itself is `opensoft/openRepoTools`' command. The Layer 3 install mirrors the Codex overlay and Layer 0's install-hook handling.
