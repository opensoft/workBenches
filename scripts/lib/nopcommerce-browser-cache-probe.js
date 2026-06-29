#!/usr/bin/env node
"use strict";

const { chromium } = require("playwright");

const host = process.env.CACHE_PROBE_HOST || "digiwrap.davinci-designer.com";
const startUrl = process.env.CACHE_PROBE_URL || `https://${host}/`;
const explicitTargetUrl = process.env.CACHE_PROBE_TARGET || "";
const outputJson = process.env.CACHE_PROBE_OUTPUT || "";
const executablePath = process.env.CACHE_PROBE_EXECUTABLE || "";
const mode = process.env.CACHE_PROBE_MODE || "manual";
const autoWaitMs = Number(process.env.CACHE_PROBE_AUTO_WAIT_MS || "6500");

const blockedPathParts = [
  "admin",
  "login",
  "register",
  "logout",
  "cart",
  "wishlist",
  "checkout",
  "customer",
  "order",
  "passwordrecovery",
  "search",
  "null",
  "undefined",
];

function isSafeUrl(url) {
  const parsed = new URL(url);
  if (parsed.origin !== new URL(startUrl).origin) return false;
  const segments = parsed.pathname
    .toLowerCase()
    .split("/")
    .filter(Boolean);
  return !blockedPathParts.some((part) => segments.includes(part));
}

