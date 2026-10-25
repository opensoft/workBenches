# Implementation plan

Stack on 033-company-connection-wizard in linked feature 160. Keep OpenSpec
profile-manifest-sources as governance with this bounded implementation handoff.
Use the pinned upstream Rclone image binary in Tools. Login uses the same image
in a temporary narrow-mount container: an HTTP relay on the container interface
forwards the published host-loopback port to Rclone's container-loopback OAuth
listener. Native browser opening uses existing private RPC. Root remains read-only.
No host networking, host Rclone, permanent port or public listener is required.

New cloud_profiles module owns scope-specific connection/source metadata, private
Rclone invocation, bounded listing/read, provider-manifest validation/review/merge
and launcher application. Profiles F action delegates there. Reuse the existing
composer/onboarding merge behavior, but sanitize imported paths/ownership and
reject secrets. Local files follow the same review path without authentication.
Use separate connection configs and locks; strip inherited RCLONE_* overrides.
Per-command OAuth output is captured privately and errors are generic.

Google requires an administrator-supplied OAuth app because Rclone 1.75.2 warns
its shared client ID is retiring. Document desktop app setup; user login remains
browser-only. Microsoft may use Rclone's supported default app or configured app,
subject to tenant consent. A source connection is not a company membership grant.

Verify focused units in declared workstation containers, strict OpenSpec in the
developer image, and actual Tools/container/host-loopback fixture transport with
private image tags. No real cloud login or user credential inspection in tests.
Use one executable task list below; exact-head PR review and CI finish acceptance.
