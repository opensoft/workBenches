# Device registration and directional SSH trust — v1.7

Target: v1.7, isolated from release/1.6.0. This is user-account device trust,
not machine-wide trust. A registration means "Brett on Eagle", not every Eagle
user. Identity is verified OIDC issuer + subject, never an email or device name.

## User workflow

Profiles contains Devices alongside GitHub accounts, with personal/company
contexts. Configure an administrator-provided registry once, then sign in.
A configured, signed-in workstation automatically registers/checks in. This does
not authorize SSH. The list shows This device, Registered, recent/last check-in,
incoming approval, outgoing approval, and pending requests. Recent does not prove
network reachability. Select a peer to request a connection, approve it incoming,
revoke incoming access, connect, or forget a retired registration.

Approvals are directional: Brett/Eagle -> Brett/Raven does not authorize the
reverse direction, other OS users, other destination accounts, or sudo. Only the
destination registration's private device capability can approve incoming access.
The issuer/subject owner may retire a lost device without that capability.
Personal and company contexts are isolated, even with the same owner. Company
context enrollment additionally requires exact administrator membership grants.
Initial scope permits connections only between the same immutable owner within
one context. Cross-person sharing/admin grants are future scope, not implicit.

## Storage and trust

The existing authenticated HTTPS broker holds the central registry in durable
SQLite alongside broker metadata. Public keys need integrity, not secret storage;
Key Vault remains server-only for provider credentials and is not required for
this registry. No new direct user vault access. Keycloak establishes identity and
does not hold device inventories. Administrator configuration enables the feature
and allowed contexts; disabled is the default.

Each local account/context owns a dedicated Ed25519 login key, random device ID,
and random device capability; only its hash reaches broker storage. Private SSH
keys never leave their local files. Capabilities are sent in TLS request bodies,
never argv, logs, or device-list responses. Owner binding includes issuer/subject.
Registering an arbitrary email is not enrollment. Published host keys are separate
from login keys and are read from the local server public-key file, not trusted
from an unauthenticated network scan. Host-key changes clear affected approvals.
Login-key replacement requires retiring and registering a new device.

## SSH and revocation

Incoming sync manages only marked lines in the current user's authorized_keys,
preserving unrelated bytes. It never edits sshd_config, opens a port, installs
sshd, adds sudo rights, or touches another user's files. Symlinks/unsafe ownership
are refused. Fresh approvals are short leases (10 minutes), renewed every two
minutes when the local agent has a valid authenticated session. Authorization
lines use OpenSSH expiry-time plus restrict,pty. Revocation/forget removes managed
lines on the destination's next successful sync; offline leases expire. Existing
SSH sessions are not terminated, and unmanaged grants are not revoked. Source
sign-out does not revoke its outgoing approvals; retirement or destination
revocation is required for that.

Connect uses only this registration's identity, a dedicated known-hosts file
pinned to the destination's registered server key, strict host checking, and no
agent forwarding. It launches a native workstation terminal when possible, with
a displayed command fallback. An SSH server and a reachable LAN/VPN route remain
prerequisites. Windows native is not yet supported; WSL uses its own Linux user.
macOS/Linux require supported OpenSSH expiry-time behavior; live platform tests
remain a release gate.

Sign-out removes managed local incoming authorizations immediately. Forgotten
registrations cannot be silently resurrected by check-in. A new sign-in may renew
leases only for already configured/enrolled contexts. Startup registration is
opt-in via registry configuration; no network or key generation otherwise.
