#!/usr/bin/env node
"use strict";

const fs = require("fs");
const { chromium } = require("playwright");

const outputJson = process.env.HOMEPAGE_SHAPE_OUTPUT || "";
const executablePath = process.env.HOMEPAGE_SHAPE_EXECUTABLE || "";
const iterations = Number(process.env.HOMEPAGE_SHAPE_ITERATIONS || "5");
const timeoutMs = Number(process.env.HOMEPAGE_SHAPE_TIMEOUT_MS || "60000");
const waitAfterLoadMs = Number(process.env.HOMEPAGE_SHAPE_WAIT_AFTER_LOAD_MS || "1000");

const targets = (process.env.HOMEPAGE_SHAPE_TARGETS ||
  "blob-mem=https://digiwrap.davinci-designer.com/,nfs=https://digiwrap.qa.davincisite.com/")
  .split(",")
  .map((entry) => {
    const index = entry.indexOf("=");
    if (index === -1) throw new Error(`Invalid target: ${entry}`);
    return {
      label: entry.slice(0, index),
      url: entry.slice(index + 1),
    };
  });

function percentile(values, p) {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  const k = (sorted.length - 1) * (p / 100);
  const f = Math.floor(k);
  const c = Math.ceil(k);
  if (f === c) return sorted[f];
  return sorted[f] * (c - k) + sorted[c] * (k - f);
}

function summarize(rows) {
  const summary = {};
  for (const target of targets) {
    const scoped = rows.filter((row) => row.label === target.label && !row.error);
    const nums = (key) => scoped.map((row) => row[key]).filter((value) => Number.isFinite(value));
    summary[target.label] = {
      url: target.url,
      runs: scoped.length,
      errors: rows.filter((row) => row.label === target.label && row.error).length,
      statusCounts: scoped.reduce((acc, row) => {
        acc[row.status] = (acc[row.status] || 0) + 1;
        return acc;
      }, {}),
      documentCacheHeaders: Array.from(new Set(scoped.map((row) => row.documentCacheHeader || ""))).filter(Boolean),
      documentServerCacheHeaders: Array.from(new Set(scoped.map((row) => row.documentServerCacheHeader || ""))).filter(Boolean),
      navigationDurationP50: percentile(nums("navigationDurationMs"), 50),
      navigationDurationP95: percentile(nums("navigationDurationMs"), 95),
      loadEventP50: percentile(nums("loadEventMs"), 50),
      domContentLoadedP50: percentile(nums("domContentLoadedMs"), 50),
      responseStartP50: percentile(nums("responseStartMs"), 50),
      totalTransferP50: percentile(nums("totalTransferSize"), 50),
      imageDurationP50: percentile(nums("imageDurationP50"), 50),
      imageDurationP95: percentile(nums("imageDurationP95"), 95),
      imageTransferP50: percentile(nums("imageTransferSize"), 50),
      blobImageCountP50: percentile(nums("blobImageCount"), 50),
      sameOriginImageCountP50: percentile(nums("sameOriginImageCount"), 50),
      failedRequestP50: percentile(nums("failedRequestCount"), 50),
    };
  }
  return summary;
}

