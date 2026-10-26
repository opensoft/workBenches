# Startup effort contract

- `pclaude PROFILE`: append default xhigh at conversation startup.
- `pclaude PROFILE --effort max`: preserve explicit max, add nothing.
- `pclaude PROFILE --effort=high`: preserve explicit high, add nothing.
- Nonempty inherited/profile effort environment: add nothing.
- `pclaude login PROFILE`, `pclaude status PROFILE`, utility commands: add nothing.
- `lclaude PROFILE`: same fallback after lane selection, without changing lane semantics.
- Arguments following standalone `--` are prompt data, not effort overrides.

Explicit settings JSON and project/model preferences are not parsed by this launcher fallback; use CLI or effort environment to opt out.
