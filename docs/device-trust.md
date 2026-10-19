# Devices — v1.7

Devices is a registry of **a signed-in user on a workstation**. Brett on Eagle
and another user on Eagle are separate registrations. Profiles → Personal &
companies → Devices (or V) opens the list; pick Personal or a company. Each company
also has V Devices in its own menu. This is implemented on the v1.7 feature branch,
not included in v1.6 or activated on existing workstations.

## Connect two workstations

1. Configure both with the same administrator-provided device-registry HTTPS URL
   and sign into the same immutable account/context. Company contexts also need
   an administrator's membership grant. Device registration is automatic after
   sign-in when the account's enrollment includes registry settings; otherwise
   choose Configure registry once. Signing in never approves incoming SSH.
2. The list shows each user/device, OS, last check-in, login/server fingerprints,
   SSH address, and separate incoming/outgoing approval or request. A recent
   check-in is not an online/reachable guarantee.
3. On Raven, Configure the hostname/IP and port reaching Raven's SSH server.
   The public server key is read from `/etc/ssh/ssh_host_ed25519_key.pub` locally.
   No keyscan result is automatically trusted. The SSH server, its routing and
   firewall must already work. A device without a configured address can still
   register and make outgoing connections.
4. On Eagle, select Raven → Request permission to connect there. On Raven,
   select Eagle → Allow Brett on Eagle to connect here. Verify the displayed
   login-key fingerprint. Raven installs an expiring authorization in Brett's
   own authorized_keys. The reverse direction remains unapproved.
5. On Eagle, select Raven → Connect. A supported native terminal opens, or a
   fully quoted command is displayed for you to run. The connection uses the
   dedicated device identity and the registered Raven server key with strict
   checking; it does not change global SSH config or known_hosts.

The source key is a new, dedicated Ed25519 key under
`~/.ssh/workbenches/device-<random-id>`, private mode 600. It has no passphrase so
the signed-in account's background synchronization/SSH flow can use it without
importing an existing personal key. Only public data is uploaded. Local disk/key
protection remains the OS user's responsibility; administrators/root can generally
access a user's files or session. Approval does not confer sudo or access to other
OS accounts. Existing grants outside this feature can independently permit access.

## Remove access and retire devices

Remove incoming access revokes only peer → this device. Forget device retires its
central registration and all its managed directional grants; only the owner can
do so, including for a lost workstation. A retired ID cannot be silently reused.
Replace local registration explicitly retires the old ID and creates a new key/ID;
old local private-key files are preserved for manual recovery/cleanup.

The local agent checks every two minutes while running, signed in and able to
refresh its OIDC session. Authorizations expire after ten minutes even if offline.
A destination's next successful sync removes revoked keys; explicit authorization
failures also remove its local managed entries. Sign-out removes this account
context's local managed incoming keys immediately and blocks a racing renewal.
Disabling the registry does the same locally. Signing out on a source does not
erase its SSH private key or revoke its existing outgoing approvals: retire that
registration or revoke it on the destination to remove outgoing access.
Existing SSH sessions continue;
unmanaged authorized_keys entries are untouched.

The agent starts after configured sign-in or opening a configured Devices pane.
It is a user process, not a privileged boot service. After a workstation reboot,
sign in/open Devices or run `bash scripts/device-trust.sh --start`. It will not
renew leases while stopped. If offline access/refresh tokens are unavailable or
revoked, sign in again. Personal and company sessions are independent.

## Administrator deployment

Use the existing broker container, HTTPS ingress and OIDC audience configuration.
`config/credential-broker.example.json` has disabled defaults. Enable only the
intended contexts, for example:

```json
"deviceRegistry": {
  "enabled": true,
  "contexts": {
    "personal": {"enabled": true},
    "company:example": {
      "enabled": true,
      "members": [{"issuer": "https://id.example/realms/company", "subject": "immutable-user-id"}]
    }
  }
}
```

Personal permits authenticated users of this broker to manage their own inventory.
A company context additionally requires an exact issuer/subject member entry.
Neither permits one owner to see or authorize another owner's devices. This first
version does not implement cross-person sharing or company-wide administrative
SSH access. Do not infer membership or link accounts by matching email addresses.

Company enrollment descriptors can include:

```json
{
  "issuer": "https://id.example/realms/company",
  "clientId": "workbenches",
  "deviceRegistryUrl": "https://broker.example",
  "deviceRegistryContext": "company:example"
}
```

The enrollment confirmation states that sign-in will register the user/device.
For a preprovisioned personal account, `account-provider.json` may include
`"deviceRegistry": {"url": "https://broker.example", "context": "personal"}`.
Use only an explicitly trusted administrator endpoint: the client sends its OIDC
token to that broker. The public client must request broker-audience access and
support offline access if unattended renewal is wanted. TLS redirects are refused.

Inventory, directional grants, audit and hashed device capabilities live in the
broker's existing durable SQLite database; include it in protected backups. This
feature needs no new Key Vault permissions and puts no device inventories in
Keycloak. Provider credentials keep the existing broker-only Key Vault path.
Do not expose broker SQLite or capability files to clients or public web hosting.

Workstation state is private, account-bound and separated by registry/context in
`~/.config/workbenches/**/devices/`. Device capabilities authorize destination-only
operations in addition to the verified OIDC owner. They are never returned by list,
logged, or sent in URL/argv. No existing user/host private SSH keys are uploaded.
Symlinked or other-user-owned SSH paths and writable-by-others files are refused.

Endpoints are authenticated POST `/v1/devices/{register,list,request,approve,revoke,sync,forget}`.
All take a context. Operations on a registration require its private device token,
except owner-authorized list/forget. Incoming approve/revoke use the destination
registration; request uses the source. Host-key/address/port changes invalidate
existing directional grants and require approval again. Login-key/user changes
require a new registration. Deployed OIDC signatures, issuer/audience, company
membership and server-side owner checks apply to every request.

## Verification and limitations

Run the declared fixtures without real credentials or published SSH ports:

```bash
docker compose -f devcontainer.test/docker-compose.yml --profile credential-sync run --build --rm credential-sync
docker compose -f devcontainer.test/docker-compose.yml --profile device-trust run --build --rm device-trust
```

The device-trust service has no network interface beyond loopback. It creates
fictional users and keys and an isolated SSH daemon. Its sudo privilege is only
inside that disposable test container. It checks approval, wrong-user/key denial,
strict server-key mismatch, revocation and expiry. Production needs no sudo.

Linux/WSL and macOS clients require native OpenSSH with `expiry-time` support.
Native Windows is outside this version. Live HTTPS/OIDC, real Raven/Eagle,
macOS terminal behavior and workstation reboot acceptance remain release gates;
fixture success is not deployment certification. As with the other v1.7 features,
VERSION and the source lock retain their inherited v1.6 source baseline until a
separate v1.7 release freeze; there is no v1.7 tag or release yet.

OpenSSH references: [authorized_keys restrictions and expiry](https://man.openbsd.org/sshd.8),
[strict host checking and explicit identities](https://man.openbsd.org/ssh_config.5).
