# Tenant system access

The shared base image installs the pinned opensoft-bench-access wheel under an isolated virtual environment. Its source is `opensoft/Opensoft-Tenant`, `infra/smallstep`; the vendored wheel checksum and dependency hashes are checked during installation. Rebuild the wheel from the reviewed tenant source when updating; copy its provenance and complete dependency lock together.

The capability at `/usr/local/share/workbenches/system-access.json` advertises the command. Both environments are disabled until the operator supplies `/etc/workbenches/access.json` with independently checked issuer/host trust and an isolated per-identity session directory. The image contains no credentials, keys or grants. See `.agents/skills/system-access/SKILL.md` for usage.

Agent enrollment binds a wallet, current composition, Keycloak client and approved key custody. A locally readable key does not provide the authority ceiling of a per-use-authorized signer. No agents or grants are enrolled by this distribution change.

Use the declared workBenches build and refresh tooling. A committed Dockerfile or rebuilt base image does not update a running bench. Preserve active sessions and report source, built image and running-container status separately. GitHub SSH authentication is independent.
