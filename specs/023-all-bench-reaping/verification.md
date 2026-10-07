# Verification: all-bench process reaping

## Source checks

On 2026-10-07, the checker rejected all 61 original selected service configurations. Review identified an additional standalone build-only gentec user-map service; the checker now selects its BASE_IMAGE contract and validates it alone and merged.

Eight regression tests pass, including absent/false/string/numeric init values, bench image selection, build-only Flutter/gentec services, infrastructure exclusions, overlay chains, empty checkouts and redacted parser errors. All 63 final service configurations pass with Compose 5.5.1 and an isolated Compose 2.40.3 binary. The Wave launcher lifecycle suite and strict OpenSpec validation pass. The generated pyBench AMD ROCm overlay resolves with init enabled. No images were rebuilt for this setting.

| Repository | Checked service configurations |
|---|---:|
| workBenches | 5 |
| cppBench | 1 |
| dotNetBench | 1 |
| flutterBench | 13 |
| frappeBench | 24 |
| goBench | 1 |
| javaBench | 1 |
| phpBench | 1 |
| pyBench | 1 |
| rustBench | 2 |
| 365Bench | 3 |
| cloudBench | 2 |
| opsBench | 3 |
| gentecBench | 4 |
| simBench | 1 |

## CI compatibility

Compose 2.40.3 still checks whether required service env files exist when resolving with `--no-env-resolution`. The validator therefore stages only tracked Compose YAML plus empty env fixtures, uses a synthetic environment and suppresses configuration/parser output. This preserves full Compose schema checking without reading actual credential files. Eleven public children are checked from parent CI; the three private children use their own CI context and an immutable public checker commit.

## Live activation boundary

Source implementation initially preserved py-bench, cloud-bench and m365-bench. The user subsequently authorized replacing cloud-bench after being told it had eight open shell sessions. That separate operation retained persistent mounts and `sys-benches_cloudbench-zshhistory`; it did not delete volumes or restart WSL/Docker.

- py-bench retained container `988cd7d35898`, its start time and runtime init.
- cloud-bench changed from `68ad7acd4c60` to `4bd57d827ebc`, runtime init enabled, PID 1 docker-init, Brett UID/GID 1000, zero zombies.
- The original cloud image had been removed from the image store; replacement used the existing `cloud-bench:brett` image `7439ac9cc30a` without rebuilding it.
- Interactive cloud shell checks returned Claude Code 2.1.291 and Codex CLI 0.161.0.
- Initial Dev Containers creation attempts timed out even though the second attempt created a running container. A subsequent normal Wave `--check` passed and verified the consuming Claude guard without changing installation.
- m365-bench retained container `8a07291bc7da` and its start time; live activation there is not authorized by the source rollout.

The all-bench source fix does not imply all existing containers are replaced. No source rollout can retrofit immutable HostConfig settings into a running container.
