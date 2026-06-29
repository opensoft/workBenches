#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-digiwrap-qa-davincisite-com}"
HOST="${HOST:-digiwrap.davinci-designer.com}"
ORIGIN_SERVICE="${ORIGIN_SERVICE:-digiwrap-qa-davincisite-com-gps}"
ORIGIN_PORT="${ORIGIN_PORT:-80}"

CACHE_NAME="${CACHE_NAME:-opensoft-homepage-memory-cache}"
CACHE_IMAGE="${CACHE_IMAGE:-node:22-alpine}"
CACHE_TTL_SECONDS="${CACHE_TTL_SECONDS:-180}"
CACHE_MAX_BYTES="${CACHE_MAX_BYTES:-1048576}"
CACHE_PATHS="${CACHE_PATHS:-/}"
INGRESS_NAME="${INGRESS_NAME:-digiwrap-davinci-designer}"
MEDIA_CACHE_ENABLED="${MEDIA_CACHE_ENABLED:-false}"
MEDIA_CACHE_BLOB_PREFIX="${MEDIA_CACHE_BLOB_PREFIX:-https://stosnopmediaqa01.blob.core.windows.net/digiwrap-media/}"
MEDIA_CACHE_PUBLIC_PATH="${MEDIA_CACHE_PUBLIC_PATH:-/__opensoft-media-cache/}"
MEDIA_CACHE_TTL_SECONDS="${MEDIA_CACHE_TTL_SECONDS:-3600}"
MEDIA_CACHE_MAX_BYTES="${MEDIA_CACHE_MAX_BYTES:-1048576}"
MEDIA_CACHE_MAX_ENTRIES="${MEDIA_CACHE_MAX_ENTRIES:-100}"

ACTION="${ACTION:-apply}"
WAIT_FOR_ROLLOUT="${WAIT_FOR_ROLLOUT:-true}"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

require_tool() {
  command -v "$1" >/dev/null || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

delete_cache() {
  log "Restoring ${INGRESS_NAME} backend to ${ORIGIN_SERVICE}"
  kubectl -n "$NAMESPACE" patch ingress "$INGRESS_NAME" --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths\",\"value\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"${ORIGIN_SERVICE}\",\"port\":{\"number\":${ORIGIN_PORT}}}}}]}]" || true

  log "Deleting homepage memory-cache service/deployment/configmap from ${NAMESPACE}"
  kubectl -n "$NAMESPACE" delete service "${CACHE_NAME}" --ignore-not-found
  kubectl -n "$NAMESPACE" delete deployment "${CACHE_NAME}" --ignore-not-found
  kubectl -n "$NAMESPACE" delete configmap "${CACHE_NAME}" --ignore-not-found
}

apply_configmap() {
  log "Applying ${CACHE_NAME} ConfigMap"
  cat <<'JS' | kubectl -n "$NAMESPACE" create configmap "${CACHE_NAME}" \
    --from-file=server.js=/dev/stdin \
    --dry-run=client -o yaml | kubectl apply -f -
"use strict";

const http = require("http");
const https = require("https");

const port = Number(process.env.PORT || "8080");
const originService = process.env.ORIGIN_SERVICE;
const originPort = Number(process.env.ORIGIN_PORT || "80");
const publicHost = process.env.PUBLIC_HOST;
const ttlMs = Number(process.env.CACHE_TTL_SECONDS || "180") * 1000;
const maxBytes = Number(process.env.CACHE_MAX_BYTES || "1048576");
const cachePaths = new Set((process.env.CACHE_PATHS || "/").split(",").map((path) => path.trim()).filter(Boolean));
const mediaCacheEnabled = String(process.env.MEDIA_CACHE_ENABLED || "false").toLowerCase() === "true";
const mediaCacheBlobPrefix = process.env.MEDIA_CACHE_BLOB_PREFIX || "";
const mediaCachePublicPath = process.env.MEDIA_CACHE_PUBLIC_PATH || "/__opensoft-media-cache/";
const mediaCacheTtlMs = Number(process.env.MEDIA_CACHE_TTL_SECONDS || "3600") * 1000;
const mediaCacheMaxBytes = Number(process.env.MEDIA_CACHE_MAX_BYTES || "1048576");
const mediaCacheMaxEntries = Number(process.env.MEDIA_CACHE_MAX_ENTRIES || "100");

let cacheEntry = null;
const mediaCache = new Map();
let stats = {
  startedAt: new Date().toISOString(),
  hits: 0,
  misses: 0,
  bypasses: 0,
  originErrors: 0,
  stores: 0,
  htmlMediaRewrites: 0,
  mediaHits: 0,
  mediaMisses: 0,
  mediaBypasses: 0,
  mediaStores: 0,
  mediaOriginErrors: 0,
};

const hopByHopHeaders = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
]);

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function cacheKeyFor(req, url) {
  return `${publicHost}:${url.pathname}`;
}

