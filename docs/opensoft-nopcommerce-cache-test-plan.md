# OpenSoft nopCommerce Cache Effectiveness Test Plan

This plan defines how to autonomously measure whether the OpenSoft QA
nopCommerce cache pilot is helping. The target cache pilot has two coordinated
layers:

- a server-first in-cluster warmer CronJob,
  `nopcommerce-cache/opensoft-nopcommerce-homepage-warmer`
- a theme-level browser lazy warmer script, `opensoft-prefetch.js`, as the
  secondary layer

The goal is to collect real comparative data, not just prove that the scripts
run.

The optimization decisions and interpretation of the results live in
`docs/nopcommerce-performance-optimization.md`. This file is only the repeatable
test plan.

## Test Objective

Determine whether the cache pilot improves user-visible performance without
raising errors, causing bad prefetch behavior, or increasing app instability.

The first evidence run should answer:

- Does server warming materially improve homepage and top landing page TTFB and
  total time?
- Does browser lazy warming add benefit after the server cache is already warm?
- Are any protected or user-specific paths being warmed?
- Are the restored sites stable while the test runs?
- Should we keep, tune, or remove the cache pilot?

## Current Target

Use the current OpenSoft QA DR stack:

```text
Tenant: OpenSoftOne / OpensoftOne.onmicrosoft.com
Subscription: sub-os-qa-platform / 297b2389-33bf-48c8-8deb-0b92838431e4
AKS: aks-os-drtest-qa-01
AKS resource group: rg-os-sandbox-drtest-qa
Ingress public IP: 172.185.27.29
Cache namespace: nopcommerce-cache
Warmer CronJob: opensoft-nopcommerce-homepage-warmer
```

The test runner should run from `cloudBench` and use the same Azure/Kubernetes
wrapper pattern used by the restore and cache pilot scripts.

## CloudPC No-VPN Validation

Run this test from the CloudPC, not from Brett's local Windows/WSL/VPN path. The
purpose is to isolate the client network path. This test does not decide the
whole cache pilot; it answers whether the poor timings seen locally were caused
or amplified by VPN, split tunnel, WSL, local browser, or local ISP routing.

Use the CloudPC with no corporate VPN session active unless the CloudPC itself
requires one for management. Run from the `cloudBench` container/session on that
CloudPC so the toolchain is close to the normal OpenSoft Azure workflow.

### Question This Test Answers

Compare these client paths:

```text
Local machine / WSL / VPN path
CloudPC / no-VPN path
```

The main signal is not whether the site is globally fast. The main signal is
whether the CloudPC sees materially lower and more stable timings for:

- homepage HTML
- large CSS and JavaScript bundles
- direct Blob media
- same-origin NFS media
- the DigiWrap DR alias that has the exact-homepage memory cache

If the CloudPC is much faster and has fewer SSL/timeouts, treat the local
VPN/split-tunnel/client route as a major contributor. If the CloudPC is also
slow, focus on Azure ingress, AKS, nopCommerce, storage, bundle weight, and app
configuration.

### CloudPC Preflight

From the CloudPC Claude/Codex session, enter `cloudBench` and run:

```bash
cd /home/brett/projects/workBenches
git pull --ff-only

RUN_ID="cloudpc-novpn-$(date -u +%Y%m%dT%H%M%SZ)"
OUT="reports/cache-pilot/${RUN_ID}"
mkdir -p "$OUT"

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "hostname=$(hostname)"
  echo "public_ip=$(curl -fsS --max-time 10 https://api.ipify.org || true)"
  echo "public_ip_alt=$(curl -fsS --max-time 10 https://ifconfig.me || true)"
  echo
  echo "proxy_env:"
  env | sort | grep -Ei '^(http|https|all|no)_proxy=' || true
  echo
  echo "dns:"
  getent hosts digiwrap.davinci-designer.com || true
  getent hosts digiwrap.qa.davincisite.com || true
  getent hosts stosnopmediaqa01.blob.core.windows.net || true
  echo
  echo "route:"
  ip route || true
} | tee "$OUT/preflight-network.txt"
```

Save this preflight with the results. It proves where the test ran from and
helps us see whether a proxy or VPN-like route is still present.

### CloudPC HTTP Timing Probe

Run this copy-paste probe from the same CloudPC `cloudBench` shell:

