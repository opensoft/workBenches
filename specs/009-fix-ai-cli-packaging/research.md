# Research: Shared AI CLI Image Refresh

## Decisions

- Keep each CLI on its existing installer and stable channel; run the supported no-cache cascade to resolve current upstream versions rather than pinning volatile CLI versions in a second manifest.
- Install MiniMax Code with `MCODE_INSTALL_DIR=/opt/minimax-code` and `MCODE_NO_MODIFY_PATH=1`, then expose both upstream commands (`mcode` and `mcode-tools`) through `/usr/local/bin`. Make the shared install readable/executable by UID 1000 and make `mcode --version` a required runnable-image check.
- Set Grok's installed `/opt/grok/bin` directory in the image-level `PATH`; shell startup files remain supplementary, not the mechanism required for Wave/noninteractive use.
- Preserve the existing Layer 3 convention where `brett` is UID/GID 1000. Remove the inherited Ubuntu user/group occupying that ID before the personalization layer creates `brett`.
- Keep credentials and account profiles outside image layers. Validate disposable images while leaving every running bench untouched; activation requires a separate authorization.

## Verification Approach

Use the repository's focused source checks and, when the final integrated tree is ready, `scripts/update-and-rebuild.sh --all --cascade --no-cache --user brett`. Run direct noninteractive CLI/version checks against disposable images, including `mcode --version` as the default UID 1000 user. Compare resolved CLI versions with current upstream stable channels during execution; do not recreate active containers.

## Risks

- Upstream installers are floating and can change during a long cascade; record actual installed versions after the build, not only the initial audit snapshot.
- Active containers retain their prior image until recreated; image success alone does not establish that Wave is using the new build.
- Some bench-specific images may override a shared CLI. Direct Layer 3 checks are required to detect such overrides.
