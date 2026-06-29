#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-297b2389-33bf-48c8-8deb-0b92838431e4}"
AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-rg-os-sandbox-drtest-qa}"
AKS_NAME="${AKS_NAME:-aks-os-drtest-qa-01}"
SQL_RESOURCE_GROUP="${SQL_RESOURCE_GROUP:-rg-os-workload-nopcommerce-qa}"
SQL_SERVER="${SQL_SERVER:-sql-os-nopcommerce-qa-01}"
GET_AKS_CREDENTIALS="${GET_AKS_CREDENTIALS:-true}"

CACHE_NAMESPACE="${CACHE_NAMESPACE:-nopcommerce-cache}"
WARMER_NAME="${WARMER_NAME:-opensoft-nopcommerce-homepage-warmer}"
HOSTS_CONFIGMAP="${HOSTS_CONFIGMAP:-opensoft-nopcommerce-homepage-warmer-hosts}"
INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"

REPORT_ROOT="${REPORT_ROOT:-reports/cache-pilot}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
REPORT_DIR="${REPORT_DIR:-${REPORT_ROOT}/${RUN_ID}}"

HOMEPAGE_CYCLES="${HOMEPAGE_CYCLES:-3}"
HOMEPAGE_SAMPLES_PER_HOST="${HOMEPAGE_SAMPLES_PER_HOST:-3}"
WARMER_ON_SUCCESSFUL_RUNS="${WARMER_ON_SUCCESSFUL_RUNS:-3}"
WARMER_OFF_WAIT_SECONDS="${WARMER_OFF_WAIT_SECONDS:-900}"
WARMER_WAIT_TIMEOUT_SECONDS="${WARMER_WAIT_TIMEOUT_SECONDS:-1200}"

BROWSER_HOSTS="${BROWSER_HOSTS:-digiwrap.davinci-designer.com,qa1.overnightprints.eu,staging.rentapress.com,eds1.qa.davincisite.com}"
BROWSER_ITERATIONS="${BROWSER_ITERATIONS:-5}"
BROWSER_PREFETCH_WAIT_MS="${BROWSER_PREFETCH_WAIT_MS:-8000}"
BROWSER_TIMEOUT_MS="${BROWSER_TIMEOUT_MS:-60000}"
PLAYWRIGHT_WORKDIR="${PLAYWRIGHT_WORKDIR:-/tmp/digiwrap-headless-test}"

COLLECT_AZURE_METRICS="${COLLECT_AZURE_METRICS:-true}"
SMOKE="${SMOKE:-false}"
BROWSER_ONLY="${BROWSER_ONLY:-false}"
USE_HOST_PROXY="${USE_HOST_PROXY:-true}"

if [ "$SMOKE" = "true" ]; then
  HOMEPAGE_CYCLES="${SMOKE_HOMEPAGE_CYCLES:-1}"
  HOMEPAGE_SAMPLES_PER_HOST="${SMOKE_HOMEPAGE_SAMPLES_PER_HOST:-1}"
  WARMER_ON_SUCCESSFUL_RUNS="${SMOKE_WARMER_ON_SUCCESSFUL_RUNS:-1}"
  WARMER_OFF_WAIT_SECONDS="${SMOKE_WARMER_OFF_WAIT_SECONDS:-15}"
  WARMER_WAIT_TIMEOUT_SECONDS="${SMOKE_WARMER_WAIT_TIMEOUT_SECONDS:-300}"
  BROWSER_ITERATIONS="${SMOKE_BROWSER_ITERATIONS:-1}"
  BROWSER_PREFETCH_WAIT_MS="${SMOKE_BROWSER_PREFETCH_WAIT_MS:-3000}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BROWSER_SCRIPT="${REPO_ROOT}/scripts/lib/nopcommerce-cache-browser-test.js"

