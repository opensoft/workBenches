# GL.iNet LuCI Router Setup for the Amnezia Endpoint Pool

This handoff is for a local Codex session that can reach the GL.iNet router over
LAN. The cloud bench cannot reach the router directly, so all router changes
must be made from the local network.

The target outcome is:

- The router connects to the Azure Amnezia server using AmneziaWG.
- The router uses only the published secondary endpoint pool, not the primary
  management IP.
- The router can refresh its selected endpoint from the public manifest without
  changing VPN keys or reimporting the whole profile.
- No private VPN config, private keys, pre-shared keys, or router credentials are
  committed to `workBenches`.

## Current WorkBenches Inputs

Manifest URL:

```text
https://amneziamanifest13bd.blob.core.windows.net/manifest/endpoints.json
```

Host-side endpoint helper:

```bash
/home/brett/projects/workBenches/scripts/amnezia-endpoint
```

Global host command, if `~/.local/bin` is in `PATH`:

```bash
amnezia-endpoint
```

The manifest is the source of truth for usable VPN endpoints. The primary
management IP `20.237.172.123` is intentionally not a VPN endpoint and should
not be used in router VPN profiles.

## Compatibility Decision

Do this first. The server is running AmneziaWG, not plain WireGuard. A stock
WireGuard-only router profile is not enough when the exported profile contains
AmneziaWG obfuscation parameters.

Use this order:

1. If the GL.iNet firmware supports AmneziaWG obfuscation, use the GL.iNet VPN
   client import path.
2. If the GL.iNet UI does not support AmneziaWG but the router is running
   OpenWrt 23.05 or newer, use LuCI with AmneziaWG packages.
3. If the router is OpenWrt 22.03 or older and the GL.iNet firmware does not
   already include AmneziaWG support, stop and upgrade firmware first. Do not
   force AmneziaWG packages built for a different OpenWrt release.

Useful checks from the local machine:

```bash
ROUTER=192.168.8.1
ssh root@$ROUTER 'ubus call system board; echo; cat /etc/openwrt_release 2>/dev/null || true'
ssh root@$ROUTER 'opkg print-architecture; echo; df -h'
ssh root@$ROUTER 'command -v awg || true; command -v wg || true; uci show network | grep -Ei "amnezia|wireguard|endpoint" || true'
```

GL.iNet says several router models support AmneziaWG in selected firmware
versions and that full official support is rolling out in firmware 4.9. Amnezia
documents the OpenWrt package path for OpenWrt 23.05 or newer only.

## Inputs the Local Codex Needs

Ask Brett for these local-only values. Do not paste secrets into the cloud
thread and do not commit them.

```text
Router LAN IP:
Router SSH/admin password:
Router model:
GL.iNet firmware version:
OpenWrt base version:
Path to exported AmneziaWG native config:
Desired mode: all LAN traffic or selected clients only
```

The exported config should come from the Amnezia app for this server:

1. Open Amnezia app locally.
2. Share/export the server connection.
3. Choose AmneziaWG protocol.
4. Choose native config format if offered.
5. Save outside the repo, for example:

```text
~/vpn/amnezia-router-native.conf
```

Expected sensitive fields include private keys and possibly a pre-shared key.
Keep the file local.

## Prepare a Router Config with a Pool Endpoint

Before importing the config into the router, patch only the `Endpoint =` line so
it uses the endpoint pool instead of the original server address.

```bash
cd /home/brett/projects/workBenches
cp ~/vpn/amnezia-router-native.conf /tmp/amnezia-router-pool.conf
scripts/amnezia-endpoint patch --config /tmp/amnezia-router-pool.conf --strategy sticky
grep '^Endpoint[[:space:]]*=' /tmp/amnezia-router-pool.conf
```

The patch command creates a timestamped backup next to the patched file. It does
not alter keys or AmneziaWG obfuscation settings.

If the config contains IPv6 addresses and the router/LAN is not intentionally
running IPv6 through the VPN, remove IPv6 `Address` and `AllowedIPs` entries for
the initial setup. This avoids accidental IPv6 leaks or broken imports. Add IPv6
back only after IPv4 is stable.

## Path A: GL.iNet Admin Panel Import

Use this when the router firmware supports AmneziaWG obfuscation directly.

1. Connect to the router LAN.
2. Open the GL.iNet Admin Panel, usually:

   ```text
   http://192.168.8.1
   ```

3. Go to `VPN > WireGuard Client`.
4. Add a new group, for example `Amnezia`.
5. Upload `/tmp/amnezia-router-pool.conf`.
6. Apply the profile.
7. Start the profile.
8. Wait about one minute and verify that the profile turns connected.
9. Go to the VPN dashboard and confirm that traffic is using the VPN.