```bash
cd /home/brett/projects/workBenches
RUN_ID="${RUN_ID:-cloudpc-novpn-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="reports/cache-pilot/${RUN_ID}"
mkdir -p "$OUT"

python3 - <<'PY' | tee "$OUT/http-resource-timing.csv"
import csv
import re
import statistics
import sys
import time
from html.parser import HTMLParser
from urllib.parse import urljoin
from urllib.parse import urlparse

import requests

ITERATIONS = 5
TIMEOUT = 90
UA = "OpenSoftCloudPCNoVPN/1.0"

homes = {
    "digiwrap_dr_alias": "https://digiwrap.davinci-designer.com/",
    "digiwrap_nfs_alias": "https://digiwrap.qa.davincisite.com/",
}

fixed = {
    "direct_blob_sample": "https://stosnopmediaqa01.blob.core.windows.net/digiwrap-media/0001554_digital-tissue-paper_600.jpeg",
    "nfs_sample": "https://digiwrap.qa.davincisite.com/images/thumbs/0001554_digital-tissue-paper_600.jpeg",
}

class AssetParser(HTMLParser):
    def __init__(self, base):
        super().__init__()
        self.base = base
        self.assets = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "link" and attrs.get("href"):
            rel = attrs.get("rel", "")
            href = attrs["href"]
            if "stylesheet" in rel or ".css" in href:
                self.assets.append(("css", urljoin(self.base, href)))
        if tag == "script" and attrs.get("src"):
            self.assets.append(("js", urljoin(self.base, attrs["src"])))

def fetch(session, label, url):
    started = time.time()
    try:
        r = session.get(url, timeout=TIMEOUT, headers={"User-Agent": UA})
        elapsed = time.time() - started
        return {
            "label": label,
            "url": url,
            "status": r.status_code,
            "seconds": elapsed,
            "bytes": len(r.content),
            "cache_control": r.headers.get("cache-control", ""),
            "x_home_cache": r.headers.get("x-opensoft-home-cache", ""),
            "x_media_cache": r.headers.get("x-opensoft-media-cache", ""),
            "error": "",
            "body": r.text if "text/html" in r.headers.get("content-type", "") else "",
        }
    except Exception as error:
        return {
            "label": label,
            "url": url,
            "status": "",
            "seconds": time.time() - started,
            "bytes": "",
            "cache_control": "",
            "x_home_cache": "",
            "x_media_cache": "",
            "error": str(error),
            "body": "",
        }

session = requests.Session()

fieldnames = [
    "iteration",
    "label",
    "url",
    "status",
    "seconds",
    "bytes",
    "cache_control",
    "x_home_cache",
    "x_media_cache",
    "error",
]
writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
writer.writeheader()

asset_urls = {}
for label, url in homes.items():
    result = fetch(session, f"{label}_home_discovery", url)
    parser = AssetParser(url)
    parser.feed(result["body"])
    home_host = urlparse(url).netloc
    for asset_type, asset_url in parser.assets:
        if urlparse(asset_url).netloc == home_host:
            asset_urls[f"{label}_{asset_type}"] = asset_url

targets = {**homes, **asset_urls, **fixed}

rows = []
for iteration in range(1, ITERATIONS + 1):
    for label, url in targets.items():
        row = fetch(session, label, url)
        row["iteration"] = iteration
        rows.append(row)
        writer.writerow({key: row.get(key, "") for key in fieldnames})
        sys.stdout.flush()

print("# summary", file=sys.stderr)
for label in sorted({row["label"] for row in rows}):
    scoped = [row for row in rows if row["label"] == label and not row["error"]]
    if not scoped:
        print(label, "all_error", file=sys.stderr)
        continue
    values = [row["seconds"] for row in scoped]
    print(
        label,
        "n=", len(values),
        "p50=", round(statistics.median(values), 3),
        "max=", round(max(values), 3),
        "statuses=", sorted({row["status"] for row in scoped}),
        file=sys.stderr,
    )
PY
```

This creates:

```text
reports/cache-pilot/<RUN_ID>/http-resource-timing.csv
```

The key comparisons are:

- `digiwrap_dr_alias` versus `digiwrap_nfs_alias`
- `direct_blob_sample` versus `nfs_sample`
- DR alias CSS/JS bundle timings versus NFS alias CSS/JS bundle timings
- error count, especially SSL EOF, TLS timeout, and connect timeout errors

### Optional Browser Probe

If the CloudPC `cloudBench` environment has Node plus Playwright/Chrome
available, also run the browser resource comparison:

```bash
cd /home/brett/projects/workBenches
RUN_ID="${RUN_ID:-cloudpc-novpn-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="reports/cache-pilot/${RUN_ID}/browser-image-compare"
mkdir -p "$OUT"

NODE_PATH="${NODE_PATH:-/mnt/c/Users/brett.heap/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/.pnpm/node_modules:/mnt/c/Users/brett.heap/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules}" \
NOP_IMAGE_COMPARE_OUTPUT_DIR="$OUT" \
node scripts/lib/nopcommerce-homepage-image-compare.js
```

