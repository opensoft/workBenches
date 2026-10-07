# Verification: Bench Process Reaping

Date: 2026-10-07. Source branch: `021-fix-bench-reaping`.

## Source checks

- The new assertions fail against the unchanged canonical launcher: explicit repair lacks runtime reaping.
- The complete Wave launcher lifecycle suite passes with the feature launcher, including creation/repair init assertions, foreign-image protection and running-container preservation.
- Bash syntax checks pass for the launcher and its regression suite.
- ShellCheck passes excluding SC2016, the pre-existing intentional literal-string check in the regression suite. Unfiltered ShellCheck reports that existing informational diagnostic only.
- `openspec validate fix-bench-reaping --strict` passes. OpenSpec hands execution to the Spec Kit task list, following the global single-executor protocol.

## Live activation

The user explicitly approved replacing active py-bench and terminating its sessions/jobs. The canonical Compose files, generated ROCm overlay and Wave mounts were used. The runtime override now enables `init: true`.

- New canonical py-bench: `988cd7d358982f64fac9ba1011404253cc370c1db5ef6c361dd8b2dc083a3544`.
- Image: the currently declared `py-bench:brett` tag, image ID `sha256:c9a020ab4d63f298da158da4875ec7070f84d1825332e766ceb1e3e28c6677e9`; no image rebuild performed. This differs from the old container's immutable image ID.
- Docker HostConfig.Init: true; PID 1: `docker-init`.
- Ten real PTY-backed zsh login/interactive shell checks succeed as brett, UID/GID 1000; zero zombies after completion.
- Both the feature and canonical Wave `--check` pass and reuse the same new container; the runtime Claude guard verifies 2.1.291.
- Project and profile mounts retained. Active history volume remains `dev-benches_pybenchhistory` at `.workbenches-history`. The obsolete volume mount at `.zsh_history` is no longer attached; that volume was not deleted.
- cloud-bench (`68ad7acd4c60`) and m365-bench (`8a07291bc7da`) retain their original IDs, images, mounts, start times and running state.

## Cleanup caveat

The old py-bench was stopped and renamed for recovery. The existing Layer 3 preparation helper nevertheless matches stopped containers by Config.Image and began removing it because its image ID differs from the current tag. Renaming did not protect it. It remains Dead/removing, so recovery cannot be promised.

The initial Docker diff probes did not complete. Their diagnostic clients were stopped, but the daemon stack shows ongoing filesystem changes walks and container removal waiting in ReleaseLayer/lease deletion. Compose created the new replacement under a temporary name before failing on the old container's in-progress removal. Its init, image, user, service/project labels and persistent volume were verified before renaming it to canonical py-bench and starting it. No Docker/WSL restart, volume deletion, unrelated replacement, or manual daemon-state edit occurred.

## Publication

The normal Wave launcher reuses the repaired live container successfully. Durable source is isolated on this feature branch; future recreation from main requires publishing/landing the source fix. OpenSpec remains unarchived until delivery completes.