async function pickTarget(page) {
  if (explicitTargetUrl) return explicitTargetUrl;

  return await page.evaluate((blocked) => {
    const origin = window.location.origin;
    const viewportBottom = (window.innerHeight || 900) * 1.5;
    const candidates = Array.from(document.querySelectorAll("a[href]"))
      .map((anchor) => {
        const href = anchor.href;
        let parsed;
        try {
          parsed = new URL(href);
        } catch {
          return null;
        }
        if (parsed.origin !== origin) return null;
        const segments = parsed.pathname
          .toLowerCase()
          .split("/")
          .filter(Boolean);
        if (blocked.some((part) => segments.includes(part))) return null;
        const rect = anchor.getBoundingClientRect();
        if (rect.width < 20 || rect.height < 10 || rect.bottom < 0 || rect.top > viewportBottom) return null;
        if (parsed.pathname === "/" || parsed.pathname === window.location.pathname) return null;
        return { href, top: rect.top, text: (anchor.textContent || "").trim().slice(0, 80) };
      })
      .filter(Boolean)
      .sort((a, b) => a.top - b.top);
    return candidates[0]?.href || "";
  }, blockedPathParts);
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    ...(executablePath ? { executablePath } : {}),
  });
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    userAgent:
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 OpenSoftCacheProbe/1.0",
  });
  if (mode === "disabled") {
    await context.addInitScript(() => {
      window.__opensoftWarmFetchInstalled = true;
    });
  }

  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.clearBrowserCache");
  await cdp.send("Network.clearBrowserCookies");

  const requestUrls = new Map();
  let cacheEvents = [];
  let responses = [];

  cdp.on("Network.requestWillBeSent", (event) => {
    requestUrls.set(event.requestId, event.request.url);
  });

  cdp.on("Network.requestServedFromCache", (event) => {
    cacheEvents.push({
      requestId: event.requestId,
      url: requestUrls.get(event.requestId) || "",
    });
  });

  cdp.on("Network.responseReceived", (event) => {
    responses.push({
      requestId: event.requestId,
      type: event.type,
      url: event.response.url,
      status: event.response.status,
      mimeType: event.response.mimeType,
      fromDiskCache: Boolean(event.response.fromDiskCache),
      fromPrefetchCache: Boolean(event.response.fromPrefetchCache),
      fromServiceWorker: Boolean(event.response.fromServiceWorker),
      encodedDataLength: event.response.encodedDataLength,
      cacheControl: event.response.headers["cache-control"] || event.response.headers["Cache-Control"] || "",
      pragma: event.response.headers.pragma || event.response.headers.Pragma || "",
      xOpenSoftCacheTest:
        event.response.headers["x-opensoft-cache-test"] || event.response.headers["X-OpenSoft-Cache-Test"] || "",
    });
  });

  const homeResponse = await page.goto(startUrl, { waitUntil: "load", timeout: 45000 });
  let targetUrl = await pickTarget(page);
  if (!targetUrl) throw new Error(`No safe target link found on ${startUrl}`);
  if (!isSafeUrl(targetUrl)) throw new Error(`Unsafe target URL selected: ${targetUrl}`);

  let warmResult;
  if (mode === "auto" || mode === "disabled") {
    await page.waitForTimeout(autoWaitMs);
    const warmFetches = await page.evaluate(() => (window.__opensoftWarmFetches || []).map((entry) => ({ ...entry })));
    const warmedTarget = warmFetches.find((entry) => entry.ok && entry.href)?.href || "";
    if (warmedTarget) targetUrl = warmedTarget;
    if (!isSafeUrl(targetUrl)) throw new Error(`Unsafe warmed URL selected: ${targetUrl}`);
    warmResult = {
      mode,
      autoWaitMs,
      selectedFromWarmFetches: Boolean(warmedTarget),
      warmFetches,
    };
  } else {
    warmResult = await page.evaluate(async (url) => {
      const started = performance.now();
      performance.clearResourceTimings();
      const response = await fetch(url, {
        cache: "force-cache",
        credentials: "include",
        priority: "low",
      });
      const body = await response.text();
      const elapsedMs = performance.now() - started;
      const entries = performance.getEntriesByName(url).map((entry) => ({
        name: entry.name,
        duration: entry.duration,
        transferSize: entry.transferSize,
        encodedBodySize: entry.encodedBodySize,
        decodedBodySize: entry.decodedBodySize,
      }));

      return {
        mode,
        ok: response.ok,
        status: response.status,
        cacheControl: response.headers.get("cache-control") || "",
        pragma: response.headers.get("pragma") || "",
        xOpenSoftCacheTest: response.headers.get("x-opensoft-cache-test") || "",
        bodyBytes: body.length,
        elapsedMs,
        entries,
      };
    }, targetUrl);
  }

  await page.waitForTimeout(500);
  cacheEvents = [];
  responses = [];

  const startedNavigation = Date.now();
  const targetResponse = await page.goto(targetUrl, { waitUntil: "load", timeout: 45000 });
  const navigationElapsedMs = Date.now() - startedNavigation;
  const navigationTiming = await page.evaluate(() => {
    const nav = performance.getEntriesByType("navigation")[0];
    return nav
      ? {
          responseStart: nav.responseStart,
          domContentLoadedEventEnd: nav.domContentLoadedEventEnd,
          loadEventEnd: nav.loadEventEnd,
          duration: nav.duration,
          transferSize: nav.transferSize,
          encodedBodySize: nav.encodedBodySize,
          decodedBodySize: nav.decodedBodySize,
        }
      : null;
  });

  const targetResponses = responses.filter((response) => response.url.split("#")[0] === targetUrl.split("#")[0]);
  const targetCacheEvents = cacheEvents.filter((event) => event.url.split("#")[0] === targetUrl.split("#")[0]);

  const result = {
    host,
    startUrl,
    targetUrl,
    homeStatus: homeResponse?.status() || null,
    warmResult,
    navigation: {
      status: targetResponse?.status() || null,
      elapsedMs: navigationElapsedMs,
      timing: navigationTiming,
      targetResponses,
      targetCacheEvents,
      servedFromCache:
        targetCacheEvents.length > 0 ||
        targetResponses.some((response) => response.fromDiskCache || response.fromPrefetchCache),
    },
  };

  await browser.close();

  const text = `${JSON.stringify(result, null, 2)}\n`;
  if (outputJson) {
    require("fs").writeFileSync(outputJson, text);
  } else {
    process.stdout.write(text);
  }
}

main().catch((error) => {
  const payload = JSON.stringify(
    {
      error: error.message,
      stack: error.stack,
    },
    null,
    2,
  );
  if (outputJson) require("fs").writeFileSync(outputJson, `${payload}\n`);
  else process.stderr.write(`${payload}\n`);
  process.exitCode = 1;
});