function isFresh(entry) {
  return entry && Date.now() < entry.expiresAt;
}

function shouldBypass(req, url) {
  if (req.method !== "GET" && req.method !== "HEAD") return "method";
  if (!cachePaths.has(url.pathname)) return "path";
  if (url.search) return "query";
  if (req.headers.cookie) return "cookie";
  if (req.headers.authorization) return "authorization";
  if (/\b(no-cache|no-store)\b/i.test(req.headers["cache-control"] || "")) return "request-cache-control";
  return "";
}

function writeStatus(res) {
  res.writeHead(200, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-cache, no-store",
  });
  res.end(JSON.stringify({
    stats,
    cache: cacheEntry ? {
      key: cacheEntry.key,
      bytes: cacheEntry.body.length,
      createdAt: cacheEntry.createdAtIso,
      ageSeconds: nowSeconds() - cacheEntry.createdAtSeconds,
      expiresInSeconds: Math.max(0, Math.floor((cacheEntry.expiresAt - Date.now()) / 1000)),
      statusCode: cacheEntry.statusCode,
    } : null,
    mediaCache: {
      enabled: mediaCacheEnabled,
      blobPrefix: mediaCacheBlobPrefix,
      publicPath: mediaCachePublicPath,
      entries: mediaCache.size,
      bytes: Array.from(mediaCache.values()).reduce((sum, entry) => sum + entry.body.length, 0),
    },
  }, null, 2));
}

function isInternalRequest(req) {
  const host = String(req.headers.host || "").split(":")[0].toLowerCase();
  return host !== String(publicHost || "").toLowerCase();
}

function writeNotFound(res) {
  res.writeHead(404, {
    "content-type": "text/plain; charset=utf-8",
    "cache-control": "no-cache, no-store",
    "pragma": "no-cache",
  });
  res.end("not found\n");
}

function originRequest(req, url) {
  return new Promise((resolve, reject) => {
    const headers = {};
    for (const [name, value] of Object.entries(req.headers)) {
      const lower = name.toLowerCase();
      if (!hopByHopHeaders.has(lower) && lower !== "accept-encoding") {
        headers[name] = value;
      }
    }

    headers.host = publicHost;
    headers["x-forwarded-host"] = publicHost;
    headers["x-forwarded-proto"] = "https";
    headers["x-forwarded-for"] = req.socket.remoteAddress || "";
    headers["accept-encoding"] = "identity";

    const origin = http.request({
      hostname: originService,
      port: originPort,
      method: req.method,
      path: `${url.pathname}${url.search}`,
      headers,
      timeout: 45000,
    }, (originRes) => {
      const chunks = [];
      originRes.on("data", (chunk) => chunks.push(chunk));
      originRes.on("end", () => {
        resolve({
          statusCode: originRes.statusCode || 502,
          headers: originRes.headers,
          body: Buffer.concat(chunks),
        });
      });
    });

    origin.on("timeout", () => {
      origin.destroy(new Error("origin timeout"));
    });
    origin.on("error", reject);
    origin.end();
  });
}

function fetchMedia(targetUrl) {
  return new Promise((resolve, reject) => {
    const request = https.request(targetUrl, {
      method: "GET",
      timeout: 45000,
      headers: {
        "user-agent": "OpenSoftMediaCache/1.0",
        "accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
        "accept-encoding": "identity",
      },
    }, (originRes) => {
      const chunks = [];
      originRes.on("data", (chunk) => chunks.push(chunk));
      originRes.on("end", () => {
        resolve({
          statusCode: originRes.statusCode || 502,
          headers: originRes.headers,
          body: Buffer.concat(chunks),
        });
      });
    });

    request.on("timeout", () => {
      request.destroy(new Error("media origin timeout"));
    });
    request.on("error", reject);
    request.end();
  });
}

