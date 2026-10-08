# Recovering a stale bench bind mount

The shared Wave launcher validates stopped containers' real bind sources before preparation. Known shell and Claude configuration targets require regular files; known workspace/profile targets require directories. Normal attaches to running containers preserve them, even if a host file was atomically replaced after startup.

Docker may store an internal hashed staging path in mount metadata. The launcher resolves such paths through read-only Compose configuration rendering, including existing Wave, ROCm, and WSLg overlays, and validates the original host sources instead. It refuses recovery if a staged source cannot be resolved. This uses `jq`, already required by shared bench helper tooling; it does not create or update overlays during validation.

A missing Docker Desktop WSL staged mount source can prevent `docker start` while the original host file is valid. The launcher reports the specific OCI failure and a shell-quoted recovery command. It does not infer this diagnosis from an exit code alone, automatically replace the container, or restart Docker/WSL.

## Explicit recovery

Run from the workBenches checkout, replacing the example bench with the affected one:

```bash
scripts/wave-container-shell.sh --user "$USER" --repair --check py-bench
```

`--repair` is consent to recreate the named container. It discards files held only in the container's writable layer; save any such work first. Declared host bind mounts and named volumes remain. A stopped container is removed without force, so a concurrent start is preserved. A live container is replaced only when explicitly requested with `--repair`; its sessions terminate.

The existing Compose or Dev Containers lifecycle remains authoritative, including AMD ROCm and WSLg overlays and `init: true`. Preparation can refresh an outdated Layer 3 image; no full cascade is needed solely for a stale bind mapping.

Only one recreation occurs per invocation. If the repaired container still cannot start, the launcher stops with diagnostics instead of looping. Missing or wrong-type real sources must be restored; recreation does not manufacture credentials. In particular, creation/recreation now requires a regular `$HOME/.claude.json` file rather than silently creating an empty one.

## Deployment boundary

The fix changes shared launcher source, not bench image recipes. Publish the feature and ensure Wave's bench links use that updated checkout. An isolated feature worktree does not update the canonical Wave link automatically. Container replacement is a separate explicit operation.
