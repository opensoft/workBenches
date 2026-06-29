#!/usr/bin/env bash
set -euo pipefail

# Run this inside cloudBench. It creates one portable DR backup set per
# nopCommerce namespace in the FarHeap QA AKS cluster.

SOURCE_SUBSCRIPTION_ID="${SOURCE_SUBSCRIPTION_ID:-cd84dddc-e6f0-45a1-b5da-e700ae550a74}"
SOURCE_TENANT_ID="${SOURCE_TENANT_ID:-96d3fa6b-5547-49ca-9af1-dba9bec50c2b}"
SOURCE_RESOURCE_GROUP="${SOURCE_RESOURCE_GROUP:-aks-davincisite-qa}"
SOURCE_CLUSTER="${SOURCE_CLUSTER:-aks-davincisite-qa}"
SOURCE_REGION="${SOURCE_REGION:-westus}"

BACKUP_SUBSCRIPTION_ID="${BACKUP_SUBSCRIPTION_ID:-38854b62-a74e-406d-9a7d-c9aaa3549db2}"
BACKUP_RESOURCE_GROUP="${BACKUP_RESOURCE_GROUP:-AKS-Backups}"
BACKUP_STORAGE_ACCOUNT="${BACKUP_STORAGE_ACCOUNT:-bknopcomdrqa}"
BACKUP_CONTAINER="${BACKUP_CONTAINER:-nopcommerce-dr}"
BACKUP_ENVIRONMENT="${BACKUP_ENVIRONMENT:-farheap-qa}"
BACKUP_BASE_PREFIX="${BACKUP_BASE_PREFIX:-backups/nopcommerce/${BACKUP_ENVIRONMENT}}"

NFS_RESOURCE_GROUP="${NFS_RESOURCE_GROUP:-aks-davincisite-qa}"
NFS_STORAGE_ACCOUNT="${NFS_STORAGE_ACCOUNT:-aksdavincisiteqa}"
NFS_SHARE="${NFS_SHARE:-gps-qa}"
NFS_SERVER="${NFS_SERVER:-${NFS_STORAGE_ACCOUNT}.file.core.windows.net}"

BATCH_ID="${BATCH_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
LOCAL_ROOT="${LOCAL_ROOT:-/tmp/nopcommerce-full-backup-${BATCH_ID}}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/tmp/kube-${SOURCE_CLUSTER}-admin}"
ARCHIVE_IMAGE="${ARCHIVE_IMAGE:-ubuntu:24.04}"
SQL_RUNNER_NAMESPACE="${SQL_RUNNER_NAMESPACE:-nopcommerce-backup}"
SQL_RUNNER_POD="${SQL_RUNNER_POD:-sqlpackage-runner}"
SQL_RUNNER_IMAGE="${SQL_RUNNER_IMAGE:-ubuntu:24.04}"
SQL_RUNNER_WORKDIR="${SQL_RUNNER_WORKDIR:-/work}"
SQL_EXPORT_TIMEOUT_SECONDS="${SQL_EXPORT_TIMEOUT_SECONDS:-7200}"
SKIP_SQL_RUNNER_PREP="${SKIP_SQL_RUNNER_PREP:-0}"
SITE_FILTER="${SITE_FILTER:-}"
SITES_JSON_SOURCE="${SITES_JSON_SOURCE:-}"

SCRIPT_VERSION="2026-06-24.full-iterative-v1"
CURRENT_SITE_JSON=""

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cloudbench() {
  command -v kubectl >/dev/null || die "kubectl not found"
  command -v helm >/dev/null || die "helm not found"
  command -v jq >/dev/null || die "jq not found"
  command -v zstd >/dev/null || die "zstd not found"
  command -v sha256sum >/dev/null || die "sha256sum not found"
  command -v azcopy >/dev/null || die "azcopy not found"
  test -x /opt/sqlpackage/sqlpackage || die "/opt/sqlpackage/sqlpackage not found"
  test -f /tmp/azfixed.py || die "/tmp/azfixed.py not found; run from cloudBench"
}

setup_az() {
  local user_site
  user_site=$(/opt/az/bin/python3 -c "import site; print(site.getusersitepackages())")
  export PYTHONPATH="${user_site}:/opt/az/lib/python3.13/site-packages"
  export AZ_INSTALLER=PIP
  export HTTP_PROXY="${HTTP_PROXY:-http://host.docker.internal:17891}"
  export HTTPS_PROXY="${HTTPS_PROXY:-http://host.docker.internal:17891}"
  export NO_PROXY="${NO_PROXY:-.database.windows.net,.file.core.windows.net,10.0.0.0/8,127.0.0.1,localhost}"
  export http_proxy="$HTTP_PROXY"
  export https_proxy="$HTTPS_PROXY"
  export no_proxy="$NO_PROXY"
  AZ=(/opt/az/bin/python3 /tmp/azfixed.py)
}

install_kubectl_retry_wrapper() {
  local real wrapper
  real=$(command -v kubectl)
  mkdir -p "${LOCAL_ROOT}/bin"
  wrapper="${LOCAL_ROOT}/bin/kubectl"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
real="${real}"
max="\${KUBECTL_RETRIES:-10}"
delay="\${KUBECTL_RETRY_DELAY_SECONDS:-3}"
call_timeout="\${KUBECTL_CALL_TIMEOUT_SECONDS:-45}"
attempt=1
while true; do
  output=\$(timeout "\$call_timeout" "\$real" "\$@" 2>&1)
  rc=\$?
  if [ "\$rc" -eq 0 ]; then
    printf '%s' "\$output"
    if [ -n "\$output" ]; then
      printf '\n'
    fi
    exit 0
  fi
  if [ "\$attempt" -ge "\$max" ]; then
    printf '%s\n' "\$output" >&2
    exit "\$rc"
  fi
  sleep \$((delay * attempt))
  attempt=\$((attempt + 1))
done
EOF
  chmod +x "$wrapper"
  export PATH="${LOCAL_ROOT}/bin:${PATH}"
}

az_set_subscription() {
  "${AZ[@]}" account set --subscription "$1" >/dev/null
}

