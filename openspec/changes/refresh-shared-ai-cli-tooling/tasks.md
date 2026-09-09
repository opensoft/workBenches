## 1. Shared Installer Contract

- [x] 1.1 Add the expanded CLI installers with bounded native-script permissions and explicit required-command verification.
- [x] 1.2 Preserve unambiguous command ownership for Cursor, Grok, and the NotebookLM launchers.
- [x] 1.3 Refresh the Herdr checksum and shared image rebuild marker.

## 2. Profiles, Routing, and Documentation

- [x] 2.1 Add Qwen, Kimi Code, and MiniMax profile-family mappings to the account adapter.
- [x] 2.2 Update the operator documentation for the expanded harness set and authentication boundaries.
- [x] 2.3 Update Claude profile initialization and prevent container launches from modifying the host compatibility link.

## 3. Validation

- [x] 3.1 Run shell syntax checks, focused shared-profile tests, and diff hygiene checks.
- [x] 3.2 Verify npm native-script allow-list behavior and an Aider installation in disposable containers.
- [ ] 3.3 Complete a no-cache shared image build and verify every required command in a disposable container.
- [ ] 3.4 Record that running bench containers were not recreated during source and image validation.
