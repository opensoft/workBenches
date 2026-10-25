# Rclone cloud manifest import

Authority: Brett, 2026-10-25: add Rclone to the workBenches toolchain in the
Tools container so users can connect and pull their profile manifest file.
Implements the bounded cloud connector part of profile-manifest-sources.

- FR1: Pin Rclone in Tools; expose it through the existing Docker-only shims,
  health/version checks and image fingerprint. No host Rclone installation.
- FR2: Profiles personal/company scopes offer file-manifest import. Support a
  local JSON or browsing connected Google Drive/OneDrive for a provider manifest.
  Store source/connection references under the selected stable scope ID.
- FR3: Use browser OAuth only. A temporary Tools-image login container publishes
  only the host-loopback callback port and receives its private connection
  directory and short-lived native callback session. No peer service.
- FR4: Rclone config remains owner-only and reusable after container removal and
  reboot. Raw config/output/tokens never reach TUI logs, manifests or argv.
  Read-only provider scopes; no sync/upload/delete. Configured OAuth applications
  are supported; Google's retiring shared client ID is not assumed.
- FR5: Download bounded files, validate versioned provider manifest metadata,
  review names/counts and merge isolated local homes/launchers. Reject secrets,
  unknown fields, invalid names, unsafe paths and symlinks. Preserve matching
  profiles and unrelated profiles/credentials on reruns.
- FR6: Cancel/failure terminates login/proxy containers and preserves prior usable
  connections/configuration. Distinguish metadata from launcher and AI credential
  readiness. Remember successful sources for explicit repeat pulls.
- FR7: Use synthetic provider/native fixtures and real container/host-loopback
  tests. Live Microsoft/Google consent remains attended qualification.

Initial file contract: one provider launcher manifest (version 1, profiles array)
per import. Ownership comes from the selected scope. Browse cloud directories or
enter remote-relative paths. Sharing-link resolution and GitHub selected-account
wiring remain the wider source proposal's work. No remote writes; the latest
request authorizes pulling. Remote workstation support remains v1.8. No release
publication in this task.
