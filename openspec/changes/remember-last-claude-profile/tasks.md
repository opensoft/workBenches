# Tasks

## 1. Remembered profile behavior

- [x] 1.1 Add focused failing tests for bare `pclaude`/`lclaude`, canonical alias persistence, missing/stale/unsafe state, and non-run actions; verify the new assertions fail against the current launcher
- [x] 1.2 Implement private atomic remembered-profile read/write in `base-image/files/claude-profile`; verify focused remembered-profile tests pass
- [x] 1.3 Update command help and operator documentation for bare-command behavior; verify examples distinguish profile-only `pclaude` from lane-aware `lclaude`

## 2. Profile-only guard separation

- [x] 2.1 Add failing tests for the profile-only process marker, tmux child propagation, lane-aware enforcement, legacy hook migration, grouped foreign hooks, and idempotence; verify failures against the current runtime configuration
- [x] 2.2 Export the profile-only marker and migrate the managed name-guard command without changing unrelated hooks; verify focused guard and lane-default suites pass

## 3. Integration and governance

- [x] 3.1 Run shell syntax checks and all focused Claude profile launcher suites in `py-bench`; verify zero failures
- [x] 3.2 Run strict OpenSpec validation and repository documentation/contract checks; verify the change is apply-ready and consistent
- [x] 3.3 Complete the Speckit artifacts and mark implementation tasks finished; verify specification, plan, task, and checklist coverage is complete
