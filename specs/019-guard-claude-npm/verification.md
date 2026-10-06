# Verification - 2026-10-06

Executed in py-bench against the mounted feature worktree, as brett.

- Real npm 12.0.2 integrity suite: 26 checks passed. Includes an isolated
  loopback registry, exit-zero blocked-hook reproduction, plain npm reinstall
  with the configured approval, exact version, missing payload, hook timeout,
  concurrent configuration, config permissions, inherited approvals, symlink
  preservation, native preservation, and shared wiring.
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
| cpp-bench | shared 2.1.274 | verified, installation unchanged |

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
Remaining Layer 3 image builds are in progress and will be recorded below.
Image builds do not replace running containers. Layer 0 source approval is
included for the next shared rebuild; this work does not claim a Layer 0
rebuild or unrelated CLI upgrades.
