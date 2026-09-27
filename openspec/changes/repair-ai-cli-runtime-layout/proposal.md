# Proposal

## Why

The shared images currently contain a broken MiniMax Code launcher because its root-owned install tree is not beside the copied launcher. Grok is installed under `/opt/grok/bin`, but that directory is only added to skeleton shell profiles, leaving ordinary noninteractive commands and existing user profiles without the command. A no-cache refresh also needs to pick up current upstream releases for the floating AI CLI installers.

## What Changes

- Install MiniMax Code into one system-owned tree, expose its launchers through `/usr/local/bin`, and ensure the `brett` UID 1000 user can execute them.
- Include `mcode` in the required shared CLI command contract and require its version command to run during image construction.
- Add Grok's installed binary directory to the image-wide command path.
- Refresh image-managed AI CLI packages and rebuild derived bench images without cache.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-ai-cli-tooling`: Tightens the existing image contract so MiniMax Code's launcher and runtime remain co-located and runnable by bench users, Grok is available through the image-wide path, and rebuilds remain separate from live-container activation.

## Impact

- `base-image/Dockerfile`, `base-image/install-ai-clis.sh`, and `base-image/ai-cli-contract.sh`
- Layer 0 and its derived Layer 1, Layer 2, and personalized Layer 3 images
- The active Wave containers that consume the rebuilt Layer 3 images
