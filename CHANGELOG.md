# Changelog

## 1.5.0 — Unreleased

**Reliable workstation setup.** [Scope approved; release gates pending](docs/release-1.5.0.md).

First release using a product version, a source freeze, and an annotated Git tag.

- Fresh clone with SSH preference and HTTPS fallback; guided Docker/WSL requirements.
- Selected bench/tool install, update, and removal with projects and credentials preserved.
- Docker, Tools, and Vault lifecycle actions in Requirements.
- Container-based setup tools and credential access.
- Optional Keycloak connection and existing Azure Key Vault, Bitwarden/Vaultwarden,
  and 1Password recovery, with separate provider sign-in/unlock.
- Vault connection and sign-out actions that preserve queued selections.
- Immediate TUI startup with background checks and updates to changed lines.
- Corrected OpenSoft header and concise setup controls.
- Product version displayed in the TUI, setup logs, and `setup.sh --version`.
- Frozen source pins for selected bench installations.

Single-login Microsoft/Keycloak credential recovery, Flutter apps, additional
vault providers, production Keycloak migration, and full package/image locking
are deferred. The release tag and publication await validation of a committed
candidate.
