# Implementation Plan: Codex Profile Runtime

**Branch**: `013-codex-profile-runtime` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/013-codex-profile-runtime/spec.md`

## Summary

Make profile-specific Codex homes compatible with the official standalone
installation by defining executable precedence and linking one canonical
standalone package cache into every manifest-backed profile. Preserve all
credentials, sessions, history, active processes, containers, and npm installs.

## Technical Context

**Language/Version**: Bash on Ubuntu 24.04

**Primary Dependencies**: `jq`, POSIX filesystem links, existing workBenches profile manifest and link helper

**Storage**: Existing profile directories and one canonical package cache; no new copied payloads

**Testing**: Isolated shell regression in `devcontainer.test/test-codex-profile.sh`, syntax and diff checks

**Target Platform**: workBenches Linux images and WSL-backed bench containers

**Project Type**: Shell launcher and workstation bootstrap tooling

**Performance Goals**: Profile selection adds no network request and only constant-time executable/path checks

**Constraints**: Preserve credentials, sessions, history, existing npm Codex, running containers, and active daemons

**Scale/Scope**: Every manifest-backed Codex profile on a workstation

## Constitution Check

The repository constitution remains an uninitialized template and defines no
project-specific gates. Repository and global rules apply: use the feature
worktree, keep secrets out of the repository, make narrow source changes, and
verify without restarting live workloads. The design satisfies these gates.

## Project Structure

### Documentation

```text
openspec/changes/expose-codex-profile-runtime/
specs/013-codex-profile-runtime/
```

### Source and tests

```text
base-image/files/codex-profile
scripts/setup-codex-profiles.sh
devcontainer.test/test-codex-profile.sh
```

**Structure Decision**: Extend the existing profile launcher and setup surface;
do not introduce a new runtime manager or duplicate package store.

## Complexity Tracking

No constitution violations or additional architectural complexity.
