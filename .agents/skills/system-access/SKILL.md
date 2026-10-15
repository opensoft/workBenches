---
name: system-access
description: Discover and connect to authorized Opensoft systems from workBenches using bench-access and short-lived SSH certificates. Use for tenant-managed system access; ordinary GitHub Git authentication keeps its existing configuration.
---

Read `/usr/local/share/workbenches/system-access.json` for the installed capability and `/etc/workbenches/access.json` for the operator-provisioned environment configuration. Missing or disabled configuration means this bench is not enrolled; report that state without creating an identity or switching to a human account.

Use an explicit environment for every command:

```sh
bench-access --env qa doctor
bench-access --env qa login
bench-access --env qa targets
bench-access --env qa explain eagle
bench-access --env qa ssh eagle --account ops --task-id TASK --grant-id GRANT
```

For an agent, use only its configured wallet identity and trusted task/grant IDs. The wallet signer runs through its declared custody provider; do not copy a private key, share another bench identity, borrow a human token, or supply a password to bypass enrollment. A denied target requires a role/grant/policy change by the responsible authority, not a different SSH flag.

A listed target is authorized, not necessarily reachable: use the approved LAN/VPN path. Keep host verification enabled. SSH login permission does not authorize arbitrary administrative operations; the target account and task scope still apply.

Report successful certificate issuance separately from a successful remote login. Never print tokens, client assertions, private keys or provider response bodies. For failures, report only the environment, non-secret identity/target metadata, refusal reason and correlation ID.