If the GL.iNet UI rejects the config or connects but never handshakes, switch to
Path B. Do not downgrade the profile to plain WireGuard unless the server config
was explicitly exported as plain WireGuard.

For repeatable endpoint automation, inspect whether the GL.iNet import created a
normal UCI network peer:

```bash
ssh root@$ROUTER 'uci show network | grep -Ei "endpoint_host|endpoint_port|amnezia|wireguard"'
```

If no peer endpoint appears in UCI, the GL UI may be managing the profile in its
own storage. In that case, prefer a LuCI/OpenWrt-managed interface for the
automated refresh script below.

## Path B: LuCI/OpenWrt AmneziaWG Interface

Use this when GL.iNet UI import is not enough but LuCI is available.

Access LuCI through the GL.iNet Admin Panel:

```text
SYSTEM > Advanced Settings > Go To LuCI
```

The LuCI password is normally the same as the GL.iNet web admin password.

### Install AmneziaWG Support

Skip this section if `AmneziaWG VPN` already appears as a protocol in LuCI or
`awg` exists on the router.

Only use this path on OpenWrt 23.05 or newer:

```bash
ssh root@$ROUTER
ping -c 3 github.com
wget -O - https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh | sh
```

If GitHub resolves to IPv6 and fails:

```bash
wget -4 -O - https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh | sh
```

When the installer asks whether to reboot immediately, choose `n`, then reboot
from the UI or with:

```bash
reboot
```

After reboot, confirm:

```bash
ssh root@$ROUTER 'command -v awg; uci -q show network | grep -i amnezia || true'
```

### Create the VPN Interface in LuCI

1. Open LuCI.
2. Go to `Network > Interfaces`.
3. Click `Add new interface`.
4. Name it `awg0`.
5. Select protocol `AmneziaWG VPN`.
6. Click `Create interface`.
7. If `AmneziaWG VPN` is missing, reboot once. If it is still missing, stop and
   inspect package compatibility.
8. Click `Load configuration`.
9. Paste or upload `/tmp/amnezia-router-pool.conf`.
10. Click `Import settings`.
11. In `Advanced Settings`, clear `Use default gateway`.
12. In `Firewall Settings`, create or assign a new zone named `awg`.
13. In `Peers`, edit the imported peer and enable `Route Allowed IPs`.
14. Save the peer and interface.
15. Edit the `wan` zone and set gateway metric to `100`.
16. Click `Save & Apply`.

### Firewall and Routing

For full-tunnel router mode:

1. Go to `Network > Firewall`.
2. Edit `lan`.
3. In `Allow forward to destination zones`, allow forwarding to `awg`.
4. Edit the `awg` zone.
5. Enable `Masquerading`.
6. Enable `MSS clamping`.
7. Save and apply.
8. Go to `Network > Routing`.
9. Add a route:

   ```text
   Interface: awg0
   Target: 0.0.0.0/0
   Metric: 20
   ```

10. Save and apply.

For selected-client mode, use the GL.iNet VPN policy UI if available, or set up
OpenWrt policy-based routing separately after the tunnel works. Do not start
with policy routing; first prove that one full-tunnel client works.

### Kill Switch

Enable a kill switch after the tunnel is proven working.

Preferred GL.iNet UI path:

```text
VPN > VPN Dashboard or VPN Client settings > Block Non-VPN Traffic / Kill Switch
```

If using raw OpenWrt firewall rules, create a LAN-to-WAN block that applies only
to the client group intended to use the VPN. Avoid blocking router-originated
traffic needed for DNS, NTP, package updates, and manifest fetches until the
refresh script is installed and tested.

## Router-Side Endpoint Refresh

This script makes the router query the manifest and update only the VPN peer
endpoint. It does not rotate Azure IPs. It only chooses among the currently
published active endpoints.

Use this only after the VPN profile is connected manually at least once.

Make sure the router can parse JSON and fetch HTTPS URLs:

```bash
ssh root@$ROUTER 'opkg update && opkg install jsonfilter ca-bundle'
```

If `jsonfilter` is already installed, `opkg` will leave it in place.

### Find the UCI Peer Section

On the router:

```bash
uci show network | sed -n "s/^network\.\([^.=]*\)\.endpoint_host=.*/\1/p"
```

For a single VPN peer, use the only returned value. For multiple peers, inspect:

```bash
uci show network | grep -Ei "endpoint_host|endpoint_port|public_key|amnezia|wireguard"
```

Record:

```text
Interface name: awg0
Peer section:   <value from UCI, for example cfg0f0a3c>
```

### Install Router Script

From the local machine:

```bash
ROUTER=192.168.8.1
ssh root@$ROUTER 'cat > /usr/bin/amnezia-endpoint-refresh << "EOF"
#!/bin/sh
set -eu

MANIFEST_URL="${MANIFEST_URL:-https://amneziamanifest13bd.blob.core.windows.net/manifest/endpoints.json}"
STATE_DIR="${STATE_DIR:-/etc/amnezia-endpoint}"
IFACE="${IFACE:-awg0}"
PEER_SECTION="${PEER_SECTION:-}"
STRATEGY="${STRATEGY:-round-robin}"
DEFAULT_PORT="${DEFAULT_PORT:-49895}"

log() {
    logger -t amnezia-endpoint "$*"
    echo "$*"
}

die() {
    log "error: $*"
    exit 1
}

fetch_manifest() {
    local output="$1"
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$output" "$MANIFEST_URL"
    else
        wget -q -O "$output" "$MANIFEST_URL"
    fi
}

[ -x /usr/bin/jsonfilter ] || die "jsonfilter is missing; install it with: opkg update && opkg install jsonfilter"

mkdir -p "$STATE_DIR"

if [ -z "$PEER_SECTION" ]; then
    PEER_SECTION="$(uci show network | sed -n "s/^network\.\([^.=]*\)\.endpoint_host=.*/\1/p" | head -n 1)"
fi

[ -n "$PEER_SECTION" ] || die "could not find network peer section with endpoint_host"

tmp="$(mktemp /tmp/amnezia-endpoints.XXXXXX)"
trap "rm -f \"$tmp\"" EXIT

fetch_manifest "$tmp" || die "failed to fetch manifest"

count="$(jsonfilter -i "$tmp" -e "@.vpn.active[*].public_ip" | wc -l | tr -d " ")"
[ "$count" -gt 0 ] 2>/dev/null || die "manifest has no active endpoints"

case "$STRATEGY" in
    first)
        index=0
        ;;
    random)
        index="$(awk -v count="$count" "BEGIN { srand(); print int(rand() * count) }")"
        ;;
    round-robin)
        last="$(cat "$STATE_DIR/index" 2>/dev/null || echo -1)"
        index=$(( (last + 1) % count ))
        ;;
    *)
        die "unsupported strategy: $STRATEGY"
        ;;
esac

host="$(jsonfilter -i "$tmp" -e "@.vpn.active[*].public_ip" | sed -n "$((index + 1))p")"
port="$(jsonfilter -i "$tmp" -e "@.vpn.active[$index].port" 2>/dev/null || true)"
[ -n "$host" ] || die "could not select endpoint host at index $index"
[ -n "$port" ] || port="$DEFAULT_PORT"

current_host="$(uci -q get "network.$PEER_SECTION.endpoint_host" || true)"
current_port="$(uci -q get "network.$PEER_SECTION.endpoint_port" || true)"

if [ "$current_host" = "$host" ] && [ "$current_port" = "$port" ]; then
    echo "$index" > "$STATE_DIR/index"
    log "endpoint unchanged: $host:$port"
    exit 0
fi

uci set "network.$PEER_SECTION.endpoint_host=$host"
uci set "network.$PEER_SECTION.endpoint_port=$port"
uci commit network
echo "$index" > "$STATE_DIR/index"
echo "$host:$port" > "$STATE_DIR/current"

log "endpoint changed: ${current_host:-none}:${current_port:-none} -> $host:$port on $PEER_SECTION"

ifdown "$IFACE" >/dev/null 2>&1 || true
sleep 2
ifup "$IFACE"
EOF
chmod 700 /usr/bin/amnezia-endpoint-refresh'
```

Run it once with explicit values:

```bash
ssh root@$ROUTER 'IFACE=awg0 PEER_SECTION=<peer-section> STRATEGY=first /usr/bin/amnezia-endpoint-refresh'
```

Then inspect:

```bash
ssh root@$ROUTER 'cat /etc/amnezia-endpoint/current; logread | grep amnezia-endpoint | tail -n 20'
ssh root@$ROUTER 'uci get network.<peer-section>.endpoint_host; uci get network.<peer-section>.endpoint_port'
```

### Schedule Manifest Refresh

Start conservative. A 15-minute client-side endpoint selection interval is
reasonable for testing. Do not rotate Azure public IPs on this schedule; Azure
rotation should happen only when endpoints are actually blocked.

```bash
ssh root@$ROUTER 'grep -q amnezia-endpoint-refresh /etc/crontabs/root || {
  echo "*/15 * * * * IFACE=awg0 PEER_SECTION=<peer-section> STRATEGY=round-robin /usr/bin/amnezia-endpoint-refresh >/tmp/amnezia-endpoint-refresh.log 2>&1" >> /etc/crontabs/root
}
/etc/init.d/cron restart'
```

