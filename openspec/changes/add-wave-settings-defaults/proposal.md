## Why

Wave Terminal clipboard behavior depends on user settings that can be absent on
new workstations, while overwriting an existing settings file would erase user
preferences. A small explicit helper can add safe defaults without claiming to
repair every Wave clipboard regression.

## What Changes

- Add an opt-in helper that resolves the Windows Wave configuration directory
  from WSL or accepts an explicit directory.
- Add only missing clipboard-related default keys and preserve all existing
  user-selected values and unrelated settings.
- Update settings atomically and preserve the existing file mode.
- Add isolated tests and operator documentation.

## Capabilities

### New Capabilities

- `wave-settings-defaults`: Defines safe, explicit, non-destructive Wave Terminal default configuration.

### Modified Capabilities

None.

## Impact

- `scripts/configure-wave-settings.sh`
- `devcontainer.test/test-configure-wave-settings.sh`
- `docs/WAVE-SETTINGS.md`
- The helper mutates a Wave user settings file only when an operator runs it;
  general repository setup remains unchanged.
