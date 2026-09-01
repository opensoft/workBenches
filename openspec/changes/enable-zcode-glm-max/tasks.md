## 1. Runtime setup

- [x] 1.1 Install the official ZCode Linux runtime and CLI in the WSL user profile.
- [x] 1.2 Register the desktop OAuth callback handler and complete the official Z.ai login.
- [x] 1.3 Verify ZCode configuration and credential files have user-only permissions.

## 2. Model synchronization and native validation

- [x] 2.1 Compare the desktop and CLI model catalogs without exposing credentials.
- [x] 2.2 Synchronize the desktop GLM-5.3 definition into the CLI provider catalog.
- [x] 2.3 Select model `zai/glm-5.3` with thought level `max` through the native ZCode protocol.
- [x] 2.4 Complete a live prompt and verify the runtime records model GLM-5.3 with variant Max.

## 3. OmniRoute and OpenCode validation

- [ ] 3.1 Establish an OmniRoute app-server transport compatible with ZCode CLI 0.16.5's NDJSON protocol.
- [ ] 3.2 Complete an OmniRoute request through the ZCode Coding Plan route and verify GLM-5.3 with Max effort.
- [ ] 3.3 Add the verified ZCode route to the OpenCode catalog and agent roster.
