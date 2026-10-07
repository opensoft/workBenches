# Design

## Context

See [proposal.md](proposal.md). All fourteen child repositories have clean verified default-branch baselines. Eight are pinned submodules; six are setup clones. None has a child Speckit feature hook, so their configuration-only slices use paired external linked worktrees under the parent's single governed feature and executable task list.

## Goals / Non-Goals

**Goals:** Cover canonical Compose services and every tracked distributed variant, including Frappe bench workers and Flutter app build templates.

**Non-Goals:** Image changes, PID tuning, database/Redis/nginx/ADB service changes, project-wide bootstrap, automatic live migration or unrelated host-path cleanup.

## Decisions

- Set Compose `init: true` at the bench service definition. Dev Containers inherits it from Compose; adding a second JSON setting is unnecessary. The existing Wave override remains defense in depth.
- Preserve every other service field and keep GPU/user-map overlays unchanged. Templates with explicit patch-version rules receive their patch bump.
- Check tracked canonical Compose files using Docker Compose's JSON configuration output. Disable interpolation, environment-file resolution and path resolution; do not print the resulting configuration or parser stderr.
- Discover bench-consuming services from their bench images, or the declared app build in Flutter templates; ignore infrastructure-only Compose files and partial override fragments. Missing services/configuration are failures, not silent passes.
- One parent governance record and Speckit list owns cross-repository delivery. Child PRs link that record; child merge commits are verified before moving parent pins. This avoids fourteen duplicate planning systems for a configuration-only extension.

## Risks / Trade-offs

- Existing containers retain their original HostConfig → report source delivery separately and require explicit replacement later.
- Compose overlays can disable inherited init → resolve each declared overlay chain, check partial overlays for explicit disabling and preserve existing launch tests.
- Some benches are not gitlinks → publish their own repositories; do not add unrelated submodules or claim the parent pins those six.
- Existing host-specific mount paths in templates → do not copy them into new code; flag them as pre-existing portability debt outside this init-only change.

## Migration Plan

Validate old definitions fail, apply minimal service settings, validate all fourteen child worktrees and parent stacks, and run Wave lifecycle regression. With publication authorization, land reviewed child PRs and then the parent checker/config/pin PR. Rollback is a reviewed removal of the setting; no source rollout automatically replaces containers.
