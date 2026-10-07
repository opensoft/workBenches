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

CodeQL identified the child-ref checkout in the manual workflow context as a potential default-branch cache-poisoning path. Child-reference validation now runs only for pull requests, while push/manual runs retain parent-only checks, and all checkout steps disable credential persistence. This follows the [CodeQL isolation guidance](https://codeql.github.com/codeql-query-help/actions/actions-cache-poisoning-poisonable-step/) without dismissing or suppressing the finding.

## Child publication

All fourteen child PRs were reviewed at their final heads and squash-merged on 2026-10-07. Their default-branch commits were fetched and verified before advancing the eight registered parent gitlinks. The six setup clones remain separate repositories, not newly added submodules.

| Repository | Merged PR | Verified default-branch commit |
|---|---|---|
| cppBench | [4](https://github.com/opensoft/cppBench/pull/4) | dd7ff022b8429faac68985f62da80a415cec0731 |
| dotNetBench | [4](https://github.com/opensoft/dotNetBench/pull/4) | 28aef2202f674d15de1e8559b6e841df9f853197 |
| flutterBench | [5](https://github.com/opensoft/flutterBench/pull/5) | 67eb337893b9c94337b765e2dc371b16900194eb |
| frappeBench | [2](https://github.com/opensoft/frappeBench/pull/2) | a7b1f4ef007f21570c66cb1a2720c0b9d798ba5f |
| goBench | [4](https://github.com/opensoft/goBench/pull/4) | fdf5a43a78eeba8d9fb359866e380e0e415bf68f |
| javaBench | [4](https://github.com/opensoft/javaBench/pull/4) | 8c6aa973e7d27b55548a553ec401e429b1405426 |
| phpBench | [3](https://github.com/opensoft/phpBench/pull/3) | 85d7f50f5c3a5e1ae77584a96c8002d845330c68 |
| pyBench | [7](https://github.com/opensoft/pyBench/pull/7) | cf62c02f18b5a5003b2927c3f2edd83fa05c08d0 |
| rustBench | [6](https://github.com/opensoft/rustBench/pull/6) | 6dff138ba8cfc697f46a3fb646dc598640f87c0c |
| 365Bench | [2](https://github.com/opensoft/365Bench/pull/2) | 718cd32614bf5325e995654782b0c60da6e648f8 |
| cloudBench | [6](https://github.com/opensoft/cloudBench/pull/6) | bc2982c56c1e4d3721237dabafdfe4b0d4f35c75 |
| opsBench | [3](https://github.com/opensoft/opsBench/pull/3) | 199630a66cab5b68d282f6942c87eb54e698f37c |
| gentecBench | [2](https://github.com/opensoft/gentecBench/pull/2) | 6212e7cb77d2513844ee0ef47835e935aaaddfa3 |
| simBench | [2](https://github.com/opensoft/simBench/pull/2) | c7711fe0a8a7e2180acfc7a9c60c0f22914a6276 |

Review also caught Java launchers still using the legacy `docker-compose` executable despite requiring the Compose plugin. Those launch and diagnostic commands now invoke `docker compose` directly. Bash syntax and native PowerShell AST checks passed; the final Java head received a fresh Codex review with no major issues.

## Live activation boundary

Source implementation initially preserved py-bench, cloud-bench and m365-bench. The user subsequently authorized replacing cloud-bench after being told it had eight open shell sessions. That separate operation retained persistent mounts and `sys-benches_cloudbench-zshhistory`; it did not delete volumes or restart WSL/Docker.

- py-bench retained container `988cd7d35898`, its start time and runtime init.
- cloud-bench changed from `68ad7acd4c60` to `4bd57d827ebc`, runtime init enabled, PID 1 docker-init, Brett UID/GID 1000, zero zombies.
- The original cloud image had been removed from the image store; replacement used the existing `cloud-bench:brett` image `7439ac9cc30a` without rebuilding it.
- Interactive cloud shell checks returned Claude Code 2.1.291 and Codex CLI 0.161.0.
- Ten additional real PTY zsh startup/exit probes completed successfully; cloud-bench retained zero zombies afterward.
- Initial Dev Containers creation attempts timed out even though the second attempt created a running container. A subsequent normal Wave `--check` passed and verified the consuming Claude guard without changing installation.
- m365-bench retained container `8a07291bc7da` and its start time; live activation there is not authorized by the source rollout.

The all-bench source fix does not imply all existing containers are replaced. No source rollout can retrofit immutable HostConfig settings into a running container.
