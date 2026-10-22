# Workstation selection and lifecycle

## Why
Brett's live review on 2026-10-22 requested removing the duplicate service strip, replacing Check buttons with the Benches selection pattern, and showing Installed/Up state in Containers. He explicitly chose all entries, including Docker and WSL, and authorized committing and pushing the completed branch.

## What changes
Space selects/unselects install/start, D selects/unselects uninstall, Enter opens Review, and Review Apply executes service changes. The Requirements count stays; its duplicate service-information row becomes a blank line. Containers shows checkboxes and installation/runtime status. New schemaVersion-1 keys wsl/docker/setup_tools/vault support install/uninstall. Install prerequisites before component work; remove managed services/host prerequisites last and only if earlier work succeeded. Selection-only preview applies nothing.

## Bounds
This is an explicit extension of feature 029's former immediate-service and unchanged-allowed-key contracts. Native Linux Docker Engine removal uses supported package managers and retains images/volumes/data/config. Managed Tools/Vault removal checks ownership and removes containers only, preserving images, volumes and credentials. Docker Desktop removal and WSL removal from inside a running distro are refused with host-side manual instructions, before any destructive step; never report them complete. No WSL shutdown, unregister, restart or deletion is implemented. Install/start retains existing platform support/manual fallbacks.

## Authority and handoff
Accepted from Brett's above chat instructions; one implementation feature: specs/029-setup-guided-wizard, task T039F. Bench-copy merge approval remains pending. The subsequent commit/push authorization permits publishing the feature branch; it does not approve a merge or archive.

## Sources
- https://docs.docker.com/desktop/uninstall/ documents Desktop uninstall data deletion.
- https://docs.docker.com/engine/install/ubuntu/ documents retaining Engine data after package removal.
- https://learn.microsoft.com/en-us/windows/wsl/basic-commands documents destructive distribution unregister.

Component plans retain required readiness. When prerequisites are missing, apply a service-only install plan first; then reopen setup for components. Mixed plans receive full Python/catalog validation before any selected service change.
