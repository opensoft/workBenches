# Amnezia Server Endpoint Pool Runbook

This document describes the Azure Amnezia VPN server endpoint pool and where the
server-local operational notes live.

Server-local canonical path:

```text
/opt/opensoft/amnezia-endpoint-pool/README.md
```

Discoverability link:

```text
/opt/amnezia/OPENSOFT-ENDPOINT-POOL.md -> /opt/opensoft/amnezia-endpoint-pool/README.md
```

This path is intentionally outside `/opt/amnezia` because `/opt/amnezia` is
owned by the Amnezia installation/runtime. The symlink makes the runbook visible
to someone inspecting Amnezia files, while the real document stays under the
Opensoft-owned operations namespace.

Do not store VPN private keys, pre-shared keys, client configs, or router/admin
credentials in this document.

## Current Server

Last verified: `2026-06-20T04:51Z`

```text
Azure resource group: amnezia
Azure VM:             amnezia
Azure NIC:            amnezia453
OS:                   Ubuntu 24.04 LTS on Azure
Management public IP: 20.237.172.123
Management private IP: 10.0.0.4
VPN protocol:         AmneziaWG over UDP
VPN port:             49895
Container:            amnezia-awg2
Manifest URL:         https://amneziamanifest13bd.blob.core.windows.net/manifest/endpoints.json
```

Management IP policy:

- `20.237.172.123` / `10.0.0.4` is for SSH management only.
- UDP VPN traffic to the management IP is intentionally blocked.
- Client/router VPN profiles must use the secondary endpoint pool only.

## Current Endpoint Pool

These are the public endpoints published to clients and attached to the VM as
secondary private IPs:

| Azure resource | NIC slot | Public IP | Private IP | Protocol |
|---|---|---:|---:|---|
| `amnezia-ip-02` | `ipconfig2` | `104.42.170.151` | `10.0.0.5` | `udp/49895` |
| `amnezia-ip-03` | `ipconfig3` | `52.190.183.33` | `10.0.0.6` | `udp/49895` |
| `amnezia-ip-04` | `ipconfig4` | `168.62.193.27` | `10.0.0.7` | `udp/49895` |
| `amnezia-ip-05` | `ipconfig5` | `20.237.253.33` | `10.0.0.8` | `udp/49895` |
| `amnezia-ip-06` | `ipconfig6` | `20.245.30.72` | `10.0.0.9` | `udp/49895` |
| `amnezia-ip-07` | `ipconfig7` | `52.225.50.143` | `10.0.0.10` | `udp/49895` |
| `amnezia-ip-08` | `ipconfig8` | `172.184.248.90` | `10.0.0.11` | `udp/49895` |
| `amnezia-ip-09` | `ipconfig9` | `104.42.157.74` | `10.0.0.12` | `udp/49895` |
| `amnezia-ip-10` | `ipconfig10` | `20.253.218.4` | `10.0.0.13` | `udp/49895` |
| `amnezia-ip-11` | `ipconfig11` | `52.160.150.174` | `10.0.0.14` | `udp/49895` |

The VM persists the secondary private IP addresses with:

```text
/etc/netplan/60-amnezia-secondary-ips.yaml
```

The server enables IPv4 forwarding with:

```text
/etc/sysctl.d/99-amnezia-forwarding.conf
```

## Security Rules

Expected NSG behavior:

| Rule | Expected behavior |
|---|---|
| `SSH` | Allows TCP `22` to `10.0.0.4` only |
| `Deny_Primary_NonSSH` | Denies all non-SSH inbound traffic to `10.0.0.4` |
| `Allow_UDP_traffic` | Allows UDP traffic to secondary VPN endpoints |

As of `2026-06-20`, Network Watcher confirmed:

- `10.0.0.4:49895/udp` is denied by `Deny_Primary_NonSSH`.
- `10.0.0.5` through `10.0.0.14` are allowed on `49895/udp`.
- UDP probes to all ten public secondary IPs arrived on the VM as the expected
  private IPs.

## Safe Verification Commands

Run these from `cloud-bench`.

Azure context:

```bash
az account show --query '{name:name,id:id,user:user.name}' -o json
az network public-ip list -g amnezia \
  --query '[].{name:name,ip:ipAddress,attached:ipConfiguration.id}' -o table
az network nic ip-config list -g amnezia --nic-name amnezia453 \
  --query '[].{slot:name,primary:primary,private:privateIPAddress,public:publicIPAddress.id}' -o table
```

