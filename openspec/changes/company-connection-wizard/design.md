# Design

Use a shared Python company_connection module for bounded enrollment parsing,
configuration review/discovery, administrator guide and export. Reuse profile_tui
selection and the existing cancellation-aware non-secret prompts. Integrate the
wizard at the account helper's missing-configuration boundary; existing configured
companies bypass it. Retain the explicit Import enrollment action through the
same parser/review contract, without starting a login merely by importing.

Separate states: settings reviewed, discovery checked, registration unverified,
and signed-in subject confirmed by existing device flow/userinfo. Discovery does
not establish client existence or authorize company credentials. Save only after
review and explicit confirmation. Export only allowlisted issuer/clientId and
optional organizationId/credentialBrokerUrl. Never copy account-session tokens
or arbitrary input keys. Private atomic writes refuse symlink destinations and
existing export targets unless the user explicitly chooses another destination.

Keycloak guide explains public client, device authorization enabled, no CLI client
secret, openid/profile/email scopes and offline_access only for opted-in sync.
Client ID may be administrator-chosen here; other providers can assign it.
The issuer is the realm issuer, not an administration/login-page URL. Offer an
explicit native browser action to a derived same-provider administration URL and
copyable instructions with fallback. Never evaluate provider URLs as shell code.

Use existing host callback for native browser/clipboard utilities when running in
Tools; fall back to printed instructions. No registration API or application
creation occurs. Unsupported/malformed discovery remains actionable and preserves
prior configuration. Back returns to the previous wizard step/menu; Q/interrupt
retains established cancellation exit statuses and saved Profiles state.

No new dependencies or runtime-image module copying is needed: scripts are
already available under the checkout in Tools. The new module must also work
from the direct host helper and tests, without a host-specific committed path.
