## Context

See proposal.md. A tmux child already receives `CLAUDE_NO_LANE=1` for an opted-out parent, but direct execution does not consistently publish it.

## Goals / Non-Goals

Give every Claude process launched without a lane an explicit marker. Keep profile settings shared and other hooks running.

## Decisions

Normalize the marker after option parsing: explicit lane options clear an inherited no-lane value, while explicit `--no-lane` wins regardless of option order. Export the marker for profile mode and unset it before lane handoff. Every final bare Claude execution sets it to `1`, including a fallback after a refused lane handoff. The marker is exact-value `1`; other values are not an opt-out.

## Risks / Trade-offs

The environment can be inherited by a later launcher. Track explicit mode options separately from inherited state so `lclaude` can enter a lane from a profile session. A matching openRepoTools guard is required; the hook remains installed for concurrent lane sessions.

## Migration Plan

Install through the existing workBenches launcher installation path alongside the matching openRepoTools guard release. Revert this change to restore the prior launcher behavior.
