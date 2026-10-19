# v1.7 tasks

- [x] Specify per-user/device identity, directional consent, central inventory,
  context isolation, host-key pinning, and bounded offline revocation.
- [x] Implement broker registry and authorization.
- [x] Implement local registration, SSH lifecycle and synchronization.
- [x] Integrate Profiles and account lifecycle.
- [x] Complete fixture and isolated SSH acceptance.
- [ ] Validate a real HTTPS/OIDC deployment and Raven/Eagle flows.

## Fixture evidence — Raven, 2026-10-19

- Declared broker/client/CPC service: 57 tests, 56 passed; real SSH case is
  intentionally reserved for the separate isolated device-trust service.
- Declared device-trust service: all 27 tests passed, including real sshd login,
  wrong key/user denial, server-key mismatch, revocation and offline expiry.
- Native Tools runtime passed, including new user/device registration without
  workstation Python, existing GitHub and Vault/Profiles button flow.
- Full Workstation Setup regression job passed. Profiles (15), account (15),
  multi-identity (14), image-layer budget, syntax and whitespace checks passed.
- Native callback tests verify dedicated key generation/derivation on the host,
  private local state, repeated registration, and public-only upload.
- Sign-out/old-context renewal and retirement protections have focused tests.

Fixture records use fictional keys/accounts. No cloud resources, real SSH server
configuration, existing credentials or v1.6 source branches were changed. Existing
broker CI entrypoint includes the new device suite; the real SSH service is an
additional declared acceptance command. Live deployment and platform gates remain
open; VERSION/source lock await a separate v1.7 freeze.
