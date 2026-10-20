# Fix fresh-install profile navigation (#174)

The v1.5 acceptance keystrokes clamp an obsolete Requirements index onto Vault
in v1.6. Use the visible Profiles screen and its AI accounts action instead.
Wait for profile-action feedback and refreshed readiness before applying the
selected CLI update. Keep cancellation, verified Vault recovery, repeat install,
bench installation/removal, secret redaction and preservation checks mandatory.

Regression validation uses the production TUI renderer/input/action with only
external discovery and credential helpers isolated. Full acceptance runs through
the declared disposable workstation/engine against the exact frozen branch SHA.