sanitize_json() {
  python3 -c '
import json
import re
import sys

secret_key = re.compile(r"(password|passwd|pwd|secret|token|key|connectionstring|connection_string)", re.I)
conn_secret = re.compile(r"(?i)(Password|Pwd|User ID|UID|AccountKey|SharedAccessSignature)=([^;]+)")

def clean(value, key=""):
    if isinstance(value, dict):
        return {k: clean(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [clean(v, key) for v in value]
    if isinstance(value, str):
        if secret_key.search(key):
            return "REDACTED"
        if "Password=" in value or "Pwd=" in value or "User ID=" in value or "AccountKey=" in value:
            return conn_secret.sub(lambda m: f"{m.group(1)}=REDACTED", value)
        return value
    return value

data = json.load(sys.stdin)
json.dump(clean(data), sys.stdout, indent=2)
sys.stdout.write("\n")
'
}

discover_sites() {
  log "Discovering nopCommerce namespaces in ${SOURCE_CLUSTER}"
  if [ -n "$SITES_JSON_SOURCE" ]; then
    [ -f "$SITES_JSON_SOURCE" ] || die "SITES_JSON_SOURCE not found: ${SITES_JSON_SOURCE}"
    if [ -n "$SITE_FILTER" ]; then
      jq --arg filter "$SITE_FILTER" '
        ($filter | split(",") | map(select(length > 0))) as $wanted
        | map(select(.namespace as $ns | $wanted | index($ns)))
      ' "$SITES_JSON_SOURCE" > "${LOCAL_ROOT}/sites.json"
    else
      cp "$SITES_JSON_SOURCE" "${LOCAL_ROOT}/sites.json"
    fi
    jq -r '.[] | [.namespace, .deployment, .image, .database.database, (.hosts | join(","))] | @tsv' "${LOCAL_ROOT}/sites.json"
    return 0
  fi

  python3 - "$SITE_FILTER" <<'PY' > "${LOCAL_ROOT}/sites.json"
import json
import subprocess
import sys

site_filter = {x.strip() for x in sys.argv[1].split(",") if x.strip()}

def kjson(args):
    return json.loads(subprocess.check_output(["kubectl", *args], text=True))

def helm_json(args):
    try:
        return json.loads(subprocess.check_output(["helm", *args], text=True))
    except Exception:
        return []

def conn_parts(conn):
    out = {}
    for part in (conn or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip().lower()] = v.strip()
    return {
        "server": out.get("data source") or out.get("server") or "",
        "database": out.get("initial catalog") or out.get("database") or "",
        "user": out.get("user id") or out.get("uid") or "",
    }

deploys = kjson(["get", "deploy", "-A", "-o", "json"])["items"]
ingresses = kjson(["get", "ingress", "-A", "-o", "json"])["items"]
pvcs = kjson(["get", "pvc", "-A", "-o", "json"])["items"]
pvs = {pv["metadata"]["name"]: pv for pv in kjson(["get", "pv", "-o", "json"])["items"]}
helm_releases = helm_json(["list", "-A", "-o", "json"])
release_by_ns = {}
for rel in helm_releases:
    release_by_ns.setdefault(rel.get("namespace"), rel)

sites = []
for deploy in deploys:
    namespace = deploy["metadata"]["namespace"]
    containers = deploy.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    if not containers:
        continue
    image = containers[0].get("image", "")
    if "nopcommerce" not in image.lower():
        continue
    if site_filter and namespace not in site_filter:
        continue

    env = containers[0].get("env", [])
    conn = next((e.get("value", "") for e in env if e.get("name") == "ConnectionStrings__ConnectionString"), "")
    db = conn_parts(conn)
    ns_ingresses = [i for i in ingresses if i["metadata"].get("namespace") == namespace]
    hosts = []
    ingress_names = []
    for ing in ns_ingresses:
        ingress_names.append(ing["metadata"]["name"])
        for rule in ing.get("spec", {}).get("rules", []) or []:
            if rule.get("host"):
                hosts.append(rule["host"])

    ns_pvcs = [p for p in pvcs if p["metadata"].get("namespace") == namespace]
    pvc_records = []
    for pvc in ns_pvcs:
        volume = pvc.get("spec", {}).get("volumeName")
        pv = pvs.get(volume, {})
        nfs = pv.get("spec", {}).get("nfs", {})
        if nfs:
            pvc_records.append({
                "name": pvc["metadata"]["name"],
                "volume": volume,
                "nfsServer": nfs.get("server", ""),
                "nfsPath": nfs.get("path", ""),
                "mountOptions": pv.get("spec", {}).get("mountOptions", []),
            })

    release = release_by_ns.get(namespace, {})
    sites.append({
        "namespace": namespace,
        "site": namespace,
        "helmRelease": release.get("name", namespace),
        "chart": release.get("chart", ""),
        "appVersion": release.get("app_version", ""),
        "deployment": deploy["metadata"]["name"],
        "replicas": deploy.get("spec", {}).get("replicas", 1),
        "strategy": deploy.get("spec", {}).get("strategy", {}).get("type", ""),
        "image": image,
        "database": db,
        "ingresses": ingress_names,
        "hosts": sorted(set(hosts)),
        "primaryHost": sorted(set(hosts))[0] if hosts else "",
        "pvcs": pvc_records,
    })

print(json.dumps(sorted(sites, key=lambda x: x["namespace"]), indent=2))
PY
  jq -r '.[] | [.namespace, .deployment, .image, .database.database, (.hosts | join(","))] | @tsv' "${LOCAL_ROOT}/sites.json"
}

normalize_connection_string() {
  local conn="$1"
  case "$conn" in
    *Encrypt=*|*encrypt=*) ;;
    *) conn="${conn};Encrypt=True" ;;
  esac
  case "$conn" in
    *TrustServerCertificate=*|*trustservercertificate=*) ;;
    *) conn="${conn};TrustServerCertificate=False" ;;
  esac
  printf '%s' "$conn"
}

