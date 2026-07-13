# WorkBenches VPN Setup

WorkBenches can depend on large Git fetches and Docker downloads. On hotel or
filtered networks, VPN clients can make small SSH checks pass while large Git
pack transfers stall.

## Recommended VPN Clients

- **0dcloud** for routed access from the workstation.
- **AmneziaVPN** for Amnezia/AmneziaWG client access and router workflows.

The WorkBenches TUI exposes **AmneziaVPN** and **0dcloud VPN** as separate
Tools-column selections. It uses `scripts/setup-vpn.sh`, which:

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
./scripts/setup-vpn.sh 0dcloud
```

Or patch manually:

```powershell
$body = @{ tun = @{ enable = $true; mtu = 1400; 'gso-max-size' = 1400 } } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri 'http://127.0.0.1:9090/configs' -Method Patch -ContentType 'application/json' -Body $body
```

## 0dcloud Routing Rules

Do not add GitHub-specific `DIRECT` rules. GitHub works best through the normal
0dcloud proxy path; `github.com`, `githubassets.com`, `githubusercontent.com`,
and `github.io` do not need split-tunnel bypass rules. In testing, GitHub
`DIRECT` rules made browsers, Docker builds, and release downloads slow or
flaky, while allowing GitHub to fall through to a `Proxy` rule was stable.

0dcloud includes bundled Microsoft rules that may not show in the custom-rule
GUI. In particular, the active runtime rules can include:

```text
DOMAIN-SUFFIX,microsoft.com,DIRECT
DOMAIN-KEYWORD,officecdn,DIRECT
```

Those built-in rules mean deleting a visible custom `microsoft.com` rule may
not make Microsoft traffic fall through to `Match,Proxy`. Always verify the
runtime rules with the local controller instead of relying only on the GUI:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '& {
  $rules=(Invoke-RestMethod http://127.0.0.1:9090/rules).rules
  for ($i=0; $i -lt $rules.Count; $i++) {
    if ($rules[$i].payload -match "github|microsoft|officecdn") {
      [PSCustomObject]@{
        index=$i
        type=$rules[$i].type
        payload=$rules[$i].payload
        proxy=$rules[$i].proxy
      }
    }
  }
} | ConvertTo-Json -Depth 4'
```

If Microsoft account pages feel slow, a narrow top-priority rule can be tested:

```text
DOMAIN-SUFFIX,account.microsoft.com,DIRECT
```

Keep that rule narrow. Do not replace it with broad GitHub or broad Microsoft
bypass rules unless fresh route tests show they are needed on the current
network.

## Installation Notes

AmneziaVPN can be installed with:

```powershell
winget install -e --id AmneziaVPN.AmneziaVPN --accept-package-agreements --accept-source-agreements
```

0dcloud is distributed through the 0dcloud Windows client download flow. If it
is not already installed, download it, then rerun:

```bash
./scripts/setup-vpn.sh 0dcloud
```

For unattended installs, provide a local installer path:

```bash
WORKBENCHES_0DCLOUD_INSTALLER=/mnt/c/Users/me/Downloads/0dcloud.exe ./scripts/setup-vpn.sh 0dcloud
```
