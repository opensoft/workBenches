#!/usr/bin/env node
"use strict";

const fs = require("fs");
const { chromium } = require("playwright");

const env = process.env;
const hosts = (env.CACHE_TEST_HOSTS || "")
  .split(",")
  .map((host) => host.trim())
  .filter(Boolean);
const ingressIp = env.INGRESS_IP || "";
const iterations = Number.parseInt(env.BROWSER_ITERATIONS || "5", 10);
const waitMs = Number.parseInt(env.BROWSER_PREFETCH_WAIT_MS || "8000", 10);
const idleTimeoutMs = Number.parseInt(env.BROWSER_IDLE_TIMEOUT_MS || "4000", 10);
const intentWarmMs = Number.parseInt(env.BROWSER_INTENT_WARM_MS || "1500", 10);
const timeoutMs = Number.parseInt(env.BROWSER_TIMEOUT_MS || "60000", 10);
const ndjsonPath = env.BROWSER_NDJSON || "";
const csvPath = env.BROWSER_CSV || "";
const smoke = env.SMOKE === "true";

const blockedPatterns = [
  /\/admin(?:\/|$)/i,
  /\/login(?:\/|$)/i,
  /\/register(?:\/|$)/i,
  /\/logout(?:\/|$)/i,
  /\/cart(?:\/|$)/i,
  /\/wishlist(?:\/|$)/i,
  /\/checkout(?:\/|$)/i,
  /\/customer(?:\/|$)/i,
  /\/order(?:\/|$)/i,
  /\/passwordrecovery(?:\/|$)/i,
  /\/search(?:\/|$)/i,
  /\/(?:null|undefined)(?:[?#]|$)/i
];

function die(message) {
  console.error(message);
  process.exit(1);
}

function csvEscape(value) {
  const text = value == null ? "" : String(value);
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function normalizePath(pathname) {
  return (pathname || "/").replace(/^\/[a-z]{2}(?:-[a-z]{2})?(?=\/|$)/i, "") || "/";
}

function isBlockedHref(href) {
  try {
    const url = new URL(href);
    const normalized = normalizePath(url.pathname);
    const normalizedHref = `${url.origin}${normalized}${url.search}${url.hash}`;
    return blockedPatterns.some((pattern) => pattern.test(normalizedHref));
  } catch (_error) {
    return true;
  }
}

function seededHash(text) {
  let hash = 2166136261;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function orderFor(host, iteration) {
  const pair = ["enabled", "disabled"];
  if (seededHash(`${host}:${iteration}`) % 2 === 1) {
    pair.reverse();
  }
  return pair;
}

function timingFromNavigation(entry) {
  if (!entry) {
    return {
      ttfbMs: null,
      domContentLoadedMs: null,
      loadMs: null,
      totalMs: null
    };
  }

  const end = entry.loadEventEnd || entry.domContentLoadedEventEnd || entry.responseEnd || 0;
  return {
    ttfbMs: Math.max(0, entry.responseStart - entry.startTime),
    domContentLoadedMs: Math.max(0, entry.domContentLoadedEventEnd - entry.startTime),
    loadMs: Math.max(0, entry.loadEventEnd - entry.startTime),
    totalMs: Math.max(0, end - entry.startTime)
  };
}

function appendRecord(record) {
  if (ndjsonPath) {
    fs.appendFileSync(ndjsonPath, `${JSON.stringify(record)}\n`);
  } else {
    process.stdout.write(`${JSON.stringify(record)}\n`);
  }

  if (!csvPath) {
    return;
  }

  const columns = [
    "timestamp",
    "iteration",
    "host",
    "prefetch_state",
    "start_url",
    "target_url",
    "home_status",
    "target_status",
    "home_ttfb_ms",
    "home_dom_ms",
    "home_load_ms",
    "target_ttfb_ms",
    "target_dom_ms",
    "target_load_ms",
    "target_total_ms",
    "post_load_wait_ms",
    "idle_wait_type",
    "idle_wait_timed_out",
    "intent_warm_ms",
    "hint_count",
    "blocked_hint_count",
    "warm_fetch_request_count",
    "pre_intent_warm_fetch_count",
    "intent_warm_fetch_count",
    "warm_fetch_ok_count",
    "warm_fetch_error_count",
    "warm_fetch_pending_count",
    "warm_fetch_avg_ms",
    "target_warmed_before_click",
    "target_warm_elapsed_ms",
    "failed_request_count",
    "console_error_count",
    "page_error_count",
    "prefetch_request_count",
    "error"
  ];

  const row = [
    record.timestamp,
    record.iteration,
    record.host,
    record.prefetchState,
    record.startUrl,
    record.targetUrl,
    record.homeStatus,
    record.targetStatus,
    record.homeTiming && record.homeTiming.ttfbMs,
    record.homeTiming && record.homeTiming.domContentLoadedMs,
    record.homeTiming && record.homeTiming.loadMs,
    record.targetTiming && record.targetTiming.ttfbMs,
    record.targetTiming && record.targetTiming.domContentLoadedMs,
    record.targetTiming && record.targetTiming.loadMs,
    record.targetTiming && record.targetTiming.totalMs,
    record.postLoadWaitMs,
    record.idleWait && record.idleWait.type,
    record.idleWait && record.idleWait.timedOut,
    record.intentWarmMs,
    record.hintCount,
    record.blockedHintCount,
    record.warmFetchRequests.length,
    record.preIntentWarmFetchRequestCount,
    record.intentWarmFetchRequests.length,
    record.warmFetchSummary.okCount,
    record.warmFetchSummary.errorCount,
    record.warmFetchSummary.pendingCount,
    record.warmFetchSummary.avgElapsedMs,
    record.warmFetchSummary.targetWarmedBeforeClick,
    record.warmFetchSummary.targetWarmElapsedMs,
    record.failedRequests.length,
    record.consoleErrors.length,
    record.pageErrors.length,
    record.prefetchRequests.length,
    record.error || ""
  ];
  fs.appendFileSync(csvPath, `${row.map(csvEscape).join(",")}\n`);
}

async function installDisabledPrefetchHarness(page) {
  await page.addInitScript(() => {
    window.__opensoftBlockedHints = [];
    window.__opensoftBlockedScripts = [];

    try {
      Object.defineProperty(navigator, "connection", {
        configurable: true,
        value: {
          saveData: true,
          effectiveType: "2g"
        }
      });
    } catch (_error) {
      // Some browsers expose this as readonly. The append hook below is the
      // enforcement path when this hint cannot be set.
    }

    const blockedRels = new Set(["prefetch", "preconnect", "dns-prefetch"]);
    const originalAppendChild = Element.prototype.appendChild;
    Element.prototype.appendChild = function patchedAppendChild(node) {
      try {
        if (node && node.tagName === "LINK" && blockedRels.has(String(node.rel || "").toLowerCase())) {
          window.__opensoftBlockedHints.push({
            rel: node.rel,
            as: node.as || "",
            href: node.href || ""
          });
          return node;
        }
        if (node && node.tagName === "SCRIPT" && String(node.src || "").includes("opensoft-prefetch.js")) {
          window.__opensoftBlockedScripts.push(node.src);
          return node;
        }
      } catch (_error) {
        return originalAppendChild.call(this, node);
      }
      return originalAppendChild.call(this, node);
    };
  });
}

async function pageNavigationTiming(page) {
  return page.evaluate(() => {
    const entries = performance.getEntriesByType("navigation");
    return entries.length ? entries[entries.length - 1].toJSON() : null;
  });
}

async function collectHints(page) {
  return page.evaluate(() => Array.from(
    document.querySelectorAll('link[rel="prefetch"],link[rel="preconnect"],link[rel="dns-prefetch"]'),
    (link) => ({
      rel: link.rel || "",
      as: link.as || "",
      href: link.href || ""
    })
  ));
}

async function collectWarmFetchRecords(page) {
  return page.evaluate(() => (window.__opensoftWarmFetches || []).map((record) => ({
    href: record.href || "",
    reason: record.reason || "",
    priority: record.priority || "",
    startedAt: record.startedAt || 0,
    ok: Boolean(record.ok),
    status: Number(record.status || 0),
    elapsedMs: Number(record.elapsedMs || 0),
    abortReason: record.abortReason || "",
    error: record.error || ""
  })));
}

function summarizeWarmFetchRecords(records, targetUrl) {
  const completed = records.filter((record) => record.elapsedMs > 0);
  const okRecords = completed.filter((record) => record.ok);
  const errorRecords = completed.filter((record) => record.error || !record.ok);
  const pendingRecords = records.filter((record) => record.elapsedMs <= 0 && !record.error);
  const targetRecord = okRecords.find((record) => record.href === targetUrl);
  const elapsedValues = okRecords.map((record) => record.elapsedMs);
  const avgElapsedMs = elapsedValues.length
    ? elapsedValues.reduce((total, value) => total + value, 0) / elapsedValues.length
    : null;

  return {
    okCount: okRecords.length,
    errorCount: errorRecords.length,
    pendingCount: pendingRecords.length,
    avgElapsedMs,
    targetWarmedBeforeClick: Boolean(targetRecord),
    targetWarmElapsedMs: targetRecord ? targetRecord.elapsedMs : null
  };
}

async function waitForBrowserIdle(page) {
  return page.evaluate((timeout) => new Promise((resolve) => {
    const startedAt = performance.now();
    const done = (type, timedOut) => {
      resolve({
        type,
        timedOut,
        elapsedMs: performance.now() - startedAt
      });
    };

    if ("requestIdleCallback" in window) {
      const fallback = window.setTimeout(() => done("requestIdleCallback", true), timeout + 250);
      window.requestIdleCallback(() => {
        window.clearTimeout(fallback);
        done("requestIdleCallback", false);
      }, { timeout });
      return;
    }

    window.setTimeout(() => done("setTimeout", false), Math.min(timeout, 1500));
  }), idleTimeoutMs);
}

async function firstEligibleLink(page) {
  return page.evaluate(() => {
    function absoluteUrl(value) {
      try {
        if (!value || value === "null" || value === "undefined") {
          return null;
        }
        return new URL(value, window.location.href);
      } catch (_error) {
        return null;
      }
    }

    function normalizedPath(pathname) {
      return (pathname || "/").replace(/^\/[a-z]{2}(?:-[a-z]{2})?(?=\/|$)/i, "") || "/";
    }

    const skippedPaths = [
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

    function eligible(anchor) {
      const url = absoluteUrl(anchor.getAttribute("href"));
      if (!url || url.origin !== window.location.origin || url.search) {
        return false;
      }
      const rect = anchor.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight * 1.15) {
        return false;
      }
      const path = normalizedPath(url.pathname);
      if (path === normalizedPath(window.location.pathname)) {
        return false;
      }
      if (/\.(?:avif|bmp|css|csv|docx?|gif|ico|jpe?g|js|json|pdf|png|svg|webp|xlsx?|xml|zip)$/i.test(path)) {
        return false;
      }
      return !skippedPaths.some((pattern) => pattern.test(path));
    }

    const seen = new Set();
    for (const anchor of Array.from(document.querySelectorAll("a[href]"))) {
      const url = absoluteUrl(anchor.getAttribute("href"));
      if (!url || seen.has(url.href) || !eligible(anchor)) {
        continue;
      }
      seen.add(url.href);
      document.querySelectorAll("[data-opensoft-cache-test-target]").forEach((element) => {
        element.removeAttribute("data-opensoft-cache-test-target");
      });
      anchor.setAttribute("data-opensoft-cache-test-target", "1");
      return {
        href: url.href,
        text: (anchor.textContent || "").trim().replace(/\s+/g, " ").slice(0, 120)
      };
    }
    return null;
  });
}

async function warmIntentForTarget(page) {
  const target = page.locator("[data-opensoft-cache-test-target='1']").first();
  await target.scrollIntoViewIfNeeded({ timeout: timeoutMs });
  await target.hover({ timeout: timeoutMs });
  await target.focus({ timeout: timeoutMs });
  await page.evaluate(() => {
    const element = document.querySelector("[data-opensoft-cache-test-target='1']");
    if (!element) {
      return;
    }

    const eventInit = {
      bubbles: true,
      cancelable: true,
      composed: true,
      view: window
    };

    element.dispatchEvent(new PointerEvent("pointerover", { ...eventInit, pointerType: "mouse" }));
    element.dispatchEvent(new PointerEvent("pointerenter", { ...eventInit, pointerType: "mouse" }));
    element.dispatchEvent(new MouseEvent("mouseover", eventInit));
    element.dispatchEvent(new MouseEvent("mouseenter", eventInit));
    element.dispatchEvent(new FocusEvent("focus", eventInit));

    try {
      element.dispatchEvent(new TouchEvent("touchstart", {
        bubbles: true,
        cancelable: true,
        touches: [],
        targetTouches: [],
        changedTouches: []
      }));
    } catch (_error) {
      element.dispatchEvent(new Event("touchstart", { bubbles: true, cancelable: true }));
    }
  });
  await page.waitForTimeout(intentWarmMs);
}

async function clickTarget(page) {
  const target = page.locator("[data-opensoft-cache-test-target='1']").first();
  return Promise.all([
    page.waitForNavigation({ waitUntil: "load", timeout: timeoutMs }).catch((error) => ({ error })),
    target.click({ timeout: timeoutMs })
  ]).then(([navigation]) => navigation);
}

async function runJourney(browser, host, iteration, prefetchState) {
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();
  const failedRequests = [];
  const consoleErrors = [];
  const pageErrors = [];
  const prefetchRequests = [];
  const warmFetchRequests = [];
  const startOrigin = `https://${host}`;

  page.on("request", (request) => {
    const url = request.url();
    if (url.includes("opensoft-prefetch") || request.resourceType() === "prefetch") {
      prefetchRequests.push(url);
    }
    if (request.resourceType() === "fetch") {
      try {
        const parsed = new URL(url);
        if (parsed.origin === startOrigin && !isBlockedHref(url)) {
          warmFetchRequests.push(url);
        }
      } catch (_error) {
        // Ignore malformed or browser-internal URLs.
      }
    }
  });
  page.on("requestfailed", (request) => {
    failedRequests.push({
      url: request.url(),
      method: request.method(),
      resourceType: request.resourceType(),
      failure: request.failure() && request.failure().errorText
    });
  });
  page.on("console", (message) => {
    if (["error", "warning"].includes(message.type())) {
      consoleErrors.push(`${message.type()}: ${message.text()}`);
    }
  });
  page.on("pageerror", (error) => {
    pageErrors.push(error.message);
  });

  if (prefetchState === "disabled") {
    await installDisabledPrefetchHarness(page);
  }

  const startUrl = `https://${host}/`;
  const startedAt = new Date().toISOString();
  let homeStatus = null;
  let targetStatus = null;
  let targetUrl = "";
  let targetText = "";
  let error = "";
  let finalHomeUrl = "";
  let homeTiming = null;
  let targetTiming = null;
  let finalTargetUrl = "";
  let idleWait = null;
  let hints = [];
  let hintsAfterIntent = [];
  let blockedHints = [];
  let blockedHintsAfterIntent = [];
  let preIntentPrefetchRequestCount = 0;
  let intentPrefetchRequests = [];
  let preIntentWarmFetchRequestCount = 0;
  let intentWarmFetchRequests = [];
  let preIntentWarmFetchRecords = [];
  let warmFetchRecordsBeforeClick = [];
  let warmFetchSummary = summarizeWarmFetchRecords([], "");

  try {
    const homeResponse = await page.goto(startUrl, {
      waitUntil: "load",
      timeout: timeoutMs
    });
    homeStatus = homeResponse ? homeResponse.status() : null;
    homeTiming = timingFromNavigation(await pageNavigationTiming(page));
    finalHomeUrl = page.url();

    await page.waitForTimeout(waitMs);
    idleWait = await waitForBrowserIdle(page);
    hints = await collectHints(page);
    blockedHints = hints.filter((hint) => isBlockedHref(hint.href));

    const target = await firstEligibleLink(page);
    if (!target) {
      throw new Error("No eligible public near-fold link found");
    }
    targetUrl = target.href;
    targetText = target.text;

    preIntentPrefetchRequestCount = prefetchRequests.length;
    preIntentWarmFetchRequestCount = warmFetchRequests.length;
    preIntentWarmFetchRecords = await collectWarmFetchRecords(page);
    await warmIntentForTarget(page);
    hintsAfterIntent = await collectHints(page);
    blockedHintsAfterIntent = hintsAfterIntent.filter((hint) => isBlockedHref(hint.href));
    intentPrefetchRequests = prefetchRequests.slice(preIntentPrefetchRequestCount);
    intentWarmFetchRequests = warmFetchRequests.slice(preIntentWarmFetchRequestCount);
    warmFetchRecordsBeforeClick = await collectWarmFetchRecords(page);
    warmFetchSummary = summarizeWarmFetchRecords(warmFetchRecordsBeforeClick, targetUrl);

    const targetResponse = await clickTarget(page);
    if (targetResponse && targetResponse.error) {
      throw targetResponse.error;
    }
    targetStatus = targetResponse ? targetResponse.status() : null;
    targetTiming = timingFromNavigation(await pageNavigationTiming(page));
    finalTargetUrl = page.url();

    if (finalTargetUrl === startUrl) {
      throw new Error("Click did not navigate away from the homepage");
    }
  } catch (caught) {
    error = caught && caught.message ? caught.message : String(caught);
  }

  const record = {
    timestamp: new Date().toISOString(),
    startedAt,
    iteration,
    host,
    prefetchState,
    startUrl,
    finalHomeUrl,
    targetUrl,
    finalTargetUrl,
    targetText,
    homeStatus,
    targetStatus,
    homeTiming,
    targetTiming,
    postLoadWaitMs: waitMs,
    idleWait,
    intentWarmMs,
    hintCount: hints.length,
    hintCountAfterIntent: hintsAfterIntent.length,
    blockedHintCount: blockedHints.length + blockedHintsAfterIntent.length,
    firstHints: hints.slice(0, 10),
    firstHintsAfterIntent: hintsAfterIntent.slice(0, 10),
    blockedHints,
    blockedHintsAfterIntent,
    failedRequests,
    consoleErrors,
    pageErrors,
    prefetchRequests,
    preIntentPrefetchRequestCount,
    intentPrefetchRequests,
    warmFetchRequests,
    preIntentWarmFetchRequestCount,
    intentWarmFetchRequests,
    preIntentWarmFetchRecords,
    warmFetchRecordsBeforeClick,
    warmFetchSummary,
    error
  };

  appendRecord(record);
  await context.close();
}

async function main() {
  if (!hosts.length) {
    die("CACHE_TEST_HOSTS is required");
  }
  if (!ingressIp) {
    die("INGRESS_IP is required");
  }
  if (csvPath) {
    fs.writeFileSync(csvPath, [
      "timestamp",
      "iteration",
      "host",
      "prefetch_state",
      "start_url",
      "target_url",
      "home_status",
      "target_status",
      "home_ttfb_ms",
      "home_dom_ms",
      "home_load_ms",
      "target_ttfb_ms",
      "target_dom_ms",
      "target_load_ms",
      "target_total_ms",
      "post_load_wait_ms",
      "idle_wait_type",
      "idle_wait_timed_out",
      "intent_warm_ms",
      "hint_count",
      "blocked_hint_count",
      "warm_fetch_request_count",
      "pre_intent_warm_fetch_count",
      "intent_warm_fetch_count",
      "warm_fetch_ok_count",
      "warm_fetch_error_count",
      "warm_fetch_pending_count",
      "warm_fetch_avg_ms",
      "target_warmed_before_click",
      "target_warm_elapsed_ms",
      "failed_request_count",
      "console_error_count",
      "page_error_count",
      "prefetch_request_count",
      "error"
    ].join(",") + "\n");
  }
  if (ndjsonPath) {
    fs.writeFileSync(ndjsonPath, "");
  }

  const resolverRules = hosts.map((host) => `MAP ${host} ${ingressIp}`).join(",");
  const browser = await chromium.launch({
    headless: true,
    args: ["--no-proxy-server", `--host-resolver-rules=${resolverRules}`]
  });

  try {
    for (let iteration = 1; iteration <= iterations; iteration += 1) {
      for (const host of hosts) {
        const states = orderFor(host, iteration);
        for (const state of states) {
          await runJourney(browser, host, iteration, state);
        }
      }
      if (smoke) {
        break;
      }
    }
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
