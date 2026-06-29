#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-297b2389-33bf-48c8-8deb-0b92838431e4}"
AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-rg-os-sandbox-drtest-qa}"
AKS_NAME="${AKS_NAME:-aks-os-drtest-qa-01}"
GET_AKS_CREDENTIALS="${GET_AKS_CREDENTIALS:-true}"

THEME_NAME="${THEME_NAME:-auto}"
PREFETCH_SCRIPT_NAME="${PREFETCH_SCRIPT_NAME:-opensoft-prefetch.js}"
RESTART_DEPLOYMENTS="${RESTART_DEPLOYMENTS:-true}"
WAIT_FOR_ROLLOUT="${WAIT_FOR_ROLLOUT:-true}"

CACHE_NAMESPACE="${CACHE_NAMESPACE:-nopcommerce-cache}"
WARMER_NAME="${WARMER_NAME:-opensoft-nopcommerce-homepage-warmer}"
WARMER_IMAGE="${WARMER_IMAGE:-curlimages/curl:8.10.1}"
WARMER_SCHEDULE="${WARMER_SCHEDULE:-*/2 * * * *}"
RUN_WARMER_NOW="${RUN_WARMER_NOW:-true}"
WARMER_STRICT_FAILURES="${WARMER_STRICT_FAILURES:-false}"

if [ -n "${AZ_CMD:-}" ]; then
  read -r -a AZ <<< "$AZ_CMD"
elif [ -x /opt/az/bin/python3 ] && [ -f /tmp/azfixed.py ]; then
  AZ=(/opt/az/bin/python3 /tmp/azfixed.py)
else
  AZ=(az)
fi

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

