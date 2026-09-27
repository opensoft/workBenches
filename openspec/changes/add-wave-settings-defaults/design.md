## Context

Wave stores user settings as JSON. On WSL, the consuming Wave application is
Windows-native, so the default path must resolve the Windows user profile rather
than write to an unrelated Linux config directory. Existing user settings are
authoritative and must not be replaced.

## Goals / Non-Goals

**Goals:**

- Add missing clipboard-related defaults safely and atomically.
- Preserve existing values, unrelated keys, and file permissions.
- Support an explicit configuration directory for tests and unusual layouts.
- Keep execution opt-in and visible.

**Non-Goals:**

- Claim that settings alone fix every Wave clipboard regression.
- Start, stop, or reconfigure Wave automatically during general setup.
- Replace malformed JSON silently.

## Decisions

- Resolve the Windows profile through PowerShell when running under WSL. On
  native Linux, use `$XDG_CONFIG_HOME/waveterm` or fall back to
  `$HOME/.config/waveterm`.
- Validate JSON with Python already present in workBenches, preserve the exact
  representation of existing values, and splice only missing defaults.
- Apply defaults only when keys are absent. Existing true or false values both
  remain authoritative.
- Write a temporary file in the destination directory and atomically replace the
  settings file, preserving its existing mode. Immediately before replacement,
  compare the source inode, metadata, and contents with the validated snapshot;
  abort if Wave or another invocation changed it.

## Risks / Trade-offs

- [Wave changes setting names] → Tests protect current keys; a future migration
  can update the explicit helper without touching unrelated settings.
- [Settings JSON is malformed] → Refuse with the exact file and parse error
  rather than overwrite recoverable user data.
- [Wave updates settings concurrently] → Refuse the stale replacement and ask
  the operator to rerun against the new file.