Manifest:

```bash
curl -fsS https://amneziamanifest13bd.blob.core.windows.net/manifest/endpoints.json \
  | jq '{schema,version,generated_at,management:.management.public_ip,active_count:(.vpn.active|length)}'
```

Server OS and container:

```bash
ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'hostname; ip -4 -brief addr show dev eth0'

ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"'

ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'sudo ss -lunp | grep :49895 || true'
```

AmneziaWG status without dumping keys:

```bash
ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'sudo docker exec amnezia-awg2 awg show awg0 listen-port'

ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'sudo docker exec amnezia-awg2 awg show awg0 peers | wc -l'

ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'sudo docker exec amnezia-awg2 awg show awg0 latest-handshakes' \
  | awk '{total++; if ($2 > 0) active++} END {printf "peers=%d peers_with_handshake=%d\n", total+0, active+0}'
```

Do not paste full `awg show` or Amnezia config output into tickets or chat; it
can expose peer public keys and operational details.

## Packet Delivery Test

This proves Azure is delivering UDP packets sent to each public secondary IP to
the VM.

Start capture on the server:

```bash
ssh -i ~/.ssh/amnezia_key.pem amnezia@20.237.172.123 \
  'sudo timeout 20 tcpdump -nn -i eth0 udp port 49895 -c 20'
```

In another shell inside `cloud-bench`, send probes:

```bash
for ip in \
  104.42.170.151 52.190.183.33 168.62.193.27 20.237.253.33 20.245.30.72 \
  52.225.50.143 172.184.248.90 104.42.157.74 20.253.218.4 52.160.150.174
do
  printf 'probe-%s' "$ip" | nc -u -w1 "$ip" 49895 || true
done
```

Expected capture destinations:

```text
10.0.0.5:49895
10.0.0.6:49895
10.0.0.7:49895
10.0.0.8:49895
10.0.0.9:49895
10.0.0.10:49895
10.0.0.11:49895
10.0.0.12:49895
10.0.0.13:49895
10.0.0.14:49895
```

This does not prove a client has a valid VPN handshake. It proves ingress and
NAT delivery to the server.

## Rotation and Manifest Management

Azure IP rotation is owned by `cloudBench`, not by the VPN server and not by the
router.

Tooling path in the repo:

```text
/home/brett/projects/workBenches/sysBenches/cloudBench/scripts/amnezia-ip-pool.sh
```

Publish the current attached secondary IPs:

```bash
cd /home/brett/projects/workBenches/sysBenches/cloudBench
./scripts/amnezia-ip-pool.sh publish
```

Rotate only endpoints that clients report as blocked:

```bash
cd /home/brett/projects/workBenches/sysBenches/cloudBench
./scripts/amnezia-ip-pool.sh rotate amnezia-ip-05
./scripts/amnezia-ip-pool.sh rotate 20.237.253.33
```

The script refuses to rotate the management public IP `amnezia-ip`.

Do not create daily Azure release/recreate jobs on the server. Keep endpoint
rotation event-driven so clients refresh from the manifest only when needed.

## Client and Router Documentation

Repo documents:

```text
/home/brett/projects/workBenches/docs/amnezia-endpoint-wrapper.md
/home/brett/projects/workBenches/docs/glinet-luci-amnezia-router.md
/home/brett/projects/workBenches/docs/amnezia-server-runbook.md
```

Host-side endpoint helper:

```text
/home/brett/projects/workBenches/scripts/amnezia-endpoint
```

Router/local clients should query the manifest and choose from the ten secondary
public IPs. They should not use the primary management IP as a VPN endpoint.

## If Something Looks Wrong

1. Confirm Azure says the public IP is attached to the expected NIC ipconfig.
2. Confirm the VM owns the matching private IP on `eth0`.
3. Confirm NSG flow allows `udp/49895` to the secondary private IP.
4. Confirm Docker publishes `0.0.0.0:49895->49895/udp`.
5. Confirm UDP probes arrive with `tcpdump`.
6. Confirm a real client has a recent AmneziaWG handshake.
7. If only one or two public IPs fail from client locations, rotate only those
   public IP resources from `cloudBench` and republish the manifest.
