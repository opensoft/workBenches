# Research

- The launcher already supports `--no-lane`, but the default still performs lane resolution and binding probes. A default flip plus early environment cleanup is needed.
- `lane-start` launches Claude itself; a separate `lclaude` implementation that calls it before profile selection would duplicate the profile path. A wrapper into one launcher preserves the current account and binary contract.
- The interactive tmux path re-executes the launcher, so lane-aware mode must be passed in its child command.
- openRepoTools handoff prints bare `pclaude` for restarts. Its compatibility update must land before the default changes.