if [[ "$REPORT_DIR" != /* ]]; then
  REPORT_DIR="${REPO_ROOT}/${REPORT_DIR}"
fi

if [ -n "${AZ_CMD:-}" ]; then
  read -r -a AZ <<< "$AZ_CMD"
elif [ -x /opt/az/bin/python3 ] && [ -f /tmp/azfixed.py ]; then
  AZ=(/opt/az/bin/python3 /tmp/azfixed.py)
else
  AZ=(az)
fi

ORIGINAL_WARMER_SUSPEND=""
RESTORE_WARMER_STATE="false"
INGRESS_IP=""
HOSTS_FILE=""

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null || die "Missing required tool: $1"
}

normalize_bool() {
  case "${1:-}" in
    true|True|TRUE) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

csv_escape() {
  python3 - "$1" <<'PY'
import csv
import io
import sys

buf = io.StringIO()
writer = csv.writer(buf)
writer.writerow([sys.argv[1]])
sys.stdout.write(buf.getvalue().strip("\r\n"))
PY
}

setup_az() {
  if [ -x /opt/az/bin/python3 ]; then
    local user_site
    user_site=$(/opt/az/bin/python3 -c "import site; print(site.getusersitepackages())")
    export PYTHONPATH="${user_site}:/opt/az/lib/python3.13/site-packages"
    export AZ_INSTALLER=PIP
  fi

  if [ "$USE_HOST_PROXY" = "true" ]; then
    export HTTP_PROXY="${HTTP_PROXY:-http://host.docker.internal:17891}"
    export HTTPS_PROXY="${HTTPS_PROXY:-http://host.docker.internal:17891}"
    export http_proxy="${http_proxy:-$HTTP_PROXY}"
    export https_proxy="${https_proxy:-$HTTPS_PROXY}"
    export NO_PROXY="${NO_PROXY:-.database.windows.net,.file.core.windows.net,10.0.0.0/8,127.0.0.1,localhost}"
    export no_proxy="${no_proxy:-$NO_PROXY}"
  else
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
  fi
}

ensure_context() {
  require_tool kubectl
  require_tool jq
  require_tool curl
  require_tool python3

  setup_az

  if [ "$GET_AKS_CREDENTIALS" = "true" ]; then
    log "Selecting subscription ${SUBSCRIPTION_ID}"
    "${AZ[@]}" account set --subscription "$SUBSCRIPTION_ID" >/dev/null

    log "Loading AKS credentials for ${AKS_NAME}"
    "${AZ[@]}" aks get-credentials \
      --resource-group "$AKS_RESOURCE_GROUP" \
      --name "$AKS_NAME" \
      --overwrite-existing \
      --output none
  fi
}

write_csv_header() {
  cat > "${REPORT_DIR}/homepage-warmer.csv" <<'EOF'
timestamp,phase,cycle,sample,host,url,http_code,exit_code,error,num_redirects,size_download,time_namelookup,time_connect,time_appconnect,time_starttransfer,time_total
EOF
  : > "${REPORT_DIR}/raw-homepage.ndjson"
}

discover_hosts() {
  HOSTS_FILE="${REPORT_DIR}/hosts.txt"
  kubectl -n "$CACHE_NAMESPACE" get configmap "$HOSTS_CONFIGMAP" \
    -o jsonpath='{.data.hosts\.txt}' \
    | sed '/^[[:space:]]*$/d' \
    | sort -u > "$HOSTS_FILE"

  [ -s "$HOSTS_FILE" ] || die "No hosts found in ${CACHE_NAMESPACE}/${HOSTS_CONFIGMAP}"
}

discover_ingress_ip() {
  INGRESS_IP=$(kubectl -n "$INGRESS_NAMESPACE" get svc "$INGRESS_SERVICE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$INGRESS_IP" ] || die "Could not discover ingress IP from ${INGRESS_NAMESPACE}/${INGRESS_SERVICE}"
}

warmer_suspend_state() {
  normalize_bool "$(kubectl -n "$CACHE_NAMESPACE" get cronjob "$WARMER_NAME" -o jsonpath='{.spec.suspend}' 2>/dev/null || true)"
}

set_warmer_suspend() {
  local value="$1"
  kubectl -n "$CACHE_NAMESPACE" patch cronjob "$WARMER_NAME" \
    --type=merge \
    -p "{\"spec\":{\"suspend\":${value}}}" >/dev/null
}

restore_warmer_state() {
  if [ "$RESTORE_WARMER_STATE" != "true" ] || [ -z "$ORIGINAL_WARMER_SUSPEND" ]; then
    return
  fi
  log "Restoring warmer suspend state to ${ORIGINAL_WARMER_SUSPEND}"
  set_warmer_suspend "$ORIGINAL_WARMER_SUSPEND" || true
}

capture_deployments() {
  kubectl get deploy -A -o json | jq '
    [
      .items[]
      | select(any(.spec.template.spec.containers[]?; ((.image // "") | test("nopcommerce"; "i"))))
      | {
          namespace: .metadata.namespace,
          name: .metadata.name,
          desired: (.spec.replicas // 0),
          replicas: (.status.replicas // 0),
          ready: (.status.readyReplicas // 0),
          updated: (.status.updatedReplicas // 0),
          images: [.spec.template.spec.containers[]?.image]
        }
    ]
  '
}

capture_pod_restarts() {
  local deployments_file="$1"
  local ns_json
  ns_json=$(jq -c '[.[].namespace] | unique' "$deployments_file")
  kubectl get pod -A -o json | jq --argjson namespaces "$ns_json" '
    [
      .items[]
      | .metadata.namespace as $namespace
      | select($namespaces | index($namespace))
      | {
          namespace: $namespace,
          pod: .metadata.name,
          phase: .status.phase,
          restartCount: ([.status.containerStatuses[]?.restartCount] | add // 0),
          containers: [
            .status.containerStatuses[]?
            | {
                name: .name,
                restartCount: (.restartCount // 0),
                ready: (.ready // false),
                image: (.image // "")
              }
          ]
        }
    ]
  '
}

capture_warmer_jobs() {
  kubectl -n "$CACHE_NAMESPACE" get jobs \
    -l app.kubernetes.io/name=nopcommerce-homepage-warmer \
    -o json 2>/dev/null | jq '
      [
        .items[]
        | {
            name: .metadata.name,
            creationTimestamp: .metadata.creationTimestamp,
            active: (.status.active // 0),
            succeeded: (.status.succeeded // 0),
            failed: (.status.failed // 0),
            startTime: (.status.startTime // null),
            completionTime: (.status.completionTime // null),
            durationSeconds: (
              if (.status.startTime and .status.completionTime)
              then ((.status.completionTime | fromdateiso8601) - (.status.startTime | fromdateiso8601))
              else null end
            )
          }
      ]
    '
}

capture_top_pods() {
  kubectl top pod -A 2>&1 || true
}

capture_azure_metrics() {
  local output="$1"
  : > "$output"

  if [ "$COLLECT_AZURE_METRICS" != "true" ]; then
    printf 'Azure metrics skipped: COLLECT_AZURE_METRICS=false\n' > "$output"
    return
  fi

  {
    echo "Azure SQL metrics captured at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "${AZ[@]}" account set --subscription "$SUBSCRIPTION_ID" >/dev/null
    local ids
    ids=$("${AZ[@]}" sql db list \
      --resource-group "$SQL_RESOURCE_GROUP" \
      --server "$SQL_SERVER" \
      --query "[?name!='master'].id" \
      --output tsv 2>/dev/null || true)
    if [ -z "$ids" ]; then
      echo "No SQL DB ids found or az sql db list failed."
      return
    fi
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      echo "--- ${id}"
      "${AZ[@]}" monitor metrics list \
        --ids "$id" \
        --metric cpu_percent,dtu_consumption_percent,storage_percent \
        --interval PT5M \
        --aggregation Average \
        --output json 2>&1 || true
    done <<< "$ids"
  } > "$output" 2>&1 || true
}

write_snapshot() {
  local label="$1"
  local output="$2"
  local deployments_file pods_file jobs_file top_file metrics_file
  local smoke_json

  if [ "$SMOKE" = "true" ]; then
    smoke_json=true
  else
    smoke_json=false
  fi

  deployments_file="${REPORT_DIR}/${label}-deployments.json"
  pods_file="${REPORT_DIR}/${label}-pod-restarts.json"
  jobs_file="${REPORT_DIR}/${label}-warmer-jobs.json"
  top_file="${REPORT_DIR}/${label}-kubectl-top.txt"
  metrics_file="${REPORT_DIR}/${label}-azure-metrics.txt"

  capture_deployments > "$deployments_file"
  capture_pod_restarts "$deployments_file" > "$pods_file"
  capture_warmer_jobs > "$jobs_file"
  capture_top_pods > "$top_file"
  capture_azure_metrics "$metrics_file"

  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg label "$label" \
    --arg subscriptionId "$SUBSCRIPTION_ID" \
    --arg aksName "$AKS_NAME" \
    --arg ingressIp "$INGRESS_IP" \
    --arg warmerSuspend "$(warmer_suspend_state)" \
    --argjson smoke "$smoke_json" \
    --argjson homepageCycles "$HOMEPAGE_CYCLES" \
    --argjson homepageSamplesPerHost "$HOMEPAGE_SAMPLES_PER_HOST" \
    --argjson warmerOnSuccessfulRuns "$WARMER_ON_SUCCESSFUL_RUNS" \
    --argjson warmerOffWaitSeconds "$WARMER_OFF_WAIT_SECONDS" \
    --argjson browserIterations "$BROWSER_ITERATIONS" \
    --arg browserHosts "$BROWSER_HOSTS" \
    --rawfile hosts "$HOSTS_FILE" \
    --slurpfile deployments "$deployments_file" \
    --slurpfile podRestarts "$pods_file" \
    --slurpfile warmerJobs "$jobs_file" \
    --rawfile topPods "$top_file" \
    --rawfile azureMetrics "$metrics_file" \
    '{
      timestamp: $timestamp,
      label: $label,
      subscriptionId: $subscriptionId,
      aksName: $aksName,
      ingressIp: $ingressIp,
      warmerSuspend: $warmerSuspend,
      config: {
        smoke: $smoke,
        homepageCycles: $homepageCycles,
        homepageSamplesPerHost: $homepageSamplesPerHost,
        warmerOnSuccessfulRuns: $warmerOnSuccessfulRuns,
        warmerOffWaitSeconds: $warmerOffWaitSeconds,
        browserIterations: $browserIterations,
        browserHosts: ($browserHosts | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
      },
      hosts: ($hosts | split("\n") | map(select(length > 0))),
      deployments: $deployments[0],
      podRestarts: $podRestarts[0],
      warmerJobs: $warmerJobs[0],
      topPods: $topPods,
      azureMetricsText: $azureMetrics
    }' > "$output"
}

assert_deployments_ready() {
  local deployments_file="$1"
  local not_ready
  not_ready=$(jq -r '
    [
      .[]
      | select((.desired != .ready) or (.desired == 0))
      | "\(.namespace)/\(.name) desired=\(.desired) ready=\(.ready)"
    ]
    | .[]
  ' "$deployments_file")

  if [ -n "$not_ready" ]; then
    printf '%s\n' "$not_ready" >&2
    die "One or more nopCommerce deployments are not ready"
  fi
}

measure_homepage() {
  local phase="$1"
  local cycle="$2"
  local sample="$3"
  local host="$4"
  local url="https://${host}/"
  local body_file err_file metrics_file timestamp exit_code error_text

  body_file=$(mktemp)
  err_file=$(mktemp)
  metrics_file=$(mktemp)
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  set +e
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    curl --noproxy "*" -k -L -sS \
      --max-time 60 \
      --connect-timeout 10 \
      --resolve "${host}:443:${INGRESS_IP}" \
      -o "$body_file" \
      -w $'http_code=%{http_code}\nnum_redirects=%{num_redirects}\nsize_download=%{size_download}\ntime_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_appconnect=%{time_appconnect}\ntime_starttransfer=%{time_starttransfer}\ntime_total=%{time_total}\n' \
      "$url" > "$metrics_file" 2> "$err_file"
  exit_code=$?
  set -e

  error_text=$(tr '\n' ' ' < "$err_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')

  local http_code num_redirects size_download time_namelookup time_connect time_appconnect time_starttransfer time_total
  http_code=$(awk -F= '/^http_code=/{print $2}' "$metrics_file")
  num_redirects=$(awk -F= '/^num_redirects=/{print $2}' "$metrics_file")
  size_download=$(awk -F= '/^size_download=/{print $2}' "$metrics_file")
  time_namelookup=$(awk -F= '/^time_namelookup=/{print $2}' "$metrics_file")
  time_connect=$(awk -F= '/^time_connect=/{print $2}' "$metrics_file")
  time_appconnect=$(awk -F= '/^time_appconnect=/{print $2}' "$metrics_file")
  time_starttransfer=$(awk -F= '/^time_starttransfer=/{print $2}' "$metrics_file")
  time_total=$(awk -F= '/^time_total=/{print $2}' "$metrics_file")

  printf '%s\n' "$(jq -n \
    --arg timestamp "$timestamp" \
    --arg phase "$phase" \
    --argjson cycle "$cycle" \
    --argjson sample "$sample" \
    --arg host "$host" \
    --arg url "$url" \
    --arg httpCode "${http_code:-000}" \
    --argjson exitCode "$exit_code" \
    --arg error "$error_text" \
    --arg numRedirects "${num_redirects:-0}" \
    --arg sizeDownload "${size_download:-0}" \
    --arg timeNamelookup "${time_namelookup:-0}" \
    --arg timeConnect "${time_connect:-0}" \
    --arg timeAppconnect "${time_appconnect:-0}" \
    --arg timeStarttransfer "${time_starttransfer:-0}" \
    --arg timeTotal "${time_total:-0}" \
    '{
      timestamp: $timestamp,
      phase: $phase,
      cycle: $cycle,
      sample: $sample,
      host: $host,
      url: $url,
      httpCode: $httpCode,
      exitCode: $exitCode,
      error: $error,
      numRedirects: ($numRedirects | tonumber),
      sizeDownload: ($sizeDownload | tonumber),
      timeNamelookup: ($timeNamelookup | tonumber),
      timeConnect: ($timeConnect | tonumber),
      timeAppconnect: ($timeAppconnect | tonumber),
      timeStarttransfer: ($timeStarttransfer | tonumber),
      timeTotal: ($timeTotal | tonumber)
    }')" >> "${REPORT_DIR}/raw-homepage.ndjson"

  {
    csv_escape "$timestamp"; printf ','
    csv_escape "$phase"; printf ','
    csv_escape "$cycle"; printf ','
    csv_escape "$sample"; printf ','
    csv_escape "$host"; printf ','
    csv_escape "$url"; printf ','
    csv_escape "${http_code:-000}"; printf ','
    csv_escape "$exit_code"; printf ','
    csv_escape "$error_text"; printf ','
    csv_escape "${num_redirects:-0}"; printf ','
    csv_escape "${size_download:-0}"; printf ','
    csv_escape "${time_namelookup:-0}"; printf ','
    csv_escape "${time_connect:-0}"; printf ','
    csv_escape "${time_appconnect:-0}"; printf ','
    csv_escape "${time_starttransfer:-0}"; printf ','
    csv_escape "${time_total:-0}"; printf '\n'
  } >> "${REPORT_DIR}/homepage-warmer.csv"

  rm -f "$body_file" "$err_file" "$metrics_file"
}

measure_all_homepages() {
  local phase="$1"
  local cycle="$2"
  local sample host

  for sample in $(seq 1 "$HOMEPAGE_SAMPLES_PER_HOST"); do
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      log "Homepage ${phase} cycle=${cycle} sample=${sample} host=${host}"
      measure_homepage "$phase" "$cycle" "$sample" "$host"
    done < "$HOSTS_FILE"
  done
}

wait_for_no_active_warmer_jobs() {
  local active
  for _ in $(seq 1 120); do
    active=$(kubectl -n "$CACHE_NAMESPACE" get cronjob "$WARMER_NAME" -o jsonpath='{.status.active}' 2>/dev/null || true)
    [ -z "$active" ] && return 0
    sleep 2
  done
  die "Timed out waiting for active warmer jobs to finish"
}

wait_for_successful_warmer_jobs() {
  local needed="$1"
  local start_epoch count observed_file observed_tmp
  start_epoch=$(date -u +%s)
  observed_file="${REPORT_DIR}/.warmer-successes-${start_epoch}-$$.txt"
  observed_tmp="${observed_file}.tmp"
  : > "$observed_file"

  log "Waiting for ${needed} successful warmer job(s)"
  local deadline=$((start_epoch + WARMER_WAIT_TIMEOUT_SECONDS))
  while true; do
    kubectl -n "$CACHE_NAMESPACE" get jobs \
      -l app.kubernetes.io/name=nopcommerce-homepage-warmer \
      -o json | jq -r --argjson start "$start_epoch" '
        .items[]
        | select((.metadata.creationTimestamp | fromdateiso8601) >= $start)
        | select((.status.succeeded // 0) >= 1)
        | .metadata.name
      ' >> "$observed_file"
    sort -u "$observed_file" > "$observed_tmp"
    mv "$observed_tmp" "$observed_file"
    count=$(wc -l < "$observed_file" | tr -d ' ')
    if [ "$count" -ge "$needed" ]; then
      log "Observed ${count} successful warmer job(s)"
      rm -f "$observed_file" "$observed_tmp"
      return 0
    fi
    if [ "$(date -u +%s)" -ge "$deadline" ]; then
      die "Timed out waiting for successful warmer jobs"
    fi
    sleep 10
  done
}

run_homepage_ab() {
  local cycle
  for cycle in $(seq 1 "$HOMEPAGE_CYCLES"); do
    log "Starting homepage warmer ON phase cycle ${cycle}/${HOMEPAGE_CYCLES}"
    set_warmer_suspend false
    wait_for_successful_warmer_jobs "$WARMER_ON_SUCCESSFUL_RUNS"
    measure_all_homepages "warmer_on" "$cycle"

    log "Starting homepage warmer OFF phase cycle ${cycle}/${HOMEPAGE_CYCLES}"
    set_warmer_suspend true
    wait_for_no_active_warmer_jobs
    log "Waiting ${WARMER_OFF_WAIT_SECONDS}s with warmer suspended"
    sleep "$WARMER_OFF_WAIT_SECONDS"
    measure_all_homepages "warmer_off" "$cycle"
  done
}

ensure_playwright() {
  require_tool node

  if node -e 'require("playwright")' >/dev/null 2>&1; then
    PLAYWRIGHT_NODE_CWD="$REPO_ROOT"
    return
  fi

  if [ -d "${PLAYWRIGHT_WORKDIR}/node_modules/playwright" ]; then
    PLAYWRIGHT_NODE_CWD="$PLAYWRIGHT_WORKDIR"
    return
  fi

  require_tool npm
  PLAYWRIGHT_NODE_CWD="${REPORT_DIR}/playwright-runtime"
  mkdir -p "$PLAYWRIGHT_NODE_CWD"
  (
    cd "$PLAYWRIGHT_NODE_CWD"
    npm init -y >/dev/null
    npm install playwright --no-audit --no-fund
    npx playwright install chromium
  )
}

run_browser_ab() {
  local hosts
  ensure_playwright

  hosts="$BROWSER_HOSTS"
  if [ "$SMOKE" = "true" ]; then
    hosts="${BROWSER_HOSTS%%,*}"
  fi

  restore_warmer_state
  log "Running browser warm-fetch A/B for hosts: ${hosts}"
  (
    cd "$PLAYWRIGHT_NODE_CWD"
    env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
      CACHE_TEST_HOSTS="$hosts" \
      INGRESS_IP="$INGRESS_IP" \
      BROWSER_ITERATIONS="$BROWSER_ITERATIONS" \
      BROWSER_PREFETCH_WAIT_MS="$BROWSER_PREFETCH_WAIT_MS" \
      BROWSER_TIMEOUT_MS="$BROWSER_TIMEOUT_MS" \
      BROWSER_NDJSON="${REPORT_DIR}/raw-browser.ndjson" \
      BROWSER_CSV="${REPORT_DIR}/browser-prefetch.csv" \
      NODE_PATH="${PLAYWRIGHT_NODE_CWD}/node_modules${NODE_PATH:+:${NODE_PATH}}" \
      SMOKE="$SMOKE" \
    node "$BROWSER_SCRIPT"
  )
}

generate_summary() {
  python3 - "$REPORT_DIR" <<'PY'
import csv
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

report = Path(sys.argv[1])

def load_json(path):
    with path.open() as handle:
        return json.load(handle)

def percentile(values, pct):
    values = sorted(float(v) for v in values if v is not None)
    if not values:
        return None
    if len(values) == 1:
        return values[0]
    rank = (len(values) - 1) * pct
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return values[int(rank)]
    return values[lower] + (values[upper] - values[lower]) * (rank - lower)

def fmt(value, suffix=""):
    if value is None:
        return "n/a"
    return f"{value:.3f}{suffix}"

preflight = load_json(report / "preflight.json")
postflight = load_json(report / "postflight.json")
smoke_mode = bool(preflight.get("config", {}).get("smoke"))

homepage_rows = []
with (report / "homepage-warmer.csv").open(newline="") as handle:
    for row in csv.DictReader(handle):
        if row["phase"] in {"warmer_on", "warmer_off"}:
            homepage_rows.append(row)

browser_rows = []
browser_csv = report / "browser-prefetch.csv"
if browser_csv.exists():
    with browser_csv.open(newline="") as handle:
        browser_rows = list(csv.DictReader(handle))

homepage_by_host = defaultdict(lambda: defaultdict(list))
homepage_errors = 0
for row in homepage_rows:
    if row["exit_code"] != "0" or not row["http_code"].startswith("2"):
        homepage_errors += 1
    homepage_by_host[row["host"]][row["phase"]].append(float(row["time_total"] or 0))

browser_by_host = defaultdict(lambda: defaultdict(list))
browser_errors = 0
blocked_hints = 0
warm_fetch_requests = 0
intent_warm_fetch_requests = 0
warm_fetch_ok = 0
warm_fetch_errors = 0
warm_fetch_pending = 0
target_warmed_before_click = 0
for row in browser_rows:
    if row.get("error") or not str(row.get("target_status", "")).startswith("2"):
        browser_errors += 1
    blocked_hints += int(float(row.get("blocked_hint_count") or 0))
    warm_fetch_requests += int(float(row.get("warm_fetch_request_count") or 0))
    intent_warm_fetch_requests += int(float(row.get("intent_warm_fetch_count") or 0))
    warm_fetch_ok += int(float(row.get("warm_fetch_ok_count") or 0))
    warm_fetch_errors += int(float(row.get("warm_fetch_error_count") or 0))
    warm_fetch_pending += int(float(row.get("warm_fetch_pending_count") or 0))
    target_warmed_before_click += 1 if str(row.get("target_warmed_before_click", "")).lower() == "true" else 0
    browser_by_host[row["host"]][row["prefetch_state"]].append(float(row.get("target_total_ms") or 0))

pre_restarts = {
    (item["namespace"], item["pod"]): int(item.get("restartCount") or 0)
    for item in preflight.get("podRestarts", [])
}
restart_delta = 0
for item in postflight.get("podRestarts", []):
    key = (item["namespace"], item["pod"])
    restart_delta += max(0, int(item.get("restartCount") or 0) - pre_restarts.get(key, 0))

homepage_help_hosts = 0
homepage_compared_hosts = 0
homepage_lines = []
for host in sorted(homepage_by_host):
    on = homepage_by_host[host].get("warmer_on", [])
    off = homepage_by_host[host].get("warmer_off", [])
    on_p50 = percentile(on, 0.50)
    on_p95 = percentile(on, 0.95)
    off_p50 = percentile(off, 0.50)
    off_p95 = percentile(off, 0.95)
    improvement = None
    if on_p95 is not None and off_p95 not in (None, 0):
        improvement = ((off_p95 - on_p95) / off_p95) * 100
        homepage_compared_hosts += 1
        if improvement >= 25:
            homepage_help_hosts += 1
    homepage_lines.append((host, on_p50, on_p95, off_p50, off_p95, improvement))

browser_help_hosts = 0
browser_compared_hosts = 0
browser_lines = []
for host in sorted(browser_by_host):
    enabled = browser_by_host[host].get("enabled", [])
    disabled = browser_by_host[host].get("disabled", [])
    enabled_p50 = percentile(enabled, 0.50)
    enabled_p95 = percentile(enabled, 0.95)
    disabled_p50 = percentile(disabled, 0.50)
    disabled_p95 = percentile(disabled, 0.95)
    improvement = None
    if enabled_p50 is not None and disabled_p50 not in (None, 0):
        improvement = ((disabled_p50 - enabled_p50) / disabled_p50) * 100
        browser_compared_hosts += 1
        if improvement >= 15:
            browser_help_hosts += 1
    browser_lines.append((host, enabled_p50, enabled_p95, disabled_p50, disabled_p95, improvement))

hurts = homepage_errors > 0 or browser_errors > 0 or blocked_hints > 0 or restart_delta > 0
helps = (
    (homepage_compared_hosts > 0 and homepage_help_hosts > homepage_compared_hosts / 2)
    or (browser_compared_hosts > 0 and browser_help_hosts > browser_compared_hosts / 2)
)

if hurts:
    recommendation = "hurts"
elif helps:
    recommendation = "helps"
else:
    recommendation = "neutral"

if smoke_mode:
    recommendation = "smoke-only"

lines = []
lines.append("# nopCommerce Cache Pilot Test Summary")
lines.append("")
lines.append(f"- Report directory: `{report}`")
lines.append(f"- Start: `{preflight.get('timestamp')}`")
lines.append(f"- End: `{postflight.get('timestamp')}`")
lines.append(f"- Ingress IP: `{preflight.get('ingressIp')}`")
lines.append(f"- Smoke mode: `{smoke_mode}`")
lines.append(f"- Original warmer suspend state restored: `{postflight.get('warmerSuspend') == preflight.get('warmerSuspend')}`")
lines.append(f"- Homepage errors: `{homepage_errors}`")
lines.append(f"- Browser journey errors: `{browser_errors}`")
lines.append(f"- Blocked warm/preconnect hints: `{blocked_hints}`")
lines.append(f"- Warm fetch requests: `{warm_fetch_requests}`")
lines.append(f"- Intent warm fetch requests: `{intent_warm_fetch_requests}`")
lines.append(f"- Warm fetches completed OK before click: `{warm_fetch_ok}`")
lines.append(f"- Warm fetches errored/pending before click: `{warm_fetch_errors}/{warm_fetch_pending}`")
lines.append(f"- Clicked targets warmed before click: `{target_warmed_before_click}`")
lines.append(f"- Pod restart delta: `{restart_delta}`")
lines.append(f"- Recommendation: `{recommendation}`")
lines.append("")
lines.append("## Homepage Warmer A/B")
lines.append("")
lines.append("| Host | ON p50 s | ON p95 s | OFF p50 s | OFF p95 s | p95 improvement |")
lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
for host, on_p50, on_p95, off_p50, off_p95, improvement in homepage_lines:
    lines.append(
        f"| `{host}` | {fmt(on_p50)} | {fmt(on_p95)} | {fmt(off_p50)} | {fmt(off_p95)} | {fmt(improvement, '%')} |"
    )

lines.append("")
lines.append("## Browser Warm-Fetch A/B")
lines.append("")
lines.append("| Host | Enabled p50 ms | Enabled p95 ms | Disabled p50 ms | Disabled p95 ms | p50 improvement |")
lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
for host, enabled_p50, enabled_p95, disabled_p50, disabled_p95, improvement in browser_lines:
    lines.append(
        f"| `{host}` | {fmt(enabled_p50)} | {fmt(enabled_p95)} | {fmt(disabled_p50)} | {fmt(disabled_p95)} | {fmt(improvement, '%')} |"
    )

lines.append("")
lines.append("## Hosts")
lines.append("")
for host in preflight.get("hosts", []):
    lines.append(f"- `{host}`")

(report / "summary.md").write_text("\n".join(lines) + "\n")
PY
}

main() {
  trap restore_warmer_state EXIT INT TERM

  mkdir -p "$REPORT_DIR"
  cd "$REPO_ROOT"
  log "Writing cache test report to ${REPORT_DIR}"

  ensure_context
  discover_hosts
  discover_ingress_ip

  ORIGINAL_WARMER_SUSPEND="$(warmer_suspend_state)"
  RESTORE_WARMER_STATE="true"
  log "Original warmer suspend state: ${ORIGINAL_WARMER_SUSPEND}"

  if [ "$BROWSER_ONLY" = "true" ]; then
    [ -f "${REPORT_DIR}/homepage-warmer.csv" ] || die "Browser-only mode requires existing ${REPORT_DIR}/homepage-warmer.csv"
    [ -f "${REPORT_DIR}/preflight.json" ] || write_snapshot "preflight" "${REPORT_DIR}/preflight.json"
    assert_deployments_ready "${REPORT_DIR}/preflight-deployments.json"

    run_browser_ab

    restore_warmer_state
    RESTORE_WARMER_STATE="false"
    write_snapshot "postflight" "${REPORT_DIR}/postflight.json"
    assert_deployments_ready "${REPORT_DIR}/postflight-deployments.json"

    generate_summary
    return
  fi

  write_csv_header

  write_snapshot "preflight" "${REPORT_DIR}/preflight.json"
  assert_deployments_ready "${REPORT_DIR}/preflight-deployments.json"

  log "Running preflight all-host smoke"
  measure_all_homepages "preflight_smoke" 0

  run_homepage_ab
  run_browser_ab

  restore_warmer_state
  RESTORE_WARMER_STATE="false"
  write_snapshot "postflight" "${REPORT_DIR}/postflight.json"
  assert_deployments_ready "${REPORT_DIR}/postflight-deployments.json"

  generate_summary
  log "Cache pilot test complete: ${REPORT_DIR}/summary.md"
}

main "$@"
