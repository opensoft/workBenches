# Feature Specification: Default Claude startup effort

**Feature Branch**: `020-default-claude-effort`

**Created**: 2026-10-06

**Status**: Accepted for implementation

**Input**: User description: "can we make pclaude auto do that? so if no effort is set then pclaude adds that"

## User Scenarios & Testing

### User Story 1 - Reliable startup default (Priority: P1)

A user starts or resumes Claude through pclaude without specifying effort and gets xhigh, including models that ignore the legacy profile setting.

**Independent Test**: Capture arguments with a mock Claude executable and assert exactly one startup fallback.

**Acceptance Scenarios**:

1. **Given** no explicit effort, **When** a conversation starts, **Then** Claude receives `--effort xhigh`.
2. **Given** a resume argument or print-mode prompt, **When** Claude starts, **Then** the fallback is present and original arguments are unchanged.

### User Story 2 - Preserve operator choices (Priority: P1)

A user can explicitly choose max or another supported effort without the launcher overriding it.

**Independent Test**: Exercise both CLI forms and inherited/profile environment overrides.

**Acceptance Scenarios**:

1. **Given** `--effort max` or `--effort=high`, **When** a conversation starts, **Then** no fallback is added.
2. **Given** a nonempty `CLAUDE_CODE_EFFORT_LEVEL` in the environment or profile settings env, **When** a conversation starts, **Then** no fallback is added.
3. **Given** utility, login, or status commands, **When** invoked, **Then** no effort argument is added.

### Edge Cases

- Empty environment values do not suppress the fallback.
- A prompt argument after standalone `--` is not interpreted as an effort option.
- Invalid explicit effort values remain native Claude validation's responsibility.
- Lane/tmux handoffs retain original command classification and arguments.

## Requirements

- **FR-001**: Conversation startup MUST receive `--effort xhigh` unless CLI or environment effort is explicitly set.
- **FR-002**: Both `--effort VALUE` and `--effort=VALUE` MUST suppress the fallback before standalone `--`.
- **FR-003**: Inherited and profile environment overrides MUST be preserved without exposing settings or credentials.
- **FR-004**: Utility commands MUST NOT receive the new option.
- **FR-005**: Existing model and effort settings MUST NOT be rewritten by this change.
- **FR-006**: The shared lane-aware startup path MUST use the same fallback without changing lane selection.

## Success Criteria

- **SC-001**: Every isolated conversation-default scenario receives exactly one xhigh fallback.
- **SC-002**: Every explicit override and utility scenario receives zero added effort options.
- **SC-003**: Existing launcher regression suites pass without altering expected lane behavior.

## Assumptions

- The fallback is a launcher startup policy, not a replacement for all profile preferences.
- Running sessions are unchanged; only future launches are affected.
- Tests use temporary manifests and mock binaries, never live credentials or provider requests.
