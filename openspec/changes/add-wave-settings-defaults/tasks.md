## 1. Safe settings helper

- [x] 1.1 Add the explicit Wave settings helper with WSL path resolution, preserve-existing semantics, and atomic writes.

## 2. Verification and documentation

- [x] 2.1 Add isolated tests for fresh and existing settings files.
- [x] 2.2 Document invocation, scope, and the fact that the helper is not a universal clipboard repair.

## 3. Review hardening

- [x] 3.1 Abort an update when the source settings file changes after it is read and before atomic replacement.
- [x] 3.2 Document native Linux `XDG_CONFIG_HOME` and `$HOME/.config` path resolution.