If the router has very limited flash or CPU, increase the interval to 30 or 60
minutes after testing.

## Local Host Assisted Endpoint Update

If you do not want the router to run the manifest script, the local machine can
select an endpoint and push it over SSH:

```bash
cd /home/brett/projects/workBenches
ROUTER=192.168.8.1
IFACE=awg0
PEER_SECTION=<peer-section>
ENDPOINT="$(scripts/amnezia-endpoint select --strategy round-robin)"
HOST="${ENDPOINT%:*}"
PORT="${ENDPOINT##*:}"

ssh root@$ROUTER "uci set network.$PEER_SECTION.endpoint_host='$HOST'; \
uci set network.$PEER_SECTION.endpoint_port='$PORT'; \
uci commit network; \
ifdown '$IFACE' >/dev/null 2>&1 || true; sleep 2; ifup '$IFACE'"
```

This is useful for manual recovery when a current endpoint appears blocked.

## Verification

Run these after the tunnel starts:

```bash
ssh root@$ROUTER 'ifstatus awg0'
ssh root@$ROUTER 'command -v awg >/dev/null 2>&1 && awg show || wg show'
ssh root@$ROUTER 'ip route get 1.1.1.1'
ssh root@$ROUTER 'logread | grep -Ei "amnezia|awg|wireguard" | tail -n 50'
```

From a client connected to the router LAN:

```bash
curl -4 https://ifconfig.me
curl -4 https://icanhazip.com
```

Expected:

- The router has a recent AmneziaWG/WireGuard handshake.
- The selected endpoint is one of the manifest secondary IPs.
- Client public IP reflects the VPN path, not the local ISP path.
- The primary management IP `20.237.172.123` is not used as the VPN endpoint.

## Failure Handling

If one endpoint stops working:

```bash
ssh root@$ROUTER 'IFACE=awg0 PEER_SECTION=<peer-section> STRATEGY=round-robin /usr/bin/amnezia-endpoint-refresh'
```

If several endpoints fail from the local network, report the blocked public IPs
back to cloudBench and rotate those Azure public IP resources with:

```bash
cd /home/brett/projects/workBenches/sysBenches/cloudBench
./scripts/amnezia-ip-pool.sh rotate <public-ip-or-resource-name>
```

Then the router-side script will pick up the new manifest on its next run.

## Rollback

Before changing router config:

```bash
ssh root@$ROUTER 'cp /etc/config/network /etc/config/network.before-amnezia; cp /etc/config/firewall /etc/config/firewall.before-amnezia; cp /etc/crontabs/root /etc/crontabs/root.before-amnezia 2>/dev/null || true'
```

To disable endpoint refresh:

```bash
ssh root@$ROUTER 'sed -i "/amnezia-endpoint-refresh/d" /etc/crontabs/root; /etc/init.d/cron restart'
```

To stop the tunnel:

```bash
ssh root@$ROUTER 'ifdown awg0'
```

To restore saved network/firewall config:

```bash
ssh root@$ROUTER 'cp /etc/config/network.before-amnezia /etc/config/network; cp /etc/config/firewall.before-amnezia /etc/config/firewall; /etc/init.d/network reload; /etc/init.d/firewall reload'
```

## Notes for Local Codex

- Do not assume the GL.iNet UI profile is UCI-managed. Inspect before patching.
- Prefer LuCI/OpenWrt-managed `awg0` if endpoint automation is required.
- Keep the VPN private key and pre-shared key out of the repo and out of cloud
  prompts.
- Do not use or rotate the primary management IP.
- Do not configure daily Azure IP release/recreate jobs on the router. The
  router should only select from the manifest; cloudBench owns Azure rotation.
- Changing the router endpoint changes the VPN transport endpoint. It does not
  create per-destination routing inside the tunnel. Use GL.iNet VPN policies or
  OpenWrt policy-based routing later if only some clients or destinations should
  use the VPN.

## References

- GL.iNet LuCI access: https://docs.gl-inet.com/router/en/4/faq/what_is_luci/
- GL.iNet WireGuard client import: https://docs.gl-inet.com/router/en/4/interface_guide/wireguard_client/
- GL.iNet AmneziaWG obfuscation: https://docs.gl-inet.com/router/en/4/tutorials/vpn_obfuscation/
- Amnezia OpenWrt router guide: https://docs.amnezia.org/documentation/instructions/openwrt-os-awg/
- AmneziaWG OpenWrt packages: https://github.com/amnezia-vpn/amneziawg-openwrt
