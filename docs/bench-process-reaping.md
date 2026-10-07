# Bench process reaping

Canonical bench Compose services use `init: true`. This inserts Docker's small init process to forward signals and reap terminated orphan helpers. It covers Wave, Dev Containers and direct Compose creation. The Wave-generated override also retains the setting.

The setting is applied to fourteen benches across dev, sys and bio families, Frappe's bench-based workers, distributed Flutter templates and tracked workspace examples, bench examples/tests, and parent family/test stacks. Infrastructure-only database, Redis, nginx and ADB services are unchanged.

## Validate source without starting containers

Run through the declared bench environment, from the workBenches checkout:

```bash
python3 devcontainer.test/test-bench-init.py
python3 scripts/check-bench-init.py . devBenches/pyBench sysBenches/cloudBench
```

Pass any other child checkout paths as additional arguments. Only tracked full definitions and tracked override chains are checked. Ignored/generated personal overlays can be checked separately with the same Compose `config` flags; a personal override that sets `init: false` defeats the protection.

The checker uses Compose's JSON parser with an empty project env file, a minimal synthetic interpolation environment, and service environment-file/path resolution disabled. It prints only repository/file/service identifiers and counts, not configuration values or parser stderr. Parent CI checks the eleven public child repositories: registered submodules at their parent-pinned commit, setup-cloned benches at their default branch. The three private children (goBench, phpBench and cloudBench) check their own checkout in their own CI context, using an immutable public checker commit. This avoids cross-repository access tokens.

## Activate separately

This is a container creation setting, not an image setting. No Layer 0-3 rebuild is required. Rebuilding an image or restarting an existing container does not change its `HostConfig.Init`.

Preserve current sessions while landing source changes. When authorized and safe, replace the selected bench through its declared launcher repair path. For the Wave launcher that is the normal bench command with `--repair`. Do not replace all benches automatically or delete persistent volumes.

Verify the replacement separately:

```bash
docker inspect --format '{{json .HostConfig.Init}}' py-bench
docker exec py-bench ps -o pid,ppid,stat,comm -p 1
docker exec py-bench sh -c 'ps -eo stat= | awk "\$1 ~ /^Z/ {count++} END {print count+0}"'
```

Expect `true`, Docker's init at PID 1 and no accumulated zombies. Init reaps orphaned children; it cannot fix a still-running application's failure to wait for its own children. A zombie already adopted by the old PID 1 cannot be removed by updating source alone.