function isMediaCachePath(url) {
  return mediaCacheEnabled && url.pathname.startsWith(mediaCachePublicPath);
}

function mediaTargetUrl(url) {
  const suffix = url.pathname.slice(mediaCachePublicPath.length);
  return `${mediaCacheBlobPrefix}${suffix}${url.search || ""}`;
}

function mediaHeaders(entry, cacheState) {
  const headers = {};
  for (const [name, value] of Object.entries(entry.headers || {})) {
    const lower = name.toLowerCase();
    if (hopByHopHeaders.has(lower)) continue;
    if (["content-length", "cache-control", "pragma", "expires"].includes(lower)) continue;
    headers[name] = value;
  }
  headers["content-length"] = String(entry.body.length);
  headers["cache-control"] = "public, max-age=31536000, immutable";
  headers["age"] = String(Math.max(0, nowSeconds() - entry.createdAtSeconds));
  headers["x-opensoft-media-cache"] = cacheState;
  headers["x-opensoft-media-cache-node"] = process.env.HOSTNAME || "unknown";
  return headers;
}

function evictMediaCacheIfNeeded() {
  while (mediaCache.size > mediaCacheMaxEntries) {
    const oldest = Array.from(mediaCache.entries())
      .sort((a, b) => a[1].createdAtSeconds - b[1].createdAtSeconds)[0];
    if (!oldest) return;
    mediaCache.delete(oldest[0]);
  }
}

async function handleMediaCache(req, res, url) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    stats.mediaBypasses += 1;
    res.writeHead(405, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-cache, no-store",
      "allow": "GET, HEAD",
      "x-opensoft-media-cache": "BYPASS-method",
    });
    res.end("method not allowed\n");
    return;
  }

  const targetUrl = mediaTargetUrl(url);
  const cached = mediaCache.get(targetUrl);
  if (cached && Date.now() < cached.expiresAt) {
    stats.mediaHits += 1;
    res.writeHead(cached.statusCode, mediaHeaders(cached, "HIT"));
    if (req.method === "HEAD") res.end();
    else res.end(cached.body);
    return;
  }

  stats.mediaMisses += 1;
  let origin;
  try {
    origin = await fetchMedia(targetUrl);
  } catch (error) {
    stats.mediaOriginErrors += 1;
    res.writeHead(502, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-cache, no-store",
      "x-opensoft-media-cache": "ERROR",
    });
    res.end(`media origin error: ${error.message}\n`);
    return;
  }

  const contentType = String(origin.headers["content-type"] || "");
  const canStoreMedia = origin.statusCode === 200 &&
    origin.body.length <= mediaCacheMaxBytes &&
    contentType.toLowerCase().startsWith("image/");
  const entry = {
    statusCode: origin.statusCode,
    headers: origin.headers,
    body: origin.body,
    createdAtSeconds: nowSeconds(),
    expiresAt: Date.now() + mediaCacheTtlMs,
  };

  if (canStoreMedia) {
    mediaCache.set(targetUrl, entry);
    evictMediaCacheIfNeeded();
    stats.mediaStores += 1;
  }

  res.writeHead(origin.statusCode, mediaHeaders(entry, canStoreMedia ? "MISS-STORE" : "MISS-BYPASS"));
  if (req.method === "HEAD") res.end();
  else res.end(origin.body);
}

function rewriteMediaUrls(origin) {
  if (!mediaCacheEnabled || !mediaCacheBlobPrefix || !mediaCachePublicPath) return origin;
  const contentType = String(origin.headers["content-type"] || "").toLowerCase();
  if (!contentType.includes("text/html")) return origin;

  const original = origin.body.toString("utf8");
  if (!original.includes(mediaCacheBlobPrefix)) return origin;

  const rewritten = original.split(mediaCacheBlobPrefix).join(mediaCachePublicPath);
  stats.htmlMediaRewrites += 1;
  return {
    ...origin,
    headers: {
      ...origin.headers,
      "content-length": undefined,
    },
    body: Buffer.from(rewritten, "utf8"),
  };
}

