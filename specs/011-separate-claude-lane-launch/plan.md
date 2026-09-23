# Implementation Plan: Separate Claude profile and lane commands

**Branch**: `011-separate-claude-lane-launch` | **Date**: 2026-09-23 | **Spec**: [spec.md](spec.md)

## Summary

Make `pclaude` profile-only by default and install `lclaude` as a lane-aware wrapper into the same launcher. Preserve explicit `pclaude --lane` compatibility. Move lane restart instructions upstream before updating the vendored pin.

## Technical Context

**Language/Version**: Bash 3.2 compatible shell.  
**Primary Dependencies**: Claude CLI, tmux, lane tooling when lane mode is selected.  
**Storage**: Existing profile and lane records; no new data format.  
**Testing**: Focused launcher shell tests, host/image install checks, openRepoTools lane helper suite, CI regression.  
**Target Platform**: Linux, WSL, and macOS profile launcher; bench images.  
**Project Type**: CLI tooling.  
**Constraints**: No network lookup during profile launch; preserve lane safety fences and startup binary selection.

## Constitution Check

The change follows the OpenSpec governance handoff, uses an isolated feature worktree, retains Bash 3.2 compatibility, and does not write host paths into committed files.

## Project Structure

```text
base-image/files/claude-profile
base-image/files/pclaude
base-image/files/lclaude
base-image/Dockerfile
scripts/setup-claude-profiles.sh
scripts/wave-container-shell.sh
devcontainer.test/
docs/claude-multi-account-profiles.md
specs/011-separate-claude-lane-launch/
```

**Structure Decision**: Keep one full launcher and add small `pclaude` and `lclaude` entry points. The existing `claude-profile` command retains its lane behavior for compatibility, while bare `pclaude` adds `--no-lane` and `lclaude` enables lane mode through `pclaude`. Update the upstream lane tooling and its pin before publishing the changed default.
