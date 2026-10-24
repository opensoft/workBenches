# v1.6.2 development — guided company connection

Issue: [#213](https://github.com/opensoft/workBenches/issues/213).
Development version only; no v1.6.2 release is published by this change.

First-time company login now explains application registration and opens a
guided connection menu: administrator enrollment import, registration guidance
and existing registration. The guide covers the current public-client/device
flow and offers explicit native browser/clipboard actions with manual fallback.
Existing configured companies retain their sign-in behavior.

Settings are reviewed in full, discovery is checked without claiming that a
client registration is verified, and the existing browser/device flow handles
actual sign-in. Non-secret enrollment exports are private, atomic and do not
overwrite existing files. Shared import validation rejects secrets/unknown
fields, redirects, invalid URLs and oversized input.

This does not implement arbitrary identity-provider support or automatic client
registration, collect administrator credentials, change broker/vault grants or
authenticate an AI-provider profile. It preserves existing device-flow trust
checks, cancellation, saved Profiles and company isolation. See the
[company connection guide](company-connection.md) and
[implementation verification](../specs/033-company-connection-wizard/quickstart.md).
