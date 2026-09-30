# Feature Specification: Publish the no-lane launch mode

**Feature Branch**: `017-export-no-lane-mode`
**Created**: 2026-09-30
**Status**: Approved for implementation by the user's request
**Input**: Pass the no-lane marker to Claude and clear it for lane launches.

## User Scenarios & Testing

### User Story 1 - Launch a profile without lane checks (Priority: P1)

The child Claude environment identifies profile mode in direct and tmux launches. Verify with fake Claude and tmux fixtures.

### User Story 2 - Enter a lane from a profile session (Priority: P1)

Explicit lane requests clear inherited profile mode. Explicit `--no-lane` wins in either option order. Verify the environment received by fake lane-start.

## Requirements

- **FR-001**: A no-lane Claude launch receives `CLAUDE_NO_LANE=1`.
- **FR-002**: Lane handoff receives no inherited exemption marker.
- **FR-003**: Explicit no-lane selection wins over explicit lane selection; explicit lane selection wins over inherited no-lane mode.
- **FR-004**: Bare fallback also publishes no-lane mode.
- **FR-005**: Keep shared hook settings intact.

## Success Criteria

- Direct and tmux profile fixtures observe marker `1`.
- Explicit lane fixtures observe an unset marker, including when inherited from a profile session.
- Both orders of conflicting options start Claude without a lane.
