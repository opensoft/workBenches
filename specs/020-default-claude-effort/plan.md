# Implementation Plan: Default Claude startup effort

**Branch**: `020-default-claude-effort` | **Date**: 2026-10-06 | **Spec**: [spec.md](spec.md)

## Summary

Add an explicit xhigh conversation fallback in the shared launcher, preserving CLI/environment overrides and routing. User authorized implementation; no broader settings migration.

## Technical Context

- Language: Bash, existing jq dependency.
- Storage: Existing profile settings; no new persistent schema.
- Platform: Linux host and bench launchers; Windows desktop runtime unchanged.
- Testing: Isolated fake-binary argument assertions and existing launcher suites.
- Performance: One local settings projection per eligible startup; no network requests.
- Constraints: No secret output, live credential modification, session restart, or unrelated checkout changes.
- Scope: Shared claude-profile, focused regression test, documentation.

## Constitution Check

The checked-in constitution is an unratified template, not an operative source of additional gates. Repository/global protocols apply: accepted OpenSpec change, isolated sequential feature worktree, single Speckit executable task list, portable references, and test verification. All gates pass before and after design.

## Project Structure

- `base-image/files/claude-profile`: startup argument fallback.
- `devcontainer.test/test-claude-profile-effort.sh`: mock-binary regression suite.
- `docs/claude-multi-account-profiles.md`: documented precedence.
- `specs/020-default-claude-effort/`: plan and sole executable task list.
- `openspec/changes/default-claude-effort/`: accepted proposal, design, requirements, task-list pointer.

## Complexity Tracking

No new dependencies, abstraction layers, or governance exceptions.
