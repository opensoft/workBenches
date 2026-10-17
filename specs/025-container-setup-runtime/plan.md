# Plan

1. Add the Tools image and an idempotent Docker-only manager; start it before any
   Python/jq/Git/curl invocation and scope command shims to launcher descendants.
2. Keep native workstation discovery and package actions explicit using a
   private, short-lived host callback channel. Never evaluate command strings or
   route interactive passwords through files; sudo stays in the host launcher.
3. Convert prerequisite inventory and bootstrap to Docker/Tools lifecycle states
   without using the tools they are bootstrapping.
4. Add optional managed Vault access, preserve provider authentication and its
   transient credential boundary, and integrate lifecycle actions in Requirements.
5. Update documentation and regression fixtures; run meaningful unit and live
   isolated-container acceptance checks, then inspect the real TUI layouts.
