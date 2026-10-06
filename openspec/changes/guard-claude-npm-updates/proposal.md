# Proposal

Status: authorized for implementation by Brett Heap on 2026-10-06:
"implement the durable fix. and make sure it also fixes all the other bench containers".

## Why

npm 12 can exit successfully while blocking Claude's postinstall, leaving a
placeholder instead of its optional native executable. Image-time repair alone
does not protect subsequent user-owned npm updates in running benches.

## What Changes

- Configure the runtime user's npm policy to approve only Claude in addition
  to existing approvals, and retain optional dependencies.
- Provide one local, locked repair/verification helper; fail on an incomplete
  native install or ineffective policy instead of reporting success.
- Apply the safeguard in every Layer 3 recipe and every Wave bench launch,
  including homes mounted over image defaults.
- Explicitly approve and verify the shared Layer 0 installation.
- Repair existing bench installations as their normal user without recreating
  containers, interrupting sessions, or modifying provider credentials.

## Capabilities

### New Capabilities

- `claude-npm-runtime-integrity`: runtime policy and exact-path verification
  for user-owned Claude npm installations across benches.

### Modified Capabilities

None. Existing resolver ownership in openRepoTools and native install
selection are retained.

## Impact

Shared Layer 0 installer, Layer 3 recipe, Wave launcher, and focused regression
tests. Implementation is Speckit feature `019-guard-claude-npm`.
No global allow-all script policy, new auto-updater, credential reset, or live
container replacement is introduced.