function responseHeadersFromOrigin(origin, cacheState) {
  const headers = {};
  for (const [name, value] of Object.entries(origin.headers)) {
    const lower = name.toLowerCase();
    if (hopByHopHeaders.has(lower)) continue;
    if (["content-length", "cache-control", "pragma", "expires"].includes(lower)) continue;
    headers[name] = value;
  }

  if (cacheState === "BYPASS") {
    headers["cache-control"] = origin.headers["cache-control"] || "no-cache, no-store";
    if (origin.headers.pragma) headers.pragma = origin.headers.pragma;
  } else if (origin.statusCode === 200) {
    headers["cache-control"] = "private, max-age=120, stale-while-revalidate=60";
  } else {
    headers["cache-control"] = "no-cache, no-store";
    headers.pragma = "no-cache";
  }

  headers["x-opensoft-home-cache"] = cacheState;
  headers["x-opensoft-home-cache-node"] = process.env.HOSTNAME || "unknown";
  return headers;
}

function cachedHeaders(entry) {
  return {
    "content-type": entry.contentType || "text/html; charset=utf-8",
    "content-language": entry.contentLanguage || "",
    "cache-control": "private, max-age=120, stale-while-revalidate=60",
    "age": String(Math.max(0, nowSeconds() - entry.createdAtSeconds)),
    "x-opensoft-home-cache": "HIT",
    "x-opensoft-home-cache-node": process.env.HOSTNAME || "unknown",
    "x-opensoft-home-cache-key": entry.key,
  };
}

function canStore(req, url, origin) {
  if (req.method !== "GET") return false;
  if (origin.statusCode !== 200) return false;
  if (origin.body.length > maxBytes) return false;
  const contentType = String(origin.headers["content-type"] || "");
  return contentType.toLowerCase().includes("text/html");
}

async function handle(req, res) {
  const url = new URL(req.url || "/", "http://cache.local");

  if (isMediaCachePath(url)) {
    await handleMediaCache(req, res, url);
    return;
  }

  if (url.pathname === "/__opensoft-cache/status") {
    if (!isInternalRequest(req)) {
      writeNotFound(res);
      return;
    }
    writeStatus(res);
    return;
  }
  if (url.pathname === "/__opensoft-cache/clear" && req.method === "POST") {
    if (!isInternalRequest(req)) {
      writeNotFound(res);
      return;
    }
    cacheEntry = null;
    res.writeHead(204, { "cache-control": "no-cache, no-store" });
    res.end();
    return;
  }

  const bypassReason = shouldBypass(req, url);
  const key = cacheKeyFor(req, url);

  if (!bypassReason && cacheEntry && cacheEntry.key === key && isFresh(cacheEntry)) {
    stats.hits += 1;
    res.writeHead(cacheEntry.statusCode, cachedHeaders(cacheEntry));
    if (req.method === "HEAD") res.end();
    else res.end(cacheEntry.body);
    return;
  }

  if (bypassReason) stats.bypasses += 1;
  else stats.misses += 1;

  let origin;
  try {
    origin = await originRequest(req, url);
    origin = rewriteMediaUrls(origin);
  } catch (error) {
    stats.originErrors += 1;
    res.writeHead(502, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-cache, no-store",
      "x-opensoft-home-cache": "ERROR",
    });
    res.end(`origin error: ${error.message}\n`);
    return;
  }

  const cacheState = bypassReason ? `BYPASS-${bypassReason}` : "MISS";
  if (!bypassReason && canStore(req, url, origin)) {
    cacheEntry = {
      key,
      statusCode: origin.statusCode,
      body: origin.body,
      contentType: origin.headers["content-type"] || "text/html; charset=utf-8",
      contentLanguage: origin.headers["content-language"] || "",
      createdAtIso: new Date().toISOString(),
      createdAtSeconds: nowSeconds(),
      expiresAt: Date.now() + ttlMs,
    };
    stats.stores += 1;
  }

  const headers = responseHeadersFromOrigin(origin, cacheState);
  if (!headers["content-length"] && req.method !== "HEAD") {
    headers["content-length"] = String(origin.body.length);
  }
  res.writeHead(origin.statusCode, headers);
  if (req.method === "HEAD") res.end();
  else res.end(origin.body);
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((error) => {
    stats.originErrors += 1;
    res.writeHead(500, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-cache, no-store",
      "x-opensoft-home-cache": "ERROR",
    });
    res.end(`cache error: ${error.message}\n`);
  });
});