require_tool() {
  command -v "$1" >/dev/null || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

ensure_context() {
  require_tool kubectl
  require_tool jq

  if [ "$GET_AKS_CREDENTIALS" = "true" ]; then
    log "Selecting subscription ${SUBSCRIPTION_ID}"
    "${AZ[@]}" account set --subscription "$SUBSCRIPTION_ID"

    log "Loading AKS credentials for ${AKS_NAME}"
    "${AZ[@]}" aks get-credentials \
      --resource-group "$AKS_RESOURCE_GROUP" \
      --name "$AKS_NAME" \
      --overwrite-existing \
      --output none
  fi
}

write_prefetch_script() {
  local namespace="$1"
  local pod="$2"
  local theme="$3"
  local script_path="/app/Themes/${theme}/Content/scripts/${PREFETCH_SCRIPT_NAME}"

  kubectl -n "$namespace" exec -i "$pod" -- sh -c "
set -eu
mkdir -p '/app/Themes/${theme}/Content/scripts'
tmp=\$(mktemp)
cat > \"\$tmp\"
if [ ! -f '$script_path' ] || ! cmp -s \"\$tmp\" '$script_path'; then
  cat \"\$tmp\" > '$script_path'
  echo changed
else
  echo unchanged
fi
rm -f \"\$tmp\"
" <<'JS'
(function () {
  "use strict";

  if (window.__opensoftWarmFetchInstalled) {
    return;
  }
  window.__opensoftWarmFetchInstalled = true;

  var cfg = {
    maxIdlePages: 1,
    allowIntentWarm: true,
    pageDelayMs: 700,
    fetchTimeoutMs: 12000,
    aboveFoldFactor: 1.15,
    debugKey: "osPrefetchDebug"
  };

  var hostRules = [
    {
      pattern: /(^|\.)digiwrap\.davinci-designer\.com$/i,
      maxIdlePages: 3,
      allowIntentWarm: true
    },
    {
      pattern: /(^|\.)overnightprints\.eu$/i,
      maxIdlePages: 1
    },
    {
      pattern: /^staging\.rentapress\.com$/i,
      maxIdlePages: 2
    },
    {
      pattern: /^eds\d+\.qa\.davincisite\.com$/i,
      maxIdlePages: 2
    }
  ];

  hostRules.some(function (rule) {
    if (rule.pattern.test(window.location.hostname)) {
      Object.keys(rule).forEach(function (key) {
        if (key !== "pattern") {
          cfg[key] = rule[key];
        }
      });
      return true;
    }
    return false;
  });

  var connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection || {};
  if (connection.saveData || /(^|-)2g$/i.test(connection.effectiveType || "")) {
    return;
  }

  var skippedPaths = [
    /^\/admin(?:\/|$)/i,
    /^\/login(?:\/|$)/i,
    /^\/register(?:\/|$)/i,
    /^\/logout(?:\/|$)/i,
    /^\/cart(?:\/|$)/i,
    /^\/wishlist(?:\/|$)/i,
    /^\/checkout(?:\/|$)/i,
    /^\/customer(?:\/|$)/i,
    /^\/order(?:\/|$)/i,
    /^\/passwordrecovery(?:\/|$)/i,
    /^\/search(?:\/|$)/i
  ];

  var hinted = {};
  var pageState = {};
  var warmControllers = {};
  window.__opensoftWarmFetches = window.__opensoftWarmFetches || [];

  function debug() {
    try {
      if (window.localStorage && localStorage.getItem(cfg.debugKey) === "1") {
        console.debug.apply(console, ["[opensoft-prefetch]"].concat([].slice.call(arguments)));
      }
    } catch (e) {
      return;
    }
  }

  function absoluteUrl(value, base) {
    try {
      if (!value || value === "null" || value === "undefined") {
        return null;
      }
      return new URL(value, base || window.location.href);
    } catch (e) {
      return null;
    }
  }

  function normalizedPath(pathname) {
    return (pathname || "/").replace(/^\/[a-z]{2}(?:-[a-z]{2})?(?=\/|$)/i, "") || "/";
  }

  function shouldSkipPage(url) {
    if (!url || url.origin !== window.location.origin) {
      return true;
    }

    var path = normalizedPath(url.pathname);
    var currentPath = normalizedPath(window.location.pathname);

    if (path === currentPath && !url.search) {
      return true;
    }
    if (url.hash && path === currentPath && url.search === window.location.search) {
      return true;
    }
    if (url.search) {
      return true;
    }
    if (/\.(?:avif|bmp|css|csv|docx?|gif|ico|jpe?g|js|json|pdf|png|svg|webp|xlsx?|xml|zip)$/i.test(path)) {
      return true;
    }
    return skippedPaths.some(function (pattern) {
      return pattern.test(path);
    });
  }

  function visibleNearFold(anchor) {
    var rect = anchor.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && rect.bottom >= 0 && rect.top <= window.innerHeight * cfg.aboveFoldFactor;
  }

  function addHint(rel, href, asType) {
    var cleanHref = String(href || "").split(/[?#]/)[0];

    if (!href || hinted[rel + " " + href]) {
      return;
    }
    if (/^(?:null|undefined)$/i.test(cleanHref) || /\/(?:null|undefined)$/i.test(cleanHref)) {
      return;
    }

    hinted[rel + " " + href] = true;

    var link = document.createElement("link");
    link.rel = rel;
    link.href = href;
    if (asType) {
      link.as = asType;
    }
    if (/^https:\/\/[^/]+\.blob\.core\.windows\.net\//i.test(href)) {
      link.crossOrigin = "anonymous";
    }
    document.head.appendChild(link);
  }

  function preconnectFor(url) {
    if (!url || url.origin === window.location.origin) {
      return;
    }
    addHint("dns-prefetch", url.origin);
    addHint("preconnect", url.origin);
  }

  function srcsetUrls(srcset, base) {
    if (!srcset) {
      return [];
    }
    return srcset.split(",").map(function (candidate) {
      return absoluteUrl(candidate.trim().split(/\s+/)[0], base);
    }).filter(Boolean);
  }

  function isMediaCandidate(url) {
    if (!url) {
      return false;
    }
    if (/^https:\/\/[^/]+\.blob\.core\.windows\.net\//i.test(url.href)) {
      return true;
    }
    if (url.origin === window.location.origin && /\/(?:images|files|sitemaps)\//i.test(url.pathname)) {
      return true;
    }
    return /\.(?:avif|gif|jpe?g|png|svg|webp)$/i.test(url.pathname);
  }

  function currentPageMediaHints() {
    [].slice.call(document.querySelectorAll("img, source")).forEach(function (node) {
      var values = [];
      if (node.currentSrc) {
        values.push(node.currentSrc);
      }
      if (node.src) {
        values.push(node.src);
      }
      if (node.getAttribute("data-src")) {
        values.push(node.getAttribute("data-src"));
      }
      srcsetUrls(node.getAttribute("srcset") || node.getAttribute("data-srcset"), window.location.href).forEach(function (url) {
        values.push(url.href);
      });

      values.map(function (value) {
        return absoluteUrl(value);
      }).filter(Boolean).forEach(preconnectFor);
    });
  }

  function markPage(url) {
    try {
      sessionStorage.setItem("osPrefetch:" + url.href, "1");
    } catch (e) {
      return;
    }
  }

  function pageAlreadyMarked(url) {
    try {
      return sessionStorage.getItem("osPrefetch:" + url.href) === "1";
    } catch (e) {
      return false;
    }
  }

  function warmPage(url, reason, priority) {
    if (!url || shouldSkipPage(url) || pageState[url.href] === "warming" || pageState[url.href] === "warmed" || pageAlreadyMarked(url)) {
      return;
    }
    pageState[url.href] = "warming";

    var controller = window.AbortController ? new AbortController() : null;
    var timeoutId = controller ? window.setTimeout(function () {
      controller.abort();
    }, cfg.fetchTimeoutMs) : null;
    var startedAt = Date.now();
    var record = {
      href: url.href,
      reason: reason || "idle",
      priority: priority || "low",
      startedAt: startedAt,
      ok: false,
      status: 0,
      elapsedMs: 0,
      abortReason: "",
      error: ""
    };
    window.__opensoftWarmFetches.push(record);
    if (controller) {
      warmControllers[url.href] = {
        controller: controller,
        record: record
      };
    }

    fetch(url.href, {
      credentials: "same-origin",
      cache: "force-cache",
      priority: priority || "low",
      signal: controller ? controller.signal : undefined
    }).then(function (response) {
      record.status = response.status;
      record.ok = response.ok;
      return response.text().catch(function () {
        return "";
      }).then(function () {
        record.elapsedMs = Date.now() - startedAt;
        return response.ok;
      });
    }).then(function (ok) {
      if (ok) {
        pageState[url.href] = "warmed";
        markPage(url);
        debug("warmed", url.href, reason || "idle", record.elapsedMs);
      } else {
        delete pageState[url.href];
      }
    }).catch(function (error) {
      record.error = error && error.message ? error.message : String(error);
      record.elapsedMs = Date.now() - startedAt;
      delete pageState[url.href];
      debug("skip", url.href, record.error);
    }).then(function () {
      delete warmControllers[url.href];
      if (timeoutId) {
        window.clearTimeout(timeoutId);
      }
    });
  }

  function abortWarmPage(url, reason) {
    var active = url && warmControllers[url.href];
    if (!active) {
      return;
    }
    active.record.abortReason = reason || "navigation";
    active.record.elapsedMs = Date.now() - active.record.startedAt;
    active.controller.abort();
    delete warmControllers[url.href];
    delete pageState[url.href];
  }

  function collectLikelyLinks() {
    var seen = {};
    return [].slice.call(document.querySelectorAll("a[href]")).filter(function (anchor) {
      var url = absoluteUrl(anchor.getAttribute("href"));
      if (shouldSkipPage(url) || !visibleNearFold(anchor) || seen[url.href]) {
        return false;
      }
      seen[url.href] = true;
      return true;
    }).slice(0, cfg.maxIdlePages).map(function (anchor) {
      return absoluteUrl(anchor.getAttribute("href"));
    }).filter(Boolean);
  }

  function run() {
    currentPageMediaHints();
    if (cfg.maxIdlePages <= 0) {
      debug("idle warming disabled", window.location.hostname);
      return;
    }
    collectLikelyLinks().forEach(function (url, index) {
      window.setTimeout(function () {
        warmPage(url, "idle", "low");
      }, cfg.pageDelayMs * index);
    });
  }

  function warmIntent(event) {
    if (!cfg.allowIntentWarm) {
      return;
    }
    var anchor = event.target && event.target.closest ? event.target.closest("a[href]") : null;
    var url = anchor ? absoluteUrl(anchor.getAttribute("href")) : null;
    if (!shouldSkipPage(url)) {
      warmPage(url, "intent", "high");
    }
  }

  document.addEventListener("pointerover", warmIntent, { capture: true, passive: true });
  document.addEventListener("mouseover", warmIntent, { capture: true, passive: true });
  document.addEventListener("focusin", warmIntent, { capture: true, passive: true });
  document.addEventListener("touchstart", warmIntent, { capture: true, passive: true });
  document.addEventListener("click", function (event) {
    var anchor = event.target && event.target.closest ? event.target.closest("a[href]") : null;
    var url = anchor ? absoluteUrl(anchor.getAttribute("href")) : null;
    abortWarmPage(url, "click");
  }, { capture: true });

  if ("requestIdleCallback" in window) {
    window.requestIdleCallback(run, { timeout: 4000 });
  } else {
    window.setTimeout(run, 1500);
  }
})();
JS
}

patch_theme_head() {
  local namespace="$1"
  local pod="$2"
  local theme="$3"
  local head_path="/app/Themes/${theme}/Views/Shared/Head.cshtml"
  local script_url="~/Themes/${theme}/Content/scripts/${PREFETCH_SCRIPT_NAME}"

  kubectl -n "$namespace" exec "$pod" -- sh -lc "
set -eu
head_path='$head_path'
script_url='$script_url'
script_line='        <script src=\"'\"\$script_url\"'\" asp-location=\"Footer\"></script>'

if grep -q '$PREFETCH_SCRIPT_NAME' \"\$head_path\"; then
  echo unchanged
  exit 0
fi

tmp=\"\${head_path}.tmp\"
if grep -q 'venture.js' \"\$head_path\"; then
  awk -v insert=\"\$script_line\" '
    { print }
    /venture\\.js/ && !done { print insert; done=1 }
  ' \"\$head_path\" > \"\$tmp\"
else
  awk -v insert=\"\$script_line\" '
    /^}$/ && !done { print insert; done=1 }
    { print }
    END { if (!done) print insert }
  ' \"\$head_path\" > \"\$tmp\"
fi
cat \"\$tmp\" > \"\$head_path\"
rm -f \"\$tmp\"
echo changed
"
}

patch_theme_loader_script() {
  local namespace="$1"
  local pod="$2"
  local theme="$3"
  local loader_path="/app/Themes/${theme}/Content/js/onp-theme-script.js"
  local script_url="/Themes/${theme}/Content/scripts/${PREFETCH_SCRIPT_NAME}"

  kubectl -n "$namespace" exec "$pod" -- sh -lc "
set -eu
loader_path='$loader_path'
script_url='$script_url'

if [ ! -f \"\$loader_path\" ]; then
  echo unchanged
  exit 0
fi

if ! grep -q 'OpenSoftPrefetchLoader' \"\$loader_path\"; then
  echo unchanged
  exit 0
fi

tmp=\"\${loader_path}.tmp\"
grep -v 'OpenSoftPrefetchLoader' \"\$loader_path\" > \"\$tmp\"
cat \"\$tmp\" > \"\$loader_path\"
rm -f \"\$tmp\"
echo changed
"
}

discover_nop_deployments() {
  kubectl get deploy -A -o json | jq -r '
    .items[]
    | select(any(.spec.template.spec.containers[]?; ((.image // "") | test("nopcommerce"; "i"))))
    | [.metadata.namespace, .metadata.name]
    | @tsv
  ' | sort
}

selector_for_deployment() {
  local namespace="$1"
  local deployment="$2"
  kubectl -n "$namespace" get deploy "$deployment" -o json | jq -r '
    .spec.selector.matchLabels
    | to_entries
    | map(.key + "=" + .value)
    | join(",")
  '
}

running_pod_for_deployment() {
  local namespace="$1"
  local deployment="$2"
  local selector
  selector="$(selector_for_deployment "$namespace" "$deployment")"
  kubectl -n "$namespace" get pod \
    -l "$selector" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

discover_theme_names() {
  local namespace="$1"
  local pod="$2"

  if [ "$THEME_NAME" != "auto" ]; then
    printf '%s\n' "$THEME_NAME"
    return
  fi

  kubectl -n "$namespace" exec "$pod" -- sh -lc '
set -eu
for head in /app/Themes/*/Views/Shared/Head.cshtml; do
  [ -f "$head" ] || continue
  theme="${head#/app/Themes/}"
  theme="${theme%%/*}"
  printf "%s\n" "$theme"
done
' | sort -u
}

patch_all_themes() {
  local patched_file
  local deduped_file
  local namespace deployment pod theme script_state head_state loader_state
  patched_file="$(mktemp)"
  deduped_file="$(mktemp)"

  while IFS=$'\t' read -r namespace deployment; do
    [ -n "$namespace" ] || continue
    pod="$(running_pod_for_deployment "$namespace" "$deployment")"
    if [ -z "$pod" ]; then
      log "Skipping ${namespace}/${deployment}; no running pod found"
      continue
    fi

    themes="$(discover_theme_names "$namespace" "$pod")"
    if [ -z "$themes" ]; then
      log "Skipping ${namespace}/${deployment}; no mounted theme Head.cshtml files found"
      continue
    fi

    while IFS= read -r theme; do
      [ -n "$theme" ] || continue
      log "Installing ${PREFETCH_SCRIPT_NAME} in ${namespace}/${deployment} theme ${theme}"
      script_state="$(write_prefetch_script "$namespace" "$pod" "$theme" | tail -n 1)"
      head_state="$(patch_theme_head "$namespace" "$pod" "$theme" | tail -n 1)"
      loader_state="$(patch_theme_loader_script "$namespace" "$pod" "$theme" | tail -n 1)"
      if [ "$script_state" = "changed" ] || [ "$head_state" = "changed" ] || [ "$loader_state" = "changed" ]; then
        printf '%s\t%s\n' "$namespace" "$deployment" >> "$patched_file"
      else
        log "${namespace}/${deployment} theme ${theme} already has current prefetch script"
      fi
    done <<< "$themes"
  done < <(discover_nop_deployments)

  if [ ! -s "$patched_file" ]; then
    log "No deployments were patched"
    rm -f "$deduped_file"
    rm -f "$patched_file"
    return
  fi

  if [ "$RESTART_DEPLOYMENTS" = "true" ]; then
    sort -u "$patched_file" > "$deduped_file"
    while IFS=$'\t' read -r namespace deployment; do
      log "Restarting ${namespace}/${deployment}"
      kubectl -n "$namespace" rollout restart "deployment/${deployment}"
      if [ "$WAIT_FOR_ROLLOUT" = "true" ]; then
        kubectl -n "$namespace" rollout status "deployment/${deployment}" --timeout=10m
      fi
    done < "$deduped_file"
  fi

  rm -f "$deduped_file"
  rm -f "$patched_file"
}

discover_ingress_hosts() {
  kubectl get ingress -A -o json | jq -r '
    .items[]
    | .spec.rules[]?
    | .host
    | select(. != null and . != "")
  ' | sort -u
}

apply_homepage_warmer() {
  local hosts_file
  hosts_file="$(mktemp)"
  discover_ingress_hosts > "$hosts_file"

  if [ ! -s "$hosts_file" ]; then
    log "No ingress hosts found; skipping homepage warmer"
    rm -f "$hosts_file"
    return
  fi

  log "Applying homepage warmer for $(wc -l < "$hosts_file" | tr -d ' ') ingress hosts"

  kubectl create namespace "$CACHE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$CACHE_NAMESPACE" create configmap "${WARMER_NAME}-hosts" \
    --from-file=hosts.txt="$hosts_file" \
    --dry-run=client -o yaml | kubectl apply -f -

  cat <<YAML | kubectl -n "$CACHE_NAMESPACE" apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${WARMER_NAME}
  labels:
    app.kubernetes.io/name: nopcommerce-homepage-warmer
    app.kubernetes.io/part-of: opensoft-nopcommerce-cache-pilot
spec:
  schedule: "${WARMER_SCHEDULE}"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        metadata:
          labels:
            app.kubernetes.io/name: nopcommerce-homepage-warmer
            app.kubernetes.io/part-of: opensoft-nopcommerce-cache-pilot
        spec:
          restartPolicy: Never
          containers:
            - name: warmer
              image: ${WARMER_IMAGE}
              imagePullPolicy: IfNotPresent
              command:
                - sh
                - -c
                - |
                  set -eu
                  status=0
                  while IFS= read -r host || [ -n "\$host" ]; do
                    [ -n "\$host" ] || continue
                    if result=\$(curl -k -L -sS \\
                      --max-time 45 \\
                      --connect-timeout 8 \\
                      --retry 1 \\
                      --retry-delay 2 \\
                      --connect-to "\${host}:443:ingress-nginx-controller.ingress-nginx.svc.cluster.local:443" \\
                      -A "OpenSoft-Homepage-Warmer/1.0" \\
                      -o /dev/null \\
                      -w '%{http_code} %{time_total}s\n' \\
                      "https://\${host}/" 2>&1); then
                      printf '%s %s\n' "\$host" "\$result"
                    else
                      printf '%s ERROR %s\n' "\$host" "\$result"
                      status=1
                    fi
                  done < /config/hosts.txt
                  if [ "${WARMER_STRICT_FAILURES}" = "true" ]; then
                    exit "\$status"
                  fi
                  exit 0
              resources:
                requests:
                  cpu: 25m
                  memory: 32Mi
                limits:
                  cpu: 250m
                  memory: 128Mi
              volumeMounts:
                - name: hosts
                  mountPath: /config
                  readOnly: true
          volumes:
            - name: hosts
              configMap:
                name: ${WARMER_NAME}-hosts
YAML

  rm -f "$hosts_file"
}

run_warmer_now() {
  local job_name
  if [ "$RUN_WARMER_NOW" != "true" ]; then
    return
  fi

  job_name="${WARMER_NAME}-manual-$(date -u +%Y%m%d%H%M%S)"
  log "Running homepage warmer once as ${job_name}"
  kubectl -n "$CACHE_NAMESPACE" create job "$job_name" --from="cronjob/${WARMER_NAME}" >/dev/null
  kubectl -n "$CACHE_NAMESPACE" wait --for=condition=complete "job/${job_name}" --timeout=5m
  kubectl -n "$CACHE_NAMESPACE" logs "job/${job_name}"
}

main() {
  ensure_context
  patch_all_themes
  apply_homepage_warmer
  run_warmer_now
  log "Cache pilot applied"
}

main "$@"
