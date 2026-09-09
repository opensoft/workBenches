## 1. Bounded Transport Probe

- [x] 1.1 Implement a deadline-bound WSL process-creation probe that owns and can terminate only its own child process.
- [x] 1.2 Implement consecutive-failure health classification and transition-based evidence capture.
- [x] 1.3 Add atomic status writes, bounded event-log rotation, and sanitized host/guest evidence collection.

## 2. Explicit Lifecycle and Documentation

- [x] 2.1 Implement limited per-user scheduled-task install, status, start, stop, and uninstall actions.
- [x] 2.2 Document the diagnostic boundary, runtime state, evidence, and non-disruptive recovery limits.
- [x] 2.3 Keep source merge separate from live scheduled-task installation.

## 3. Validation

- [x] 3.1 Parse both PowerShell scripts without syntax errors and run static analysis when available.
- [x] 3.2 Run a one-shot probe against a temporary state directory and verify its JSON contract.
- [x] 3.3 Verify strict OpenSpec validation, diff hygiene, and absence of host-specific committed paths.
- [x] 3.4 Verify bounded child-process termination, status output/exit-code separation, encoded child arguments, and installed-script removal on uninstall.
- [x] 3.5 Verify host diagnostic failures remain non-fatal and failure evidence retention is bounded.
- [x] 3.6 Verify host and Windows-event diagnostics run behind an owned-process deadline.