prepare_sql_runner() {
  local phase
  if [ "$SKIP_SQL_RUNNER_PREP" = "1" ]; then
    log "Skipping SQL runner preparation by request"
    return 0
  fi

  log "Preparing in-cluster SQL export runner ${SQL_RUNNER_NAMESPACE}/${SQL_RUNNER_POD}"
  kubectl get ns "$SQL_RUNNER_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$SQL_RUNNER_NAMESPACE" >/dev/null

  phase=$(kubectl -n "$SQL_RUNNER_NAMESPACE" get pod "$SQL_RUNNER_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$phase" != "Running" ]; then
    kubectl -n "$SQL_RUNNER_NAMESPACE" delete pod "$SQL_RUNNER_POD" --ignore-not-found --wait=true >/dev/null 2>&1 || true
    cat <<EOF | kubectl -n "$SQL_RUNNER_NAMESPACE" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${SQL_RUNNER_POD}
  labels:
    app: nopcommerce-sqlpackage-runner
spec:
  restartPolicy: Never
  containers:
  - name: runner
    image: ${SQL_RUNNER_IMAGE}
    command: ["bash", "-lc", "sleep 86400"]
    volumeMounts:
    - name: work
      mountPath: ${SQL_RUNNER_WORKDIR}
  volumes:
  - name: work
    emptyDir: {}
EOF
  fi

  kubectl -n "$SQL_RUNNER_NAMESPACE" wait --for=condition=Ready "pod/${SQL_RUNNER_POD}" --timeout=180s >/dev/null
  if ! kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- test -x /opt/sqlpackage/sqlpackage >/dev/null 2>&1; then
    log "Copying sqlpackage into ${SQL_RUNNER_NAMESPACE}/${SQL_RUNNER_POD}"
    kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- bash -lc 'rm -rf /opt/sqlpackage && mkdir -p /opt "$1"' _ "$SQL_RUNNER_WORKDIR"
    tar -C /opt -czf - sqlpackage | kubectl -n "$SQL_RUNNER_NAMESPACE" exec -i "$SQL_RUNNER_POD" -- tar -C /opt -xzf -
  fi

  if ! kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- test -x /usr/local/bin/azcopy >/dev/null 2>&1; then
    log "Copying azcopy into ${SQL_RUNNER_NAMESPACE}/${SQL_RUNNER_POD}"
    kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- mkdir -p /usr/local/bin
    tar -C /usr/local/bin -czf - azcopy | kubectl -n "$SQL_RUNNER_NAMESPACE" exec -i "$SQL_RUNNER_POD" -- tar -C /usr/local/bin -xzf -
  fi

  if ! kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- \
    bash -lc '/opt/sqlpackage/sqlpackage /Version >/dev/null 2>&1'; then
    log "Installing ICU runtime in ${SQL_RUNNER_NAMESPACE}/${SQL_RUNNER_POD}"
    kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- bash -lc \
      'apt-get update >/tmp/sqlpackage-runner-apt-update.log && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libicu74 ca-certificates >/tmp/sqlpackage-runner-apt-install.log'
  fi

  kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- \
    bash -lc '/opt/sqlpackage/sqlpackage /Version >/dev/null'
  kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- \
    bash -lc '/usr/local/bin/azcopy --version >/dev/null'
}

upload_pod_file() {
  local pod_namespace="$1"
  local pod_name="$2"
  local remote_file="$3"
  local blob="$4"
  local upload_log="$5"

  if [ -z "${BACKUP_SAS_TOKEN:-}" ]; then
    die "BACKUP_SAS_TOKEN is not set"
  fi

  if ! printf '%s\n' "$BACKUP_SAS_TOKEN" | kubectl -n "$pod_namespace" exec -i "$pod_name" -- bash -lc '
set -euo pipefail
remote_file="$1"
account="$2"
container="$3"
blob="$4"
IFS= read -r sas_token
url="https://${account}.blob.core.windows.net/${container}/${blob}?${sas_token}"
mkdir -p /tmp/azcopy-logs /tmp/azcopy-plans
printf "upload_start_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AZCOPY_LOG_LOCATION=/tmp/azcopy-logs \
AZCOPY_JOB_PLAN_LOCATION=/tmp/azcopy-plans \
AZCOPY_CONCURRENCY_VALUE="${AZCOPY_CONCURRENCY_VALUE:-16}" \
  /usr/local/bin/azcopy copy "$remote_file" "$url" --overwrite=false --check-length=true --log-level=ERROR
printf "upload_finish_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
' _ "$remote_file" "$BACKUP_STORAGE_ACCOUNT" "$BACKUP_CONTAINER" "$blob" > "$upload_log" 2>&1; then
    return 1
  fi
}

upload_runner_file() {
  local remote_file="$1"
  local blob="$2"
  local upload_log="$3"

  upload_pod_file "$SQL_RUNNER_NAMESPACE" "$SQL_RUNNER_POD" "$remote_file" "$blob" "$upload_log"
}

export_sql_in_runner() {
  local namespace="$1"
  local conn="$2"
  local prefix="$3"
  local site_dir="$4"
  local runner_dir="${SQL_RUNNER_WORKDIR}/${namespace}-${BATCH_ID}"
  local remote_target="${runner_dir}/database.bacpac"
  local remote_log="${runner_dir}/sql-export.log"
  local remote_meta="${runner_dir}/database.bacpac.meta.json"
  local remote_status="${runner_dir}/status"
  local db_sha db_bytes elapsed status

  if ! printf '%s\n' "$conn" | kubectl -n "$SQL_RUNNER_NAMESPACE" exec -i "$SQL_RUNNER_POD" -- bash -lc '
set -euo pipefail
runner_dir="$1"
rm -rf "$runner_dir"
mkdir -p "$runner_dir"
cat > "${runner_dir}/connection.txt"
' _ "$runner_dir"; then
    return 1
  fi

  if ! kubectl -n "$SQL_RUNNER_NAMESPACE" exec -i "$SQL_RUNNER_POD" -- bash -lc 'cat > "$1/export-job.sh" && chmod +x "$1/export-job.sh"' _ "$runner_dir" <<'SQL_EXPORT_JOB'
#!/usr/bin/env bash
set -euo pipefail
runner_dir="$1"
target="${runner_dir}/database.bacpac"
log_file="${runner_dir}/sql-export.log"
meta_file="${runner_dir}/database.bacpac.meta.json"
status_file="${runner_dir}/status"
conn_file="${runner_dir}/connection.txt"
rm -f "$target" "$meta_file" "$status_file"
if {
  printf "sql_export_start_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sql_conn=$(cat "$conn_file")
  /opt/sqlpackage/sqlpackage \
    /Action:Export \
    "/SourceConnectionString:${sql_conn}" \
    "/TargetFile:${target}"
  printf "sql_export_finish_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log_file" 2>&1; then
  test -s "$target"
  sha="$(sha256sum "$target" | awk "{print \$1}")"
  bytes="$(stat -c "%s" "$target")"
  printf "{\"artifact\":\"database.bacpac\",\"bytes\":%s,\"sha256\":\"%s\"}\n" "$bytes" "$sha" > "$meta_file"
  rm -f "$conn_file"
  printf complete > "$status_file"
else
  rc=$?
  rm -f "$conn_file"
  printf failed > "$status_file"
  exit "$rc"
fi
SQL_EXPORT_JOB
  then
    return 1
  fi

  kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- bash -lc 'nohup "$1/export-job.sh" "$1" >/dev/null 2>&1 & echo $! > "$1/pid"' _ "$runner_dir" || return 1

  elapsed=0
  while true; do
    status=$(kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- bash -lc 'cat "$1" 2>/dev/null || true' _ "$remote_status" 2>/dev/null || true)
    case "$status" in
      complete)
        break
        ;;
      failed)
        kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- cat "$remote_log" > "${site_dir}/sql-export.log" 2>/dev/null || true
        return 1
        ;;
    esac
    if [ "$elapsed" -ge "$SQL_EXPORT_TIMEOUT_SECONDS" ]; then
      kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- cat "$remote_log" > "${site_dir}/sql-export.log" 2>/dev/null || true
      return 1
    fi
    sleep 15
    elapsed=$((elapsed + 15))
  done

  kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- cat "$remote_log" > "${site_dir}/sql-export.log" || return 1
  kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- cat "$remote_meta" > "${site_dir}/database.bacpac.meta.json" || return 1
  db_sha=$(jq -r .sha256 "${site_dir}/database.bacpac.meta.json")
  db_bytes=$(jq -r .bytes "${site_dir}/database.bacpac.meta.json")
  printf '%s  database.bacpac\n' "$db_sha" > "${site_dir}/database.bacpac.sha256"
  printf '%s\n' "$db_bytes" > "${site_dir}/database.bacpac.bytes"
  upload_runner_file "$remote_target" "${prefix}/database.bacpac" "${site_dir}/sql-upload.log" || return 1
  kubectl -n "$SQL_RUNNER_NAMESPACE" exec "$SQL_RUNNER_POD" -- rm -rf "$runner_dir" >/dev/null 2>&1 || true
}

