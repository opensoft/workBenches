Lane: project-command

CLAIMED — lane project-command for scripts/new-project.sh, scripts/onp and
project command installation. Sibling searches of issues, PRs and remote heads
found no competing migration. The user authorized implementation and installation.

## Why

The generic project creation coordinator now belongs to openRepoProject.
workBenches must distribute the executable and preserve its old entrypoints.

## What Changes

Install a commit/SHA-256 pinned project executable from setup and the command
installer. Forward onp/new-project.sh to project new. Keep bench generators.

## Capabilities

### New Capabilities

- project-command-installation: verified installation and legacy forwarding.

## Impact

Depends on the published openRepoProject executable. Existing estate command
pins and submodule sources are unaffected. Implementation is tracked in
specs/003-project-command/tasks.md.