If Playwright/Chrome is not installed in that CloudPC environment, skip this
optional browser probe. The HTTP timing probe above is the required no-VPN
evidence.

### What To Send Back

Bring back the whole report directory:

```text
reports/cache-pilot/<RUN_ID>/
```

At minimum, send:

```text
preflight-network.txt
http-resource-timing.csv
browser-image-compare/summary.md, if the optional browser probe ran
```

Interpretation rule:

- If CloudPC p50s are materially lower and max/error counts are much better
  than local WSL/VPN runs, the local VPN/split-tunnel path is the likely
  bottleneck.
- If CloudPC p50s and max timings are also poor, the bottleneck is probably in
  Azure ingress, AKS, nopCommerce, storage, or asset weight.
- If only Blob is slow from CloudPC while NFS is fast, prefer NFS or a real CDN
  edge for media delivery.
- If CSS/JS bundles are slow from CloudPC on both aliases, focus next on bundle
  size, static asset caching, compression, WebOptimizer output, and ingress
  delivery.

## Test Method

Use controlled A/B testing. Passive observation is not enough because the
cluster, browser, WebOptimizer, SQL, and TLS caches can all make the sites look
fast after any recent activity.

Default test settings:

- Total run time: about 2 hours.
- Mutation tolerance: suspend and resume the homepage warmer only.
- Do not restart nopCommerce pods during the normal A/B run.
- Do not edit themes, deployments, services, ingresses, SQL, DNS, or storage.
- Restore the original CronJob suspend state on exit, including interrupted or
  failed runs.

### Preflight

Before measuring, the runner should collect:

- all hosts from
  `nopcommerce-cache/opensoft-nopcommerce-homepage-warmer-hosts`
- current ingress IP from the `ingress-nginx` LoadBalancer service
- current warmer CronJob suspend state
- recent warmer job history and durations
- readiness for all nopCommerce deployments
- pod restart counts for all nopCommerce deployments
- one all-host HTTP smoke test through the ingress IP

Abort the test if any nopCommerce deployment is not `1/1` ready.

### Server Warmer A/B

The server warmer test should compare the same host and path list with the
warmer on and off.

For every host, warm this baseline set:

```text
/
top public landing page 1
top public landing page 2
top public landing page 3
```

The top landing pages should be configured per host. If a host does not have an
explicit list yet, the warmer may discover the first three safe public
category/product links from the homepage and use those as the temporary warm
set.

Use three repeated cycles:

1. **Warmer on**
   - Ensure the CronJob is not suspended.
   - Wait for at least three successful scheduled warmer jobs.
   - Measure every warmed path.
2. **Warmer off**
   - Suspend the CronJob.
   - Wait 15 minutes with no synthetic warmer traffic.
   - Measure every warmed path.

For each measured request, record:

- timestamp
- phase: `warmer_on` or `warmer_off`
- cycle number
- host
- URL
- HTTP status
- redirect count
- bytes downloaded
- DNS, connect, TLS, TTFB, and total time from `curl`
- curl exit code and error text, if any

Use low concurrency. The goal is a realistic browsing signal, not a load test.

### Browser Lazy Warmer A/B

Use Playwright for representative browser journeys. Test at least these hosts:

- `digiwrap.davinci-designer.com`
- `qa1.overnightprints.eu`
- `staging.rentapress.com`
- one DefaultClean site, such as `eds1.qa.davincisite.com`

The browser test should run after the server warmer test. It should not use a
primary mode where browser warming is on and server warming is off. The intended
comparison is:

- **Server warm, browser lazy warmer enabled:** target operating mode.
- **Server warm, browser lazy warmer disabled:** isolates the browser layer.

Randomize the browser enabled/disabled order per iteration to reduce cache-order
bias.

Current browser lazy warmer tuning:

- DigiWrap: three idle warm fetches for the DR alias cache-header experiment.
- Overnight Prints: one idle warm fetch.
- Rentapress: two idle warm fetches.
- EDS QA sites: two idle warm fetches.
- All other sites: one idle warm fetch.
- Abort an in-flight warm fetch when the user clicks the same URL.

Journey:

1. Open the homepage.
2. Wait for the homepage `load` event so the homepage has finished loading.
3. Wait a few quiet seconds so the test does not compete with initial page load.
4. Wait for browser idle with `requestIdleCallback` when available.
5. Capture the light preconnect hints and warm-fetch request count.
6. Pick the first eligible public product or category link visible near the top
   of the page.