wait_deploy_ready_replicas() {
  local namespace="$1"
  local deployment="$2"
  local desired="$3"
  local timeout="${4:-420}"
  local elapsed=0
  local ready
  while true; do
    ready=$(kubectl -n "$namespace" get deploy "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    ready="${ready:-0}"
    if [ "$ready" = "$desired" ]; then
      return 0
    fi
    if [ "$elapsed" -ge "$timeout" ]; then
      log "Timed out waiting for ${namespace}/${deployment} readyReplicas=${desired}; last ready=${ready}"
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

blob_exists() {
  local blob="$1"
  "${AZ[@]}" storage blob exists \
    --account-name "$BACKUP_STORAGE_ACCOUNT" \
    --account-key "$BACKUP_ACCOUNT_KEY" \
    --container-name "$BACKUP_CONTAINER" \
    --name "$blob" \
    --query exists -o tsv
}

upload_file() {
  local file="$1"
  local blob="$2"
  "${AZ[@]}" storage blob upload \
    --account-name "$BACKUP_STORAGE_ACCOUNT" \
    --account-key "$BACKUP_ACCOUNT_KEY" \
    --container-name "$BACKUP_CONTAINER" \
    --name "$blob" \
    --file "$file" \
    --overwrite false \
    --no-progress \
    --only-show-errors >/dev/null
}

upload_site_dir() {
  local site_dir="$1"
  local prefix="$2"
  local file
  for file in manifest.json helm-values.redacted.json k8s-inventory.json sql-export.log sql-upload.log database.bacpac.meta.json database.bacpac.sha256 database.bacpac.bytes file-archive.log file-upload.log files.tar.zst.meta.json files.tar.zst.sha256 files.tar.zst.bytes cold-backup.log smoke-test.txt sha256.txt; do
    if [ -f "${site_dir}/${file}" ]; then
      upload_file "${site_dir}/${file}" "${prefix}/${file}"
    fi
  done
  upload_file "${site_dir}/complete.json" "${prefix}/complete.json"
}

write_inventory() {
  local namespace="$1"
  local deployment="$2"
  local site_dir="$3"
  local pv_name
  pv_name=$(kubectl -n "$namespace" get pvc -o jsonpath='{.items[0].spec.volumeName}' 2>/dev/null || true)

  {
    printf '{\n'
    printf '"deployment":'
    kubectl -n "$namespace" get deploy "$deployment" -o json | sanitize_json
    printf ',\n"serviceList":'
    kubectl -n "$namespace" get svc -o json | sanitize_json
    printf ',\n"ingressList":'
    kubectl -n "$namespace" get ingress -o json | sanitize_json
    printf ',\n"pvcList":'
    kubectl -n "$namespace" get pvc -o json | sanitize_json
    printf ',\n"configMaps":'
    kubectl -n "$namespace" get configmap -o json | sanitize_json
    if [ -n "$pv_name" ]; then
      printf ',\n"pv":'
      kubectl get pv "$pv_name" -o json | sanitize_json
    fi
    printf '\n}\n'
  } > "${site_dir}/k8s-inventory.json"
}

write_helm_values() {
  local namespace="$1"
  local release="$2"
  local site_dir="$3"
  if helm -n "$namespace" get values "$release" -o json >/tmp/helm-values.$$ 2>/dev/null; then
    sanitize_json < /tmp/helm-values.$$ > "${site_dir}/helm-values.redacted.json"
  else
    printf '{}\n' > "${site_dir}/helm-values.redacted.json"
  fi
  rm -f /tmp/helm-values.$$
}

archive_pvc() {
  local namespace="$1"
  local pvc="$2"
  local prefix="$3"
  local site_dir="$4"
  local pod="backup-archive-${pvc//[^a-zA-Z0-9-]/-}"
  pod="${pod:0:55}"
  local remote_archive="/work/files.tar.zst"
  local remote_meta="/work/files.tar.zst.meta.json"

  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  cat <<EOF | kubectl -n "$namespace" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
  labels:
    app: nopcommerce-backup-archive
spec:
  restartPolicy: Never
  containers:
  - name: archive
    image: ${ARCHIVE_IMAGE}
    command: ["bash", "-lc", "sleep 3600"]
    volumeMounts:
    - name: site
      mountPath: /mnt/site
    - name: work
      mountPath: /work
  volumes:
  - name: site
    persistentVolumeClaim:
      claimName: ${pvc}
  - name: work
    emptyDir: {}
EOF
  kubectl -n "$namespace" wait --for=condition=Ready "pod/${pod}" --timeout=180s >/dev/null

  if ! {
    printf 'file_archive_start_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    kubectl -n "$namespace" exec "$pod" -- bash -lc \
      'if ! command -v zstd >/dev/null || ! test -f /etc/ssl/certs/ca-certificates.crt; then apt-get update >/tmp/nop-backup-apt-update.log && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends zstd ca-certificates >/tmp/nop-backup-apt-install.log; fi'
    if ! kubectl -n "$namespace" exec "$pod" -- test -x /usr/local/bin/azcopy >/dev/null 2>&1; then
      kubectl -n "$namespace" exec "$pod" -- mkdir -p /usr/local/bin
      tar -C /usr/local/bin -czf - azcopy | kubectl -n "$namespace" exec -i "$pod" -- tar -C /usr/local/bin -xzf -
    fi
    kubectl -n "$namespace" exec "$pod" -- bash -lc '
set -euo pipefail
archive="$1"
meta="$2"
rm -f "$archive" "$meta"
tar --numeric-owner -C /mnt/site -cf - . | zstd -T0 -q -o "$archive"
sha="$(sha256sum "$archive" | awk "{print \$1}")"
bytes="$(stat -c "%s" "$archive")"
printf "{\"artifact\":\"files.tar.zst\",\"bytes\":%s,\"sha256\":\"%s\"}\n" "$bytes" "$sha" > "$meta"
' _ "$remote_archive" "$remote_meta"
    printf 'file_archive_finish_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${site_dir}/file-archive.log" 2>&1; then
    kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return 1
  fi

  kubectl -n "$namespace" exec "$pod" -- cat "$remote_meta" > "${site_dir}/files.tar.zst.meta.json" || {
    kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return 1
  }
  printf '%s  files.tar.zst\n' "$(jq -r .sha256 "${site_dir}/files.tar.zst.meta.json")" > "${site_dir}/files.tar.zst.sha256"
  printf '%s\n' "$(jq -r .bytes "${site_dir}/files.tar.zst.meta.json")" > "${site_dir}/files.tar.zst.bytes"
  upload_pod_file "$namespace" "$pod" "$remote_archive" "${prefix}/files.tar.zst" "${site_dir}/file-upload.log" || {
    kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return 1
  }
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null
}

archive_pvc_detached() {
  local namespace="$1"
  local pvc="$2"
  local prefix="$3"
  local site_dir="$4"
  local pod="backup-archive-${pvc//[^a-zA-Z0-9-]/-}"
  pod="${pod:0:55}"
  local remote_meta="/work/files.tar.zst.meta.json"
  local elapsed=0
  local status

  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  cat <<EOF | kubectl -n "$namespace" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
  labels:
    app: nopcommerce-backup-archive
spec:
  restartPolicy: Never
  containers:
  - name: archive
    image: ${ARCHIVE_IMAGE}
    command: ["bash", "-lc", "sleep 3600"]
    volumeMounts:
    - name: site
      mountPath: /mnt/site
    - name: work
      mountPath: /work
  volumes:
  - name: site
    persistentVolumeClaim:
      claimName: ${pvc}
  - name: work
    emptyDir: {}
EOF
  kubectl -n "$namespace" wait --for=condition=Ready "pod/${pod}" --timeout=180s >/dev/null

  printf '%s\n' "$BACKUP_SAS_TOKEN" | kubectl -n "$namespace" exec -i "$pod" -- bash -lc 'cat > /work/sas.txt' || {
    kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return 1
  }

  kubectl -n "$namespace" exec -i "$pod" -- bash -lc 'cat > /work/archive-job.sh && chmod +x /work/archive-job.sh' <<'ARCHIVE_JOB'
#!/usr/bin/env bash
set -euo pipefail
account="$1"
container="$2"
blob="$3"
archive="/work/files.tar.zst"
meta="/work/files.tar.zst.meta.json"
archive_log="/work/file-archive.log"
upload_log="/work/file-upload.log"
status_file="/work/status"
sas_file="/work/sas.txt"
rm -f "$archive" "$meta" "$archive_log" "$upload_log" "$status_file"
if {
  printf "file_archive_start_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! command -v zstd >/dev/null || ! command -v curl >/dev/null || ! test -f /etc/ssl/certs/ca-certificates.crt; then
    apt-get update >/tmp/nop-backup-apt-update.log
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends zstd ca-certificates curl >/tmp/nop-backup-apt-install.log
  fi
  if ! /usr/local/bin/azcopy --version >/dev/null 2>&1; then
    rm -rf /tmp/azcopy-install
    mkdir -p /tmp/azcopy-install
    curl -fsSL https://aka.ms/downloadazcopy-v10-linux -o /tmp/azcopy-install/azcopy.tar.gz
    tar -xzf /tmp/azcopy-install/azcopy.tar.gz -C /tmp/azcopy-install
    install -m 0755 /tmp/azcopy-install/azcopy_linux_amd64_*/azcopy /usr/local/bin/azcopy
  fi
  tar --numeric-owner -C /mnt/site -cf - . | zstd -T0 -q -o "$archive"
  sha="$(sha256sum "$archive" | awk "{print \$1}")"
  bytes="$(stat -c "%s" "$archive")"
  printf "{\"artifact\":\"files.tar.zst\",\"bytes\":%s,\"sha256\":\"%s\"}\n" "$bytes" "$sha" > "$meta"
  printf "file_archive_finish_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$archive_log" 2>&1; then
  if {
    printf "upload_start_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sas_token=$(cat "$sas_file")
    url="https://${account}.blob.core.windows.net/${container}/${blob}?${sas_token}"
    mkdir -p /tmp/azcopy-logs /tmp/azcopy-plans
    AZCOPY_LOG_LOCATION=/tmp/azcopy-logs \
    AZCOPY_JOB_PLAN_LOCATION=/tmp/azcopy-plans \
    AZCOPY_CONCURRENCY_VALUE="${AZCOPY_CONCURRENCY_VALUE:-16}" \
      /usr/local/bin/azcopy copy "$archive" "$url" --overwrite=false --check-length=true --log-level=ERROR
    printf "upload_finish_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$upload_log" 2>&1; then
    rm -f "$sas_file"
    printf complete > "$status_file"
  else
    rm -f "$sas_file"
    printf failed > "$status_file"
    exit 1
  fi
else
  rm -f "$sas_file"
  printf failed > "$status_file"
  exit 1
fi
ARCHIVE_JOB

  kubectl -n "$namespace" exec "$pod" -- bash -lc 'nohup /work/archive-job.sh "$1" "$2" "$3" >/dev/null 2>&1 & echo $! > /work/pid' _ "$BACKUP_STORAGE_ACCOUNT" "$BACKUP_CONTAINER" "${prefix}/files.tar.zst" || {
    kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return 1
  }

  while true; do
    status=$(kubectl -n "$namespace" exec "$pod" -- bash -lc 'cat /work/status 2>/dev/null || true' 2>/dev/null || true)
    case "$status" in
      complete)
        break
        ;;
      failed)
        kubectl -n "$namespace" exec "$pod" -- cat /work/file-archive.log > "${site_dir}/file-archive.log" 2>/dev/null || true
        kubectl -n "$namespace" exec "$pod" -- cat /work/file-upload.log > "${site_dir}/file-upload.log" 2>/dev/null || true
        kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
        return 1
        ;;
    esac
    if [ "$elapsed" -ge "$SQL_EXPORT_TIMEOUT_SECONDS" ]; then
      kubectl -n "$namespace" exec "$pod" -- cat /work/file-archive.log > "${site_dir}/file-archive.log" 2>/dev/null || true
      kubectl -n "$namespace" exec "$pod" -- cat /work/file-upload.log > "${site_dir}/file-upload.log" 2>/dev/null || true
      kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
      return 1
    fi
    sleep 15
    elapsed=$((elapsed + 15))
  done

  kubectl -n "$namespace" exec "$pod" -- cat /work/file-archive.log > "${site_dir}/file-archive.log" || return 1
  kubectl -n "$namespace" exec "$pod" -- cat /work/file-upload.log > "${site_dir}/file-upload.log" || return 1
  kubectl -n "$namespace" exec "$pod" -- cat "$remote_meta" > "${site_dir}/files.tar.zst.meta.json" || return 1
  printf '%s  files.tar.zst\n' "$(jq -r .sha256 "${site_dir}/files.tar.zst.meta.json")" > "${site_dir}/files.tar.zst.sha256"
  printf '%s\n' "$(jq -r .bytes "${site_dir}/files.tar.zst.meta.json")" > "${site_dir}/files.tar.zst.bytes"
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false >/dev/null
}

write_manifest_and_checksums() {
  local site_dir="$1"
  local site_json="$2"
  local prefix="$3"
  local db_sha files_sha db_bytes files_bytes
  db_sha=$(jq -r .sha256 "${site_dir}/database.bacpac.meta.json")
  files_sha=$(jq -r .sha256 "${site_dir}/files.tar.zst.meta.json")
  db_bytes=$(jq -r .bytes "${site_dir}/database.bacpac.meta.json")
  files_bytes=$(jq -r .bytes "${site_dir}/files.tar.zst.meta.json")

  SITE_JSON="$site_json" \
  PREFIX="$prefix" \
  DB_SHA="$db_sha" \
  FILES_SHA="$files_sha" \
  DB_BYTES="$db_bytes" \
  FILES_BYTES="$files_bytes" \
  BATCH_ID="$BATCH_ID" \
  SHARE_SNAPSHOT="$SHARE_SNAPSHOT" \
  SCRIPT_VERSION="$SCRIPT_VERSION" \
  SOURCE_TENANT_ID="$SOURCE_TENANT_ID" \
  SOURCE_SUBSCRIPTION_ID="$SOURCE_SUBSCRIPTION_ID" \
  SOURCE_RESOURCE_GROUP="$SOURCE_RESOURCE_GROUP" \
  SOURCE_CLUSTER="$SOURCE_CLUSTER" \
  BACKUP_SUBSCRIPTION_ID="$BACKUP_SUBSCRIPTION_ID" \
  BACKUP_RESOURCE_GROUP="$BACKUP_RESOURCE_GROUP" \
  BACKUP_STORAGE_ACCOUNT="$BACKUP_STORAGE_ACCOUNT" \
  BACKUP_CONTAINER="$BACKUP_CONTAINER" \
  NFS_STORAGE_ACCOUNT="$NFS_STORAGE_ACCOUNT" \
  NFS_SHARE="$NFS_SHARE" \
  python3 - <<'PY' > "${site_dir}/manifest.json"
import json
import os
from datetime import datetime, timezone

site = json.loads(os.environ["SITE_JSON"])
manifest = {
    "schemaVersion": 2,
    "site": site["site"],
    "createdUtc": os.environ["BATCH_ID"],
    "backupMode": "cold-consistent-iterative",
    "backupRunner": {
        "tool": "scripts/backup-farheap-qa-nopcommerce-sites.sh",
        "version": os.environ["SCRIPT_VERSION"],
    },
    "source": {
        "tenantId": os.environ.get("SOURCE_TENANT_ID"),
        "subscriptionId": os.environ.get("SOURCE_SUBSCRIPTION_ID"),
        "resourceGroup": os.environ.get("SOURCE_RESOURCE_GROUP"),
        "cluster": os.environ.get("SOURCE_CLUSTER"),
        "namespace": site["namespace"],
        "helmRelease": site["helmRelease"],
    },
    "backupTarget": {
        "subscriptionId": os.environ.get("BACKUP_SUBSCRIPTION_ID"),
        "resourceGroup": os.environ.get("BACKUP_RESOURCE_GROUP"),
        "storageAccount": os.environ.get("BACKUP_STORAGE_ACCOUNT"),
        "container": os.environ.get("BACKUP_CONTAINER"),
        "prefix": os.environ["PREFIX"],
    },
    "app": {
        "image": site["image"],
        "chart": site.get("chart", ""),
        "appVersion": site.get("appVersion", ""),
        "replicas": site.get("replicas"),
        "strategy": site.get("strategy", ""),
        "hosts": site.get("hosts", []),
    },
    "database": {
        "engine": "azure-sql",
        "server": site["database"]["server"],
        "database": site["database"]["database"],
        "artifact": "database.bacpac",
        "bytes": int(os.environ["DB_BYTES"]),
        "sha256": os.environ["DB_SHA"],
    },
    "files": {
        "storage": os.environ.get("NFS_STORAGE_ACCOUNT"),
        "share": os.environ.get("NFS_SHARE"),
        "server": site["pvcs"][0]["nfsServer"] if site.get("pvcs") else "",
        "path": site["pvcs"][0]["nfsPath"] if site.get("pvcs") else "",
        "pvc": site["pvcs"][0]["name"] if site.get("pvcs") else "",
        "artifact": "files.tar.zst",
        "bytes": int(os.environ["FILES_BYTES"]),
        "sha256": os.environ["FILES_SHA"],
        "shareSnapshot": os.environ.get("SHARE_SNAPSHOT", ""),
    },
    "artifacts": {
        "helmValues": "helm-values.redacted.json",
        "kubernetesInventory": "k8s-inventory.json",
        "sqlLog": "sql-export.log",
        "sqlUploadLog": "sql-upload.log",
        "databaseMetadata": "database.bacpac.meta.json",
        "fileArchiveLog": "file-archive.log",
        "fileUploadLog": "file-upload.log",
        "fileMetadata": "files.tar.zst.meta.json",
        "phaseLog": "cold-backup.log",
        "smokeTest": "smoke-test.txt",
    },
    "secrets": {
        "includedInBackup": False,
        "notes": "Live deployment currently stores connection strings in env; backup artifacts redact them.",
    },
}
print(json.dumps(manifest, indent=2))
PY

  (
    cd "$site_dir"
    printf '%s  database.bacpac\n' "$db_sha" > sha256.txt
    printf '%s  files.tar.zst\n' "$files_sha" >> sha256.txt
    sha256sum manifest.json helm-values.redacted.json k8s-inventory.json sql-export.log sql-upload.log database.bacpac.meta.json file-archive.log file-upload.log files.tar.zst.meta.json cold-backup.log smoke-test.txt >> sha256.txt
  )
}

backup_site() {
  local site_json="$1"
  local namespace deployment helm_release image db_name primary_host pvc prefix site_dir original_replicas conn normalized_conn started
  namespace=$(jq -r .namespace <<<"$site_json")
  deployment=$(jq -r .deployment <<<"$site_json")
  helm_release=$(jq -r .helmRelease <<<"$site_json")
  image=$(jq -r .image <<<"$site_json")
  db_name=$(jq -r .database.database <<<"$site_json")
  primary_host=$(jq -r .primaryHost <<<"$site_json")
  pvc=$(jq -r '.pvcs[0].name // ""' <<<"$site_json")
  prefix="${BACKUP_BASE_PREFIX}/${namespace}/${BATCH_ID}"
  site_dir="${LOCAL_ROOT}/${namespace}"
  mkdir -p "$site_dir"

  log "Starting backup for ${namespace} db=${db_name} image=${image}"
  printf 'site_start_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${site_dir}/cold-backup.log"
  printf 'site=%s\nprefix=%s\n' "$namespace" "$prefix" >> "${site_dir}/cold-backup.log"

  if [ "$(blob_exists "${prefix}/complete.json")" = "true" ]; then
    die "Complete backup already exists at ${prefix}"
  fi
  if [ -z "$pvc" ]; then
    die "No PVC discovered for ${namespace}"
  fi

  original_replicas=$(kubectl -n "$namespace" get deploy "$deployment" -o jsonpath='{.spec.replicas}')
  original_replicas="${original_replicas:-1}"
  printf 'original_replicas=%s\n' "$original_replicas" >> "${site_dir}/cold-backup.log"

  conn=$(kubectl -n "$namespace" get deploy "$deployment" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ConnectionStrings__ConnectionString")].value}')
  normalized_conn=$(normalize_connection_string "$conn")
  unset conn

  log "Scaling ${namespace}/${deployment} down"
  kubectl -n "$namespace" scale deploy "$deployment" --replicas=0 >/dev/null || return 1
  wait_deploy_ready_replicas "$namespace" "$deployment" 0 300 || return 1
  printf 'scaled_down_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${site_dir}/cold-backup.log"

  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  log "Exporting SQL for ${namespace}"
  printf 'sql_export_requested_utc=%s\n' "$started" >> "${site_dir}/cold-backup.log"
  if ! export_sql_in_runner "$namespace" "$normalized_conn" "$prefix" "$site_dir"; then
    unset normalized_conn
    return 1
  fi
  unset normalized_conn
  [ -s "${site_dir}/database.bacpac.meta.json" ] || return 1
  printf 'database_bacpac_bytes=%s\n' "$(jq -r .bytes "${site_dir}/database.bacpac.meta.json")" >> "${site_dir}/cold-backup.log"

  log "Archiving NFS PVC ${namespace}/${pvc}"
  if ! archive_pvc_detached "$namespace" "$pvc" "$prefix" "$site_dir"; then
    return 1
  fi
  [ -s "${site_dir}/files.tar.zst.meta.json" ] || return 1
  printf 'files_tarzst_bytes=%s\n' "$(jq -r .bytes "${site_dir}/files.tar.zst.meta.json")" >> "${site_dir}/cold-backup.log"

  write_inventory "$namespace" "$deployment" "$site_dir" || return 1
  write_helm_values "$namespace" "$helm_release" "$site_dir" || return 1

  log "Scaling ${namespace}/${deployment} back to ${original_replicas}"
  kubectl -n "$namespace" scale deploy "$deployment" --replicas="$original_replicas" >/dev/null || return 1
  wait_deploy_ready_replicas "$namespace" "$deployment" "$original_replicas" 600 || return 1
  printf 'scaled_up_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${site_dir}/cold-backup.log"

  if [ -n "$primary_host" ]; then
    log "Smoke testing https://${primary_host}/"
    curl --noproxy '*' -sS -o /dev/null \
      -w 'smoke_test_utc=%{time_starttransfer}\nhttp_code=%{http_code}\ntime_total=%{time_total}\nurl_effective=%{url_effective}\n' \
      --max-time 90 "https://${primary_host}/" > "${site_dir}/smoke-test.txt" 2>&1 || true
  else
    printf 'skipped=no_primary_host\n' > "${site_dir}/smoke-test.txt"
  fi

  write_manifest_and_checksums "$site_dir" "$site_json" "$prefix" || return 1
  cat > "${site_dir}/complete.json" <<EOF
{
  "status": "complete",
  "completedUtc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "site": "${namespace}",
  "prefix": "${prefix}",
  "databaseBytes": $(jq -r .bytes "${site_dir}/database.bacpac.meta.json"),
  "filesBytes": $(jq -r .bytes "${site_dir}/files.tar.zst.meta.json")
}
EOF

  log "Uploading backup artifacts for ${namespace}"
  upload_site_dir "$site_dir" "$prefix" || return 1

  jq -n \
    --arg site "$namespace" \
    --arg prefix "$prefix" \
    --arg status "complete" \
    --arg dbBytes "$(jq -r .bytes "${site_dir}/database.bacpac.meta.json")" \
    --arg filesBytes "$(jq -r .bytes "${site_dir}/files.tar.zst.meta.json")" \
    '{site:$site,prefix:$prefix,status:$status,databaseBytes:($dbBytes|tonumber),filesBytes:($filesBytes|tonumber)}' \
    > "${site_dir}/site-result.json"
  log "Completed backup for ${namespace}"
}

write_failed_site() {
  local site_json="$1"
  local reason="$2"
  local namespace prefix site_dir
  namespace=$(jq -r .namespace <<<"$site_json")
  prefix="${BACKUP_BASE_PREFIX}/${namespace}/${BATCH_ID}"
  site_dir="${LOCAL_ROOT}/${namespace}"
  mkdir -p "$site_dir"
  cat > "${site_dir}/failed.json" <<EOF
{
  "status": "failed",
  "failedUtc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "site": "${namespace}",
  "prefix": "${prefix}",
  "reason": $(jq -Rn --arg s "$reason" '$s')
}
EOF
  upload_file "${site_dir}/failed.json" "${prefix}/failed.json" || true
  jq -n --arg site "$namespace" --arg prefix "$prefix" --arg status failed --arg reason "$reason" \
    '{site:$site,prefix:$prefix,status:$status,reason:$reason}' > "${site_dir}/site-result.json"
}

restore_replica_on_failure() {
  local site_json="$1"
  local namespace deployment desired
  namespace=$(jq -r .namespace <<<"$site_json")
  deployment=$(jq -r .deployment <<<"$site_json")
  desired=$(jq -r .replicas <<<"$site_json")
  if [ -n "$namespace" ] && [ -n "$deployment" ] && [ "$desired" != "null" ]; then
    log "Ensuring ${namespace}/${deployment} is scaled back to ${desired}"
    kubectl -n "$namespace" scale deploy "$deployment" --replicas="$desired" >/dev/null 2>&1 || true
  fi
}

write_batch_summary() {
  local batch_dir="${LOCAL_ROOT}/_batch"
  mkdir -p "$batch_dir"
  python3 - "$LOCAL_ROOT" "$BATCH_ID" <<'PY' > "${batch_dir}/batch.json"
import json
import pathlib
import sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
batch = sys.argv[2]
results = []
for path in sorted(root.glob("*/site-result.json")):
    if path.parent.name == "_batch":
        continue
    results.append(json.loads(path.read_text()))
summary = {
    "schemaVersion": 1,
    "batchId": batch,
    "completedUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "environment": "farheap-qa",
    "siteCount": len(results),
    "completeCount": sum(1 for x in results if x.get("status") == "complete"),
    "failedCount": sum(1 for x in results if x.get("status") == "failed"),
    "results": results,
}
print(json.dumps(summary, indent=2))
PY
  upload_file "${batch_dir}/batch.json" "${BACKUP_BASE_PREFIX}/_batches/${BATCH_ID}/batch.json"
}

main() {
  require_cloudbench
  setup_az
  mkdir -p "$LOCAL_ROOT"
  install_kubectl_retry_wrapper

  az_set_subscription "$SOURCE_SUBSCRIPTION_ID"
  "${AZ[@]}" aks get-credentials \
    -g "$SOURCE_RESOURCE_GROUP" \
    -n "$SOURCE_CLUSTER" \
    --admin \
    --file "$KUBECONFIG_PATH" \
    --overwrite-existing >/dev/null
  export KUBECONFIG="$KUBECONFIG_PATH"

  discover_sites
  local site_count
  site_count=$(jq length "${LOCAL_ROOT}/sites.json")
  [ "$site_count" -gt 0 ] || die "No nopCommerce sites discovered"

  prepare_sql_runner

  az_set_subscription "$BACKUP_SUBSCRIPTION_ID"
  BACKUP_ACCOUNT_KEY=$("${AZ[@]}" storage account keys list \
    -g "$BACKUP_RESOURCE_GROUP" \
    -n "$BACKUP_STORAGE_ACCOUNT" \
    --query '[0].value' -o tsv)
  export BACKUP_ACCOUNT_KEY
  "${AZ[@]}" storage container create \
    --account-name "$BACKUP_STORAGE_ACCOUNT" \
    --account-key "$BACKUP_ACCOUNT_KEY" \
    --name "$BACKUP_CONTAINER" >/dev/null
  BACKUP_SAS_EXPIRY_UTC="${BACKUP_SAS_EXPIRY_UTC:-$(date -u -d '+2 days' +%Y-%m-%dT%H:%MZ)}"
  BACKUP_SAS_TOKEN=$("${AZ[@]}" storage container generate-sas \
    --account-name "$BACKUP_STORAGE_ACCOUNT" \
    --account-key "$BACKUP_ACCOUNT_KEY" \
    --name "$BACKUP_CONTAINER" \
    --permissions acdlrw \
    --expiry "$BACKUP_SAS_EXPIRY_UTC" \
    -o tsv)
  export BACKUP_SAS_TOKEN

  az_set_subscription "$SOURCE_SUBSCRIPTION_ID"
  local nfs_key snapshot_json
  nfs_key=$("${AZ[@]}" storage account keys list -g "$NFS_RESOURCE_GROUP" -n "$NFS_STORAGE_ACCOUNT" --query '[0].value' -o tsv)
  log "Creating batch Azure Files snapshot for ${NFS_STORAGE_ACCOUNT}/${NFS_SHARE}"
  snapshot_json=$("${AZ[@]}" storage share snapshot \
    --account-name "$NFS_STORAGE_ACCOUNT" \
    --account-key "$nfs_key" \
    --name "$NFS_SHARE" \
    --metadata Environment="$BACKUP_ENVIRONMENT" BackupBatch="$BATCH_ID" Initiator=nopcommerce-full-backup \
    -o json)
  SHARE_SNAPSHOT=$(jq -r '.snapshot // .Snapshot // empty' <<<"$snapshot_json")
  [ -n "$SHARE_SNAPSHOT" ] || SHARE_SNAPSHOT=$(jq -r '.properties.snapshot // empty' <<<"$snapshot_json")
  [ -n "$SHARE_SNAPSHOT" ] || die "Could not determine share snapshot timestamp from: ${snapshot_json}"
  export SHARE_SNAPSHOT
  log "Share snapshot: ${SHARE_SNAPSHOT}"

  az_set_subscription "$BACKUP_SUBSCRIPTION_ID"

  local idx site_json
  for idx in $(seq 0 $((site_count - 1))); do
    site_json=$(jq -c ".[$idx]" "${LOCAL_ROOT}/sites.json")
    CURRENT_SITE_JSON="$site_json"
    if backup_site "$site_json"; then
      CURRENT_SITE_JSON=""
      :
    else
      local status=$?
      restore_replica_on_failure "$site_json"
      CURRENT_SITE_JSON=""
      write_failed_site "$site_json" "backup_site exited ${status}"
      log "Backup failed for $(jq -r .namespace <<<"$site_json"); continuing"
    fi
  done

  write_batch_summary
  log "Batch summary: ${BACKUP_BASE_PREFIX}/_batches/${BATCH_ID}/batch.json"
  jq . "${LOCAL_ROOT}/_batch/batch.json"
}

trap 'status=$?; if [ "$status" -ne 0 ] && [ -n "${CURRENT_SITE_JSON:-}" ]; then restore_replica_on_failure "$CURRENT_SITE_JSON"; fi; exit "$status"' INT TERM

main "$@"
