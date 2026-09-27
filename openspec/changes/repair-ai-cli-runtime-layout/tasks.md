# Tasks

## 1. Speckit Implementation Handoff

- [x] 1.1 Complete feature `009-fix-ai-cli-packaging` and verify the refreshed image sources and disposable image checks expose the runnable AI CLI set without recycling active benches.

## 2. Review Hardening

- [x] 2.1 Update regression assertions to distinguish the shared `/opt/minimax-code` install from the legacy developer installer.
- [x] 2.2 Require both `mcode` and `mcode-tools` version commands, plus Grok, to remain runnable after installation.
- [x] 2.3 Register non-root runtime checks for `mcode`, `mcode-tools`, and Grok in the Layer 0 image test harness.
- [x] 2.4 Correct the quickstart so cascade validation does not claim to build personalized Layer 3 images.
