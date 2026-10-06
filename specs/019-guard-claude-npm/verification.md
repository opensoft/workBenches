# Verification - 2026-10-06

Executed in py-bench against the mounted feature worktree, as brett.

- Real npm 12.0.2 integrity suite: 28 checks passed. Includes an isolated
  loopback registry, exit-zero blocked-hook reproduction, plain npm reinstall
  with the configured approval, exact version, missing payload, hook timeout,
  concurrent configuration, config permissions, inherited approvals, symlink
  preservation, native preservation, native-only .zshrc startup, and shared wiring.
- Layer 3 Claude suite: 43 checks passed.
- Wave lifecycle regression: passed, including guard activation as bench user.
- Cascade image validation regression: passed.
- Bash syntax, git diff whitespace, and strict OpenSpec validation: passed.

## Existing managed containers

Guard deployed in place, policy configured as brett, consuming CLI verified:

| Container | Selected Claude | Result |
|---|---|---|
| py-bench | npm 2.1.291 | verified |
| cloud-bench | native 2.1.291 | verified, installation unchanged |
| m365-bench | native 2.1.291 | verified, installation unchanged |
| cpp-bench | npm 2.1.291 | verified, added user-owned copy; shared floor untouched |

The three stopped managed containers were started for verification. No live
container was replaced, no session was killed, and no provider credential was
modified. Foreign CodexFactory py-bench-* clones and Frappe application stacks
were excluded: they are not workBenches personalized containers.

## Additional image compatibility

Ephemeral, network-disabled probes passed on dotnet, flutter, frappe, go,
java, php, rust, ops, gentec and sim personalized images, as brett. Their
pre-existing shared CLI version was 2.1.274. Probes did not claim to persist
changes into images. Together with the four containers, all 14 available
personalized bench types passed.

## Persistent image activation

The patched Layer 3 recipe successfully built py-bench:brett with Claude
2.1.291, UID/GID 1000, Docker socket group 1001 and persisted npm policy.
All 14 personalized images were rebuilt and passed network-disabled probes
through their normal zsh login shell, as UID/GID 1000, with the npm executable
reporting 2.1.291: py, cloud, m365, cpp, dotnet, flutter, frappe, go, rust, java,
php, ops, gentec and sim. Each contains the guard and persisted npm policy.
PHP and Frappe initially hit the 30-second Codex version-probe timeout; both
succeeded with a 120-second bounded probe. A transient WSL service connection
timeout was bypassed by routing the Windows Docker client to the same verified
desktop-linux engine and named bench, without restarting WSL or Docker.

Image builds do not replace running containers. Layer 0 source approval is
included for the next shared rebuild; this work does not claim a Layer 0
rebuild or unrelated CLI upgrades.

## Delivery checks

PR #136's CI, including the new real-npm job, passed at code head 09d8d15.
An explicit Codex review was requested; the connector reported exhausted
code-review quota, so no Codex review is claimed. Brett authorized opening and
landing the PR after checks pass. This evidence-only update is rechecked
before landing.

## Post-landing implementation correction

The final Wave smoke test exposed a PATH-context mismatch: direct docker exec
selected cloud's shared 2.1.283 CLI, while its login shell selected native
2.1.291. The guard now runs under Wave's declared interactive shell, with login
startup only for zsh, matching the consuming environment including .zshrc and
.bashrc. Review follow-up added native-only .zshrc coverage and sh/bash/zsh
argument regressions. This preserves the existing specification and does not
introduce a new resolver or require rebuilding any image.

After Brett explicitly approved replacement, cpp-bench was recreated from
the rebuilt image (sha256:5c315e0f2eece0195e9b23f8e2635a232d14ef90a43b9d0ce315540a00466bc2).
Its legacy devcontainer definition still lacks some shared profile mounts;
the declared Dev Containers lifecycle was retained with a host cache
Compose overlay for those mounts. Config and shared launcher library mounts
remain read-only, and the existing history volume was retained. Its full Wave
check then passed as brett. Only cpp-bench was replaced; the other three live
containers were preserved. The cache overlay is runtime repair, not a claim
that the cppBench submodule's devcontainer definition was changed.