async function runOne(browser, target, iteration) {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    userAgent:
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 OpenSoftHomepageShape/1.0",
  });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.clearBrowserCache");
  await cdp.send("Network.clearBrowserCookies");

  const failedRequests = [];
  page.on("requestfailed", (request) => {
    failedRequests.push({
      url: request.url(),
      resourceType: request.resourceType(),
      failure: request.failure()?.errorText || "",
    });
  });

  const started = Date.now();
  let response;
  try {
    response = await page.goto(target.url, { waitUntil: "load", timeout: timeoutMs });
    await page.waitForTimeout(waitAfterLoadMs);
  } catch (error) {
    await context.close();
    return {
      label: target.label,
      url: target.url,
      iteration,
      error: error.message,
      elapsedMs: Date.now() - started,
    };
  }

  const status = response ? response.status() : null;
  const headers = response ? response.headers() : {};
  const metrics = await page.evaluate(() => {
    const nav = performance.getEntriesByType("navigation")[0];
    const resources = performance.getEntriesByType("resource").map((entry) => ({
      name: entry.name,
      initiatorType: entry.initiatorType,
      duration: entry.duration,
      transferSize: entry.transferSize,
      encodedBodySize: entry.encodedBodySize,
      decodedBodySize: entry.decodedBodySize,
      responseStart: entry.responseStart,
      responseEnd: entry.responseEnd,
    }));
    return {
      navigation: nav
        ? {
            duration: nav.duration,
            responseStart: nav.responseStart,
            domContentLoadedEventEnd: nav.domContentLoadedEventEnd,
            loadEventEnd: nav.loadEventEnd,
            transferSize: nav.transferSize,
            encodedBodySize: nav.encodedBodySize,
            decodedBodySize: nav.decodedBodySize,
          }
        : null,
      resources,
      htmlBytes: document.documentElement.outerHTML.length,
    };
  });

  await context.close();

  const resources = metrics.resources || [];
  const imageResources = resources.filter((entry) => entry.initiatorType === "img" || /\.(?:png|jpe?g|gif|webp|svg)(?:[?#].*)?$/i.test(entry.name));
  const imageDurations = imageResources.map((entry) => entry.duration).filter(Number.isFinite);
  const imageTransfers = imageResources.map((entry) => entry.transferSize || 0);
  const blobImages = imageResources.filter((entry) => /\.blob\.core\.windows\.net\//i.test(entry.name));
  const origin = new URL(target.url).origin;
  const sameOriginImages = imageResources.filter((entry) => entry.name.startsWith(origin));
  const nav = metrics.navigation || {};

  return {
    label: target.label,
    url: target.url,
    iteration,
    status,
    elapsedMs: Date.now() - started,
    documentCacheHeader: headers["cache-control"] || "",
    documentServerCacheHeader: headers["x-opensoft-home-cache"] || "",
    navigationDurationMs: nav.duration,
    responseStartMs: nav.responseStart,
    domContentLoadedMs: nav.domContentLoadedEventEnd,
    loadEventMs: nav.loadEventEnd,
    documentTransferSize: nav.transferSize,
    documentEncodedBodySize: nav.encodedBodySize,
    htmlBytes: metrics.htmlBytes,
    resourceCount: resources.length,
    imageCount: imageResources.length,
    blobImageCount: blobImages.length,
    sameOriginImageCount: sameOriginImages.length,
    imageDurationP50: percentile(imageDurations, 50),
    imageDurationP95: percentile(imageDurations, 95),
    imageTransferSize: imageTransfers.reduce((sum, value) => sum + value, 0),
    totalTransferSize: (nav.transferSize || 0) + resources.reduce((sum, entry) => sum + (entry.transferSize || 0), 0),
    failedRequestCount: failedRequests.length,
    failedRequests: failedRequests.slice(0, 20),
  };
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    ...(executablePath ? { executablePath } : {}),
  });

  const rows = [];
  for (let iteration = 1; iteration <= iterations; iteration += 1) {
    const ordered = iteration % 2 === 0 ? targets.slice().reverse() : targets;
    for (const target of ordered) {
      rows.push(await runOne(browser, target, iteration));
    }
  }

  await browser.close();

  const payload = {
    startedAt: new Date().toISOString(),
    iterations,
    timeoutMs,
    waitAfterLoadMs,
    targets,
    summary: summarize(rows),
    rows,
  };

  const text = `${JSON.stringify(payload, null, 2)}\n`;
  if (outputJson) fs.writeFileSync(outputJson, text);
  else process.stdout.write(text);
}

main().catch((error) => {
  const payload = JSON.stringify({ error: error.message, stack: error.stack }, null, 2);
  if (outputJson) fs.writeFileSync(outputJson, `${payload}\n`);
  else process.stderr.write(`${payload}\n`);
  process.exitCode = 1;
});
