#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const targets = (process.env.NOP_IMAGE_COMPARE_TARGETS ||
  "blob-mem=https://digiwrap.davinci-designer.com/,nfs=https://digiwrap.qa.davincisite.com/")
  .split(",")
  .map((entry) => {
    const index = entry.indexOf("=");
    if (index === -1) throw new Error(`Invalid target entry: ${entry}`);
    return { label: entry.slice(0, index), url: entry.slice(index + 1) };
  });

const outputDir =
  process.env.NOP_IMAGE_COMPARE_OUTPUT_DIR ||
  path.join(
    process.cwd(),
    "reports",
    "cache-pilot",
    `browser-image-compare-${new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z")}`,
  );
const executablePath = process.env.NOP_IMAGE_COMPARE_EXECUTABLE || "";
const timeoutMs = Number(process.env.NOP_IMAGE_COMPARE_TIMEOUT_MS || "60000");
const waitAfterLoadMs = Number(process.env.NOP_IMAGE_COMPARE_WAIT_AFTER_LOAD_MS || "2000");
const imageUrlPattern = /\.(?:png|jpe?g|gif|webp|svg|avif|bmp|ico)(?:[?#].*)?$/i;

function canonicalKey(url) {
  const parsed = new URL(url);
  const parts = decodeURIComponent(parsed.pathname).split("/").filter(Boolean);
  return (parts[parts.length - 1] || parsed.pathname).toLowerCase();
}

function percentile(values, p) {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  const k = (sorted.length - 1) * (p / 100);
  const f = Math.floor(k);
  const c = Math.ceil(k);
  if (f === c) return sorted[f];
  return sorted[f] * (c - k) + sorted[c] * (k - f);
}

function parsePng(buffer) {
  if (buffer.length >= 24 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
  }
  return null;
}

function parseGif(buffer) {
  if (buffer.length >= 10 && (buffer.subarray(0, 6).toString() === "GIF87a" || buffer.subarray(0, 6).toString() === "GIF89a")) {
    return { width: buffer.readUInt16LE(6), height: buffer.readUInt16LE(8) };
  }
  return null;
}

function parseJpeg(buffer) {
  if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) return null;
  let offset = 2;
  while (offset < buffer.length - 9) {
    if (buffer[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    while (offset < buffer.length && buffer[offset] === 0xff) offset += 1;
    if (offset >= buffer.length) break;
    const marker = buffer[offset];
    offset += 1;
    if (marker === 0xd8 || marker === 0xd9 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > buffer.length) break;
    const segmentLength = buffer.readUInt16BE(offset);
    if (segmentLength < 2) break;
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      if (offset + 7 <= buffer.length) {
        return { width: buffer.readUInt16BE(offset + 5), height: buffer.readUInt16BE(offset + 3) };
      }
      break;
    }
    offset += segmentLength;
  }
  return null;
}

function parseWebp(buffer) {
  if (buffer.length < 30 || buffer.subarray(0, 4).toString() !== "RIFF" || buffer.subarray(8, 12).toString() !== "WEBP") {
    return null;
  }
  const chunk = buffer.subarray(12, 16).toString();
  if (chunk === "VP8X" && buffer.length >= 30) {
    return {
      width: 1 + buffer.readUIntLE(24, 3),
      height: 1 + buffer.readUIntLE(27, 3),
    };
  }
  if (chunk === "VP8L" && buffer.length >= 25) {
    const b0 = buffer[21];
    const b1 = buffer[22];
    const b2 = buffer[23];
    const b3 = buffer[24];
    return {
      width: 1 + (((b1 & 0x3f) << 8) | b0),
      height: 1 + (((b3 & 0x0f) << 10) | (b2 << 2) | ((b1 & 0xc0) >> 6)),
    };
  }
  if (chunk === "VP8 ") {
    const startCode = buffer.indexOf(Buffer.from([0x9d, 0x01, 0x2a]), 20);
    if (startCode !== -1 && startCode + 7 <= buffer.length) {
      return {
        width: buffer.readUInt16LE(startCode + 3) & 0x3fff,
        height: buffer.readUInt16LE(startCode + 5) & 0x3fff,
      };
    }
  }
  return null;
}

function parseSvg(buffer) {
  const text = buffer.subarray(0, 4096).toString("utf8");
  if (!/<svg/i.test(text)) return null;
  const width = text.match(/\bwidth=["']?([0-9.]+)/i);
  const height = text.match(/\bheight=["']?([0-9.]+)/i);
  if (width && height) return { width: Number(width[1]), height: Number(height[1]) };
  const viewBox = text.match(/\bviewBox=["']\s*[-0-9.]+\s+[-0-9.]+\s+([0-9.]+)\s+([0-9.]+)/i);
  if (viewBox) return { width: Number(viewBox[1]), height: Number(viewBox[2]) };
  return null;
}

function parseDimensions(buffer) {
  return parsePng(buffer) || parseJpeg(buffer) || parseGif(buffer) || parseWebp(buffer) || parseSvg(buffer) || { width: null, height: null };
}

function headersToObject(headers) {
  const result = {};
  for (const [key, value] of Object.entries(headers || {})) result[key.toLowerCase()] = value;
  return result;
}

function resourceTypeFor(resource) {
  if (resource.resourceType === "image" || imageUrlPattern.test(resource.url)) return "image";
  return resource.resourceType || "other";
}

function summarizeResources(resources) {
  const byType = {};
  for (const resource of resources) {
    const type = resourceTypeFor(resource);
    byType[type] ||= { count: 0, bytes: 0, durationP50: null, durations: [] };
    byType[type].count += 1;
    byType[type].bytes += resource.bytes || 0;
    if (Number.isFinite(resource.durationMs)) byType[type].durations.push(resource.durationMs);
  }
  for (const value of Object.values(byType)) {
    value.durationP50 = percentile(value.durations, 50);
    delete value.durations;
  }
  return byType;
}

async function fetchBody(url, headers) {
  const response = await fetch(url, {
    headers: {
      "user-agent": "OpenSoftImageCompare/1.0",
      accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
    },
  });
  const arrayBuffer = await response.arrayBuffer();
  return {
    status: response.status,
    headers: Object.fromEntries(Array.from(response.headers.entries()).map(([k, v]) => [k.toLowerCase(), v])),
    body: Buffer.from(arrayBuffer),
    browserHeaders: headersToObject(headers),
  };
}

async function runTarget(browser, target) {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    userAgent:
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 OpenSoftImageCompare/1.0",
  });
  const page = await context.newPage();
  const resources = new Map();
  const failedRequests = [];

  page.on("request", (request) => {
    const url = request.url();
    resources.set(url, {
      url,
      resourceType: request.resourceType(),
      method: request.method(),
      startedAt: Date.now(),
    });
  });
  page.on("response", async (response) => {
    const url = response.url();
    const existing = resources.get(url) || { url, startedAt: Date.now() };
    existing.status = response.status();
    existing.headers = response.headers();
    existing.finishedAt = Date.now();
    existing.durationMs = existing.startedAt ? existing.finishedAt - existing.startedAt : null;
    resources.set(url, existing);
  });
  page.on("requestfailed", (request) => {
    failedRequests.push({
      url: request.url(),
      resourceType: request.resourceType(),
      failure: request.failure()?.errorText || "",
    });
  });

  const started = Date.now();
  const documentResponse = await page.goto(target.url, { waitUntil: "load", timeout: timeoutMs });
  await page.waitForTimeout(waitAfterLoadMs);
  const navigation = await page.evaluate(() => {
    const nav = performance.getEntriesByType("navigation")[0];
    return nav
      ? {
          duration: nav.duration,
          responseStart: nav.responseStart,
          domContentLoadedEventEnd: nav.domContentLoadedEventEnd,
          loadEventEnd: nav.loadEventEnd,
          transferSize: nav.transferSize,
          encodedBodySize: nav.encodedBodySize,
          decodedBodySize: nav.decodedBodySize,
        }
      : null;
  });
  const domImages = await page.evaluate(() => {
    const seen = new Map();
    for (const img of Array.from(document.images)) {
      const url = img.currentSrc || img.src;
      if (!url) continue;
      seen.set(url, {
        url,
        naturalWidth: img.naturalWidth || null,
        naturalHeight: img.naturalHeight || null,
        renderedWidth: img.clientWidth || null,
        renderedHeight: img.clientHeight || null,
        loading: img.loading || "",
        alt: img.alt || "",
      });
    }
    for (const element of Array.from(document.querySelectorAll("*"))) {
      const background = getComputedStyle(element).backgroundImage;
      if (!background || background === "none") continue;
      const matches = Array.from(background.matchAll(/url\\(["']?(.*?)["']?\\)/g));
      for (const match of matches) {
        const url = new URL(match[1], document.baseURI).href;
        if (!seen.has(url)) {
          seen.set(url, {
            url,
            naturalWidth: null,
            naturalHeight: null,
            renderedWidth: element.clientWidth || null,
            renderedHeight: element.clientHeight || null,
            loading: "css-background",
            alt: "",
          });
        }
      }
    }
    return Array.from(seen.values());
  });
  await context.close();

  const resourceRows = Array.from(resources.values()).map((resource) => ({
    url: resource.url,
    resourceType: resource.resourceType,
    type: resourceTypeFor(resource),
    method: resource.method,
    status: resource.status || null,
    durationMs: resource.durationMs || null,
    cacheControl: headersToObject(resource.headers)["cache-control"] || "",
    contentType: headersToObject(resource.headers)["content-type"] || "",
    contentLength: headersToObject(resource.headers)["content-length"] || "",
    headers: headersToObject(resource.headers),
  }));
  const imageUrls = new Set();
  for (const resource of resourceRows) {
    if (resource.type === "image") imageUrls.add(resource.url);
  }
  for (const image of domImages) imageUrls.add(image.url);

  const domByUrl = Object.fromEntries(domImages.map((image) => [image.url, image]));
  const resourceByUrl = Object.fromEntries(resourceRows.map((resource) => [resource.url, resource]));
  const images = [];
  for (const url of Array.from(imageUrls).sort()) {
    const browserResource = resourceByUrl[url] || {};
    let fetched = null;
    let error = "";
    try {
      fetched = await fetchBody(url, browserResource.headers);
    } catch (err) {
      error = err.message;
    }
    const body = fetched?.body || Buffer.alloc(0);
    const fetchHeaders = fetched?.headers || {};
    const browserHeaders = fetched?.browserHeaders || headersToObject(browserResource.headers);
    const dimensions = body.length ? parseDimensions(body) : { width: null, height: null };
    images.push({
      key: canonicalKey(url),
      url,
      status: fetched?.status || browserResource.status || null,
      bytes: body.length,
      browserStatus: browserResource.status || null,
      browserDurationMs: browserResource.durationMs || null,
      resourceType: browserResource.resourceType || "",
      contentType: fetchHeaders["content-type"] || browserHeaders["content-type"] || browserResource.contentType || "",
      cacheControl: fetchHeaders["cache-control"] || browserHeaders["cache-control"] || browserResource.cacheControl || "",
      contentLength: fetchHeaders["content-length"] || browserHeaders["content-length"] || browserResource.contentLength || "",
      etag: fetchHeaders.etag || browserHeaders.etag || "",
      lastModified: fetchHeaders["last-modified"] || browserHeaders["last-modified"] || "",
      server: fetchHeaders.server || browserHeaders.server || "",
      xMsBlobType: fetchHeaders["x-ms-blob-type"] || browserHeaders["x-ms-blob-type"] || "",
      width: dimensions.width ?? domByUrl[url]?.naturalWidth ?? null,
      height: dimensions.height ?? domByUrl[url]?.naturalHeight ?? null,
      naturalWidth: domByUrl[url]?.naturalWidth || null,
      naturalHeight: domByUrl[url]?.naturalHeight || null,
      renderedWidth: domByUrl[url]?.renderedWidth || null,
      renderedHeight: domByUrl[url]?.renderedHeight || null,
      domLoading: domByUrl[url]?.loading || "",
      error,
    });
  }

  const resourcesWithBytes = resourceRows.map((resource) => ({
    ...resource,
    bytes: Number(resource.contentLength) || 0,
  }));

  return {
    label: target.label,
    url: target.url,
    elapsedMs: Date.now() - started,
    documentStatus: documentResponse?.status() || null,
    documentHeaders: documentResponse ? headersToObject(documentResponse.headers()) : {},
    navigation,
    failedRequests,
    domImages,
    images,
    resources: resourceRows,
    resourceSummary: summarizeResources(resourcesWithBytes),
  };
}

function compare(results) {
  const byKey = new Map();
  for (const result of results) {
    for (const image of result.images) {
      if (!byKey.has(image.key)) byKey.set(image.key, {});
      byKey.get(image.key)[result.label] = image;
    }
  }
  return Array.from(byKey.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => {
      const row = { key, ...value };
      const labels = targets.map((target) => target.label);
      const left = value[labels[0]];
      const right = value[labels[1]];
      if (left && right && right.bytes) {
        row.byteDelta = left.bytes - right.bytes;
        row.byteRatio = Number((left.bytes / right.bytes).toFixed(3));
        row.dimensionMatch = left.width === right.width && left.height === right.height;
        row.contentTypeMatch = left.contentType === right.contentType;
      }
      return row;
    });
}

function markdown(payload) {
  const lines = [];
  const labels = payload.targets.map((target) => target.label);
  lines.push("# Browser Homepage Image Comparison");
  lines.push("");
  lines.push(`Run: \`${path.basename(payload.outputDir)}\``);
  lines.push("");
  lines.push("Targets:");
  for (const target of payload.targets) lines.push(`- \`${target.label}\`: \`${target.url}\``);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push("| side | document status | document cache | server cache | images | image bytes | blob images | same-origin images | failed requests |");
  lines.push("| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |");
  for (const result of payload.results) {
    const imageBytes = result.images.reduce((sum, image) => sum + (image.status === 200 ? image.bytes : 0), 0);
    const blobImages = result.images.filter((image) => image.url.includes(".blob.core.windows.net/")).length;
    const host = new URL(result.url).host;
    const sameOrigin = result.images.filter((image) => new URL(image.url).host === host).length;
    lines.push(
      `| \`${result.label}\` | ${result.documentStatus || ""} | \`${result.documentHeaders["cache-control"] || ""}\` | \`${result.documentHeaders["x-opensoft-home-cache"] || ""}\` | ${result.images.length} | ${imageBytes.toLocaleString()} | ${blobImages} | ${sameOrigin} | ${result.failedRequests.length} |`,
    );
  }
  lines.push("");
  lines.push("## Resource Breakdown");
  lines.push("");
  lines.push("| side | type | count | content-length bytes | p50 duration ms |");
  lines.push("| --- | --- | ---: | ---: | ---: |");
  for (const result of payload.results) {
    for (const [type, summary] of Object.entries(result.resourceSummary).sort()) {
      lines.push(`| \`${result.label}\` | \`${type}\` | ${summary.count} | ${summary.bytes.toLocaleString()} | ${summary.durationP50 ?? ""} |`);
    }
  }
  lines.push("");
  lines.push("## Matched Images");
  lines.push("");
  lines.push("| image key | blob bytes | nfs bytes | ratio | blob dims | nfs dims | blob cache | nfs cache |");
  lines.push("| --- | ---: | ---: | ---: | --- | --- | --- | --- |");
  const matched = payload.comparison.filter((row) => row[labels[0]] && row[labels[1]]);
  for (const row of matched) {
    const left = row[labels[0]];
    const right = row[labels[1]];
    lines.push(
      `| \`${row.key}\` | ${left.bytes.toLocaleString()} | ${right.bytes.toLocaleString()} | ${row.byteRatio ?? ""} | ${left.width}x${left.height} | ${right.width}x${right.height} | \`${left.cacheControl}\` | \`${right.cacheControl}\` |`,
    );
  }
  const leftOnly = payload.comparison.filter((row) => row[labels[0]] && !row[labels[1]]);
  const rightOnly = payload.comparison.filter((row) => row[labels[1]] && !row[labels[0]]);
  if (leftOnly.length) {
    lines.push("");
    lines.push(`## ${labels[0]} Only`);
    lines.push("");
    lines.push("| image key | bytes | dims | cache | url |");
    lines.push("| --- | ---: | --- | --- | --- |");
    for (const row of leftOnly) {
      const image = row[labels[0]];
      lines.push(`| \`${row.key}\` | ${image.bytes.toLocaleString()} | ${image.width}x${image.height} | \`${image.cacheControl}\` | \`${image.url}\` |`);
    }
  }
  if (rightOnly.length) {
    lines.push("");
    lines.push(`## ${labels[1]} Only`);
    lines.push("");
    lines.push("| image key | bytes | dims | cache | url |");
    lines.push("| --- | ---: | --- | --- | --- |");
    for (const row of rightOnly) {
      const image = row[labels[1]];
      lines.push(`| \`${row.key}\` | ${image.bytes.toLocaleString()} | ${image.width}x${image.height} | \`${image.cacheControl}\` | \`${image.url}\` |`);
    }
  }
  lines.push("");
  lines.push("Raw data: `homepage-image-browser-compare.json`");
  lines.push("");
  return `${lines.join("\n")}\n`;
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    ...(executablePath ? { executablePath } : {}),
  });
  const results = [];
  try {
    for (const target of targets) {
      results.push(await runTarget(browser, target));
    }
  } finally {
    await browser.close();
  }
  const payload = {
    startedAt: new Date().toISOString(),
    outputDir,
    targets,
    timeoutMs,
    waitAfterLoadMs,
    results,
    comparison: compare(results),
  };
  fs.writeFileSync(path.join(outputDir, "homepage-image-browser-compare.json"), `${JSON.stringify(payload, null, 2)}\n`);
  fs.writeFileSync(path.join(outputDir, "summary.md"), markdown(payload));
  process.stdout.write(`${outputDir}\n`);
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
