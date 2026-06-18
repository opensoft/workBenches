# WorkBenches VPN Setup

WorkBenches can depend on large Git fetches and Docker downloads. On hotel or
filtered networks, VPN clients can make small SSH checks pass while large Git
pack transfers stall.

## Recommended VPN Clients

- **0dcloud** for routed access from the workstation.
- **AmneziaVPN** for Amnezia/AmneziaWG client access and router workflows.

The WorkBenches installer includes `scripts/setup-vpn.sh`, which:

- installs/checks AmneziaVPN on Windows via `winget`;
- detects 0dcloud on Windows;
- supports a local 0dcloud installer via `WORKBENCHES_0DCLOUD_INSTALLER`;
- patches the 0dcloud/mihomo TUN MTU to avoid large Git fetch stalls.

## 0dcloud MTU Patch

0dcloud uses a mihomo/Clash-style local controller on `127.0.0.1:9090`.
The default TUN settings observed on affected workstations were:

```text
mtu: 9000
gso-max-size: 65536
```

That allowed `ssh -T git@github.com` and `git ls-remote` to work, but large
`git fetch` operations stalled with errors like:

```text
Timeout, server github.com not responding.
fetch-pack: unexpected disconnect while reading sideband packet
fatal: protocol error: bad pack header
```

The fix is:

```text
mtu: 1400
gso-max-size: 1400
```

Run:

```bash
./scripts/setup-vpn.sh
```

Or patch manually:

```powershell
$body = @{ tun = @{ enable = $true; mtu = 1400; 'gso-max-size' = 1400 } } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri 'http://127.0.0.1:9090/configs' -Method Patch -ContentType 'application/json' -Body $body
```

## 0dcloud GitHub Rules

Add these as `DIRECT` or bypass rules above any broader GitHub proxy rule:

```text
DOMAIN-SUFFIX,github.com,DIRECT
DOMAIN-SUFFIX,githubusercontent.com,DIRECT
DOMAIN-SUFFIX,githubassets.com,DIRECT
DOMAIN-SUFFIX,github.io,DIRECT
```

Verify active rules:

```bash
curl -s http://127.0.0.1:9090/rules
```

During a Git connection, the controller should show:

```text
host: github.com
chains: DIRECT
rule: DomainSuffix
payload: github.com
```

## Installation Notes

AmneziaVPN can be installed with:

```powershell
winget install -e --id AmneziaVPN.AmneziaVPN --accept-package-agreements --accept-source-agreements
```

0dcloud is distributed through the 0dcloud Windows client download flow. If it
is not already installed, download it, then rerun:

```bash
./scripts/setup-vpn.sh
```

For unattended installs, provide a local installer path:

```bash
WORKBENCHES_0DCLOUD_INSTALLER=/mnt/c/Users/me/Downloads/0dcloud.exe ./scripts/setup-vpn.sh
```