7. Hover, focus, and send touch-style intent events to that exact link.
8. Wait briefly so any intent-based warming can run.
9. Click the link as a user would.
10. Record navigation timing and resource timing.

The browser lazy warmer must not start before the homepage `load` event, the
quiet wait, and browser idle. Intent warming may run only for the exact link that
the user hovers, focuses, or touches.

For browser-cache validation, use:

```bash
node scripts/lib/nopcommerce-browser-cache-probe.js
```

The probe should verify whether the warmed document navigation reports
`fromDiskCache` or `transferSize: 0`. A warm fetch that downloads successfully
but does not make the later navigation cache-backed is not sufficient evidence
that browser-side HTML warming helps.

For each browser journey, record:

- host
- start URL and clicked URL
- browser lazy warmer state: enabled or disabled
- HTTP status for homepage and clicked page
- browser navigation timing: TTFB, DOMContentLoaded, load event, total
- post-load quiet wait, idle wait method, and intent warm delay
- failed request count and URLs
- console errors and page errors
- number of browser lazy warm requests
- number of completed, errored, and pending warm fetches before click
- whether the clicked target was warmed before click
- number of preconnect hints
- blocked hint count
- first 10 hint URLs

Blocked hints are any URL containing:

```text
/admin
/login
/register
/logout
/cart
/wishlist
/checkout
/customer
/order
/passwordrecovery
/search
/null
/undefined
```

The blocked hint check must also catch localized paths such as `/en/cart`.

### Resource and Stability Snapshot

At the start and end of the run, collect:

- deployment readiness
- pod restart counts
- `kubectl top pod` output, if metrics-server is available
- recent warmer job statuses and durations
- Azure SQL CPU/DTU/storage metrics, if `az monitor metrics list` works without
  extra setup

Do not fail the whole report if Azure Monitor metrics are unavailable. The core
evidence is curl, Playwright, Kubernetes readiness, and warmer job data.

## Report Output

Write one timestamped output directory:

```text
reports/cache-pilot/<timestamp>/
```

Run the full autonomous test from `cloudBench`:

```bash
cd /home/brett/projects/workBenches
./scripts/test-opensoft-nopcommerce-cache-pilot.sh
```

Run a short implementation smoke test:

```bash
cd /home/brett/projects/workBenches
SMOKE=true COLLECT_AZURE_METRICS=false \
  BROWSER_HOSTS=digiwrap.davinci-designer.com \
  ./scripts/test-opensoft-nopcommerce-cache-pilot.sh
```

Smoke mode validates the machinery only. It intentionally uses one short ON/OFF
cycle and marks the generated `summary.md` recommendation as `smoke-only`.

Required files:

```text
summary.md
homepage-warmer.csv
browser-prefetch.csv
raw-homepage.ndjson
raw-browser.ndjson
preflight.json
postflight.json
```

`summary.md` should include:

- test start/end time
- host list
- whether the original CronJob suspend state was restored
- server warmer on/off p50 and p95 by host and path
- browser lazy warmer enabled/disabled p50 and p95 by journey, with the server
  warmer on
- error count by host and phase
- blocked hint count
- browser lazy warm count
- pod restart delta
- recommendation/classification: `helps`, `neutral`, `hurts`, or `smoke-only`

Use `helps` as evidence to keep the pilot, `neutral` as evidence to tune or
retest with a longer window, and `hurts` as evidence to remove or redesign it.

## Decision Rules

Classify the pilot as `helps` when:

- server warmer `ON` improves p95 total time by at least 20% on most warmed
  host/path combinations, or
- browser lazy warming improves next-page p50 or p95 total time by at least 15%
  over the already-warmed server baseline
- and no error or blocked-hint regression appears

Classify the pilot as `neutral` when:

- improvements are below threshold
- errors do not increase
- pod restarts do not increase
- no blocked hints appear

Classify the pilot as `hurts` when:

- HTTP errors increase
- browser journey errors increase
- timings regress by more than 10%
- blocked hints appear
- nopCommerce pod restarts increase during the test

## Acceptance Criteria

The autonomous test is acceptable when:

- it can run unattended from `cloudBench`
- it leaves the warmer CronJob in its original suspend state
- it does not restart app pods or mutate app configuration
- it produces raw data and a human-readable summary
- it can tell us whether the current cache pilot helps, is neutral, or hurts

## Assumptions

- This first test is for QA evidence, not a production traffic benchmark.
- The runner may temporarily suspend only the homepage warmer CronJob.
- The runner may create short-lived Kubernetes Jobs for measurement.
- The runner may write local report files under `reports/cache-pilot/`.
- If Azure Monitor metrics are unavailable, the report should still complete.
