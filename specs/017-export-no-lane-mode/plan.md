# Implementation Plan

Governance: `openspec/changes/export-no-lane-mode/`.

Track explicit lane and no-lane requests during parsing. Normalize the environment before launching and mark every final bare Claude execution. Keep Bash 3.2 compatibility. Extend the existing binary-selection regression to observe the mode received by Claude and lane-start, including tmux children. Update the launcher reference and README.

Verify with the binary-selection, name-guard-hook, lane-default and Amendment 11 host regression suites, Bash syntax checks and strict OpenSpec validation. Dependency: openRepoTools feature `002-skip-no-lane-guard` consumes the marker.