server.listen(port, () => {
  console.log(`OpenSoft homepage memory cache listening on ${port}`);
  console.log(JSON.stringify({
    originService,
    originPort,
    publicHost,
    ttlMs,
    maxBytes,
    cachePaths: Array.from(cachePaths),
    mediaCacheEnabled,
    mediaCacheBlobPrefix,
    mediaCachePublicPath,
    mediaCacheTtlMs,
    mediaCacheMaxBytes,
    mediaCacheMaxEntries,
  }));
});
JS
}

apply_workload() {
  log "Applying ${CACHE_NAME} deployment and service"
  cat <<YAML | kubectl -n "$NAMESPACE" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${CACHE_NAME}
  labels:
    app.kubernetes.io/name: ${CACHE_NAME}
    app.kubernetes.io/part-of: opensoft-nopcommerce-cache-pilot
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${CACHE_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${CACHE_NAME}
        app.kubernetes.io/part-of: opensoft-nopcommerce-cache-pilot
    spec:
      containers:
        - name: cache
          image: ${CACHE_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["node", "/app/server.js"]
          env:
            - name: PORT
              value: "8080"
            - name: ORIGIN_SERVICE
              value: "${ORIGIN_SERVICE}.${NAMESPACE}.svc.cluster.local"
            - name: ORIGIN_PORT
              value: "${ORIGIN_PORT}"
            - name: PUBLIC_HOST
              value: "${HOST}"
            - name: CACHE_TTL_SECONDS
              value: "${CACHE_TTL_SECONDS}"
            - name: CACHE_MAX_BYTES
              value: "${CACHE_MAX_BYTES}"
            - name: CACHE_PATHS
              value: "${CACHE_PATHS}"
            - name: MEDIA_CACHE_ENABLED
              value: "${MEDIA_CACHE_ENABLED}"
            - name: MEDIA_CACHE_BLOB_PREFIX
              value: "${MEDIA_CACHE_BLOB_PREFIX}"
            - name: MEDIA_CACHE_PUBLIC_PATH
              value: "${MEDIA_CACHE_PUBLIC_PATH}"
            - name: MEDIA_CACHE_TTL_SECONDS
              value: "${MEDIA_CACHE_TTL_SECONDS}"
            - name: MEDIA_CACHE_MAX_BYTES
              value: "${MEDIA_CACHE_MAX_BYTES}"
            - name: MEDIA_CACHE_MAX_ENTRIES
              value: "${MEDIA_CACHE_MAX_ENTRIES}"
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /__opensoft-cache/status
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /__opensoft-cache/status
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 128Mi
          volumeMounts:
            - name: app
              mountPath: /app
              readOnly: true
      volumes:
        - name: app
          configMap:
            name: ${CACHE_NAME}
---
apiVersion: v1
kind: Service
metadata:
  name: ${CACHE_NAME}
  labels:
    app.kubernetes.io/name: ${CACHE_NAME}
    app.kubernetes.io/part-of: opensoft-nopcommerce-cache-pilot
spec:
  selector:
    app.kubernetes.io/name: ${CACHE_NAME}
  ports:
    - name: http
      port: 80
      targetPort: http
YAML

  if [ "$WAIT_FOR_ROLLOUT" = "true" ]; then
    kubectl -n "$NAMESPACE" rollout restart "deployment/${CACHE_NAME}" >/dev/null
    kubectl -n "$NAMESPACE" rollout status "deployment/${CACHE_NAME}" --timeout=5m
  fi
}

apply_ingress() {
  log "Patching ${INGRESS_NAME} routes: exact homepage and media cache to ${CACHE_NAME}, remaining paths to ${ORIGIN_SERVICE}"
  kubectl -n "$NAMESPACE" patch ingress "$INGRESS_NAME" --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths\",\"value\":[{\"path\":\"${MEDIA_CACHE_PUBLIC_PATH}\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"${CACHE_NAME}\",\"port\":{\"number\":80}}}},{\"path\":\"/\",\"pathType\":\"Exact\",\"backend\":{\"service\":{\"name\":\"${CACHE_NAME}\",\"port\":{\"number\":80}}}},{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"${ORIGIN_SERVICE}\",\"port\":{\"number\":${ORIGIN_PORT}}}}}]}]"
}

main() {
  require_tool kubectl

  if [ "$ACTION" = "delete" ]; then
    delete_cache
    return
  fi

  apply_configmap
  apply_workload
  apply_ingress
  log "Homepage memory cache applied for https://${HOST}/"
}

main "$@"
