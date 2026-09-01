## 1. Quiet plugin configuration

- [x] 1.1 Disable OmniRoute background synchronization in the global OpenCode configuration
- [x] 1.2 Disable management-only combo and enrichment features while retaining `/v1/models` and disk cache
- [x] 1.3 Set plugin diagnostics to error-only logging
- [x] 1.4 Patch the installed plugin so startup logging and the config shim honor the configured quiet feature flags

## 2. Validation

- [x] 2.1 Validate the updated OpenCode JSON and effective plugin option values
- [x] 2.2 Start a fresh profile-aware OpenCode process and confirm OmniRoute warnings are absent
- [x] 2.3 Run a governed OmniRoute inference call and confirm the expected response without terminal-noise output
