# Implementation Plan: Wave Settings Defaults

**Branch**: `015-wave-settings-defaults` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

## Summary

Provide an explicit Bash helper that resolves the consuming Wave configuration
directory, adds only missing clipboard defaults through an atomic JSON update,
and preserves user-selected values, unrelated keys, and file mode. Verify with
temporary directories and document the limited, opt-in scope.

## Technical Context

**Language/Version**: Bash and Python 3

**Primary Dependencies**: WSL interop tools when available, Python standard-library JSON and filesystem modules

**Storage**: Wave `settings.json` in a user configuration directory

**Testing**: Isolated shell test with temporary existing and fresh settings files

**Target Platform**: Windows Wave Terminal configured from WSL, with native Linux fallback

**Project Type**: Workstation setup utility

**Performance Goals**: Complete a local settings update in under one second

**Constraints**: Never overwrite existing settings or run implicitly during unrelated setup

**Scale/Scope**: One local Wave settings object per explicit invocation

## Constitution Check

The repository constitution is still an uninitialized template. Repository
rules require narrow, reversible workstation mutations and isolated tests. The
helper is explicit, preserves existing values, and tests only temporary paths.

## Project Structure

```text
openspec/changes/add-wave-settings-defaults/
specs/015-wave-settings-defaults/
scripts/configure-wave-settings.sh
devcontainer.test/test-configure-wave-settings.sh
docs/WAVE-SETTINGS.md
```

**Structure Decision**: Keep the operation as one standalone script rather than
adding it to automatic setup or bench startup.

## Complexity Tracking

No constitution violations or additional dependencies.
