# Design

## Context

See [proposal.md](proposal.md) for motivation. Layer 0 installs shared AI CLIs as root; Layer 2 and personalized Layer 3 images inherit those files. The current user image runs as UID/GID 1000, so shared command launchers and their runtime files must be readable and executable by that identity. Docker's image `ENV` applies to noninteractive processes and shells, while `/etc/skel` only affects newly created user profiles.

## Goals / Non-Goals

**Goals:**

- Keep the MiniMax install root and its stable launchers together in a system-owned path.
- Verify MiniMax from the image build and preserve access for the `brett` UID/GID 1000 user.
- Make Grok available through the default image `PATH`, including noninteractive command invocations.
- Refresh floating AI CLI packages from their current stable upstream channels in a no-cache cascade.

**Non-Goals:**

- Add provider credentials or perform provider authentication during image construction.
- Rename Grok's `agent` command or let Cursor claim that ambiguous name.
- Change the bench startup workflow or replace any active bench container.

## Decisions

- Configure MiniMax's official installer with `MCODE_INSTALL_DIR=/opt/minimax-code` and disable shell profile edits. The installer keeps versioned releases and the `current` pointer under this root; copying only its stable launcher to `/usr/local/bin` is not sufficient because that launcher derives its root from its own location.
- Publish `mcode` and `mcode-tools` as symlinks to the launchers under `/opt/minimax-code/bin`. Make the exact install tree readable and executable for other users, then require both version commands during the build and in the UID 1000 image harness. The alternative of installing under `/root/.minimax-code` leaves the image's other users unable to resolve or execute its runtime.
- Add `/opt/grok/bin` to the Dockerfile's image-wide `PATH`, retaining the existing skeleton shell configuration. Editing only `.bashrc`/`.zshrc` would not fix noninteractive commands and would not update an existing user's copied startup files.
- Keep the versioned AI packages on their established upstream floating channels. A no-cache rebuild will resolve each channel once for the image snapshot; maintain explicit upstream pins only where the repository already requires a verified checksum.

## Risks / Trade-offs

- [MiniMax may change its install tree contract] → The build requires its launcher and version command, so an incompatible installer fails the image build rather than producing a broken user command.
- [Floating upstream versions can change between builds] → Record the resulting image IDs and tool versions after the cascade completes.
- [Rebuilding all derived images takes substantial time and disk] → Build the dependency chain once, preserve existing caches only outside the requested no-cache run, and leave live activation to a separately authorized operation after image checks pass.

## Migration Plan

1. Change the shared installer contract and Layer 0 environment.
2. Run the repository's no-cache all-bench cascade.
3. Rebuild each personalized `:brett` Layer 3 image from its refreshed Layer 2 image.
4. Read back CLI versions and execution identity from disposable image checks.

If the rebuild fails, keep existing running containers in place and repair the source or installer before retrying. Live-container activation remains a separately authorized operation.
