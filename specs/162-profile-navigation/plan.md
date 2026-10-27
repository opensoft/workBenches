# Plan

Extend profile_tui with stacked Profile/list and About panels. Add a navigation
module behind setup-profiles.py, retaining the existing company/GitHub actions.
Extend setup_profiles validation with optional metadata, local-workstation
records and stable personal AI scopes. Reuse bounded source reads and provider
manifest validation. Isolate profile portability and explicit remote writes in
a separate module; extend only the native gh helper's narrow write operation
and Rclone's browser permission flow. Test inside the declared Tools container.
Reload the existing preview terminal from this feature worktree after checks.
