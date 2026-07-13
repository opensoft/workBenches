# nopCommerce Performance Optimization

Updated: 2026-06-29

## Ownership and Storage

This is the canonical place in `workBenches` for nopCommerce optimization
decisions and findings.

Use this split:

- `docs/nopcommerce-performance-optimization.md`: optimization strategy,
  findings, decisions, and production guardrails.
- `docs/opensoft-nopcommerce-cache-test-plan.md`: how to run repeatable cache
  and browser-warming tests.
- `reports/cache-pilot/`: raw timing reports and generated summaries.
- nopCommerce app/plugin repo, later: actual application implementation notes
  once `OpenSoft.CacheWarm`, response headers, or cache invalidation move into
  code.

The DR runbook should only reference the optimization playbook. DR should not be
the owner of these findings.

## Decision

Move the nopCommerce performance work to a server-first, browser-second cache
strategy.

The browser warm-fetch pilot proved useful as an experiment, but it should be
the second layer, not the main production strategy. nopCommerce HTML responses
currently set `no-cache`/`no-store` and user-specific cookies, so a browser
`fetch()` usually cannot make the next navigation reuse the downloaded HTML. It
can still warm server state indirectly and can warm browser-local static/media
work, but it must run after the current page is usable.

The `no-store` header is a hard blocker for the browser-side HTML preload idea.
With `no-store` present, `fetch(url, { cache: "force-cache" })` still downloads
the page, but Chromium does not keep it for the later document navigation. In
that mode, browser warming can only help indirectly by warming server-side
state. If public anonymous HTML is changed to a short browser-private cache
header, the same warm fetch can be reused for the next navigation.

The next design should put the expensive data in memory on the server before
the user asks for it, then let the browser lazily warm likely next actions.

## Target Behavior

For common anonymous catalog flows, the app should already have these in a warm
server cache:

- store configuration and host mapping
- menus, category trees, and homepage widgets
- product/category summary models used by listing pages
- product detail data for popular items
- media metadata and Blob URLs
- WebOptimizer bundles and other generated static assets

The app should not keep large image/blob bytes in nopCommerce pod memory.
Product images should stay in Azure Blob Storage, with a CDN or Azure Front Door
later if the cost/performance tradeoff is worth it.

## Layered Runtime Behavior

Use two coordinated warming layers:

| Layer | What it warms | When it runs | Why |
| --- | --- | --- | --- |
| Server warmer | homepage plus top 3 public landing pages per site | scheduled and after deploy/DR restore | keeps common server data hot before users arrive |
| Browser lazy warmer | likely next public links and static/media hints | after homepage load, quiet wait, and browser idle | warms the user's likely path without blocking first paint |
| Browser intent warmer | exact link under hover/focus/touch | only after user intent | gives the clicked route one last chance to be hot |

The server warmer is the primary layer. The browser warmer is allowed only when
it does not compete with homepage load or click navigation.

The baseline server warm set for every restored site is:

```text
/
top landing page 1
top landing page 2
top landing page 3
```

The top landing pages should be configured per host. If a host does not have an
explicit list yet, discover the first three safe public category/product links
from the homepage and use those as the temporary warm set.

## Homepage In-Memory Cache

Redis can hold homepage HTML easily from a capacity point of view. The current
DigiWrap homepage is about 39 KB, so even many site/language/currency variants
are small cache entries.

The harder question is safety, not size.

The current DigiWrap homepage response includes:

- `.Nop.Customer`, `.Nop.Culture`, `.Nop.Antiforgery`, and `.Nop.TempData`
  cookies
- one `__RequestVerificationToken` occurrence in the rendered HTML
- login, register, customer, cart, and wishlist markup

Because of that, do not implement raw full-homepage replay as a blind cache. A
cached homepage body could contain an antiforgery token or customer/cart-adjacent
markup from the request that created the cache entry. At best, that can break a
later form post; at worst, it can leak user-specific output if the route guards
are wrong.

Recommended order:

1. **Cache homepage data/fragments first.**
   Cache menus, category trees, homepage widgets, product boxes, media metadata,
   and URL mappings. This avoids most SQL and storage work while letting
   nopCommerce still generate per-request cookies and antiforgery values.
2. **Add full anonymous HTML cache only after token/dynamic regions are solved.**
   Either exclude pages with antiforgery tokens, replace token/customer/cart
   regions with per-request placeholders, or split those regions into separate
   uncached AJAX/fragment calls.
3. **Use local memory first for the current one-pod-per-site shape.**
   `IMemoryCache` inside the nopCommerce pod is fastest and cheapest when one
   site has one pod.
4. **Use Redis as L2/shared cache before multi-pod scale.**
   Redis is the right shared cache when one site scales to multiple nopCommerce
   pods, or when cache invalidation must coordinate across pods.

The practical target is a hybrid cache:

```text
request -> nopCommerce/OpenSoft cache plugin
        -> L1 pod memory cache
        -> L2 Redis cache, when enabled
        -> SQL/Blob/NFS source of truth on miss
```

Cache key shape:

```text
os:nop:home:{storeId}:{host}:{culture}:{currency}:{theme}:{role}:{version}
```

Minimum full-HTML cache guards, if/when we test it:

- `GET` or `HEAD` only
- anonymous public homepage only
- HTTP `200` only
- no authenticated customer
- no cart, checkout, customer, admin, login, register, order, wishlist, search,
  or password recovery paths
- no arbitrary query strings
- vary by host, store, language, currency, theme, customer role bucket, and app
  version
- short TTL first, such as 60 to 120 seconds
- never cache `Set-Cookie` headers
- never store a response body containing per-request antiforgery or customer
  state unless those regions are replaced per request

Redis is therefore a good place to store homepage cache entries after the app
knows exactly what is safe to store. Redis by itself is not the safety layer; the
nopCommerce/OpenSoft cache code is.

### DigiWrap QA Memory-Cache Pilot

Implemented on 2026-06-28 for the DigiWrap QA alias:

```text
Host: digiwrap.davinci-designer.com
Namespace: digiwrap-qa-davincisite-com
Deployment: opensoft-homepage-memory-cache
Service: opensoft-homepage-memory-cache
Script: scripts/apply-opensoft-nopcommerce-homepage-memory-cache.sh
```

This is a QA-only reverse-proxy pilot, not the final production architecture.
The existing DigiWrap ingress backend is patched to the memory-cache proxy. The
proxy caches only exact `/` in process memory and forwards everything else to
the original nopCommerce service.

Current behavior:

- cache only `GET /`
- cache only no-cookie, no-auth, no-query requests
- bypass any request with `Cookie`, `Authorization`, query string, or
  `Cache-Control: no-cache/no-store`
- bypass every non-homepage path, such as product, cart, checkout, and admin
- store one homepage body in local pod memory, 1 MiB max, 180 second TTL
- preserve `Set-Cookie` only on origin misses, never on memory-cache hits
- internal status endpoint is available only inside the cluster; public access
  returns `404` with `no-cache, no-store`

Rollback:

```bash
ACTION=delete ./scripts/apply-opensoft-nopcommerce-homepage-memory-cache.sh
```

Latest quick timing report:

```text
reports/cache-pilot/homepage-memory-cache-20260628T210900Z/
```

30 cache-hit attempts were compared with 30 cookie-bypass origin attempts:

| Mode | 200s | Cache Header | TTFB p50 | Total p50 | Total p95 |
| --- | ---: | --- | ---: | ---: | ---: |
| Memory cache hit | 30/30 | `HIT` | 546.6 ms | 772.7 ms | 1473.0 ms |
| Origin bypass | 29/30 | `BYPASS-cookie` | 756.4 ms | 929.6 ms | 1670.3 ms |

Observed p50 total improvement was 16.9 percent. One bypass attempt failed to
connect to the public ingress and was excluded from timing percentiles.

Interpretation:

- Server memory caching helps the homepage document path.
- The gain is real but modest compared with the browser-document cache test,
  because public ingress/network overhead remains and the page still has
  client-side/static resource work.
- This pilot avoids Redis because the current site shape is one pod per site.
  Redis should be added when a single site scales to multiple nopCommerce pods
  or when cache invalidation must be shared across replicas.

### Blob Plus Memory Cache vs NFS Directional Test

The production question is whether the proposed shape is faster than the
current production-style NFS shape:

```text
Current shape: nopCommerce origin + NFS wwwroot/media
Proposed shape: Blob media + homepage memory cache
```

The current QA stack has a useful directional comparison for DigiWrap:

| Shape | Host | Notes |
| --- | --- | --- |
| Blob + memory cache | `digiwrap.davinci-designer.com` | Blob media URLs plus `opensoft-homepage-memory-cache` |
| NFS-like baseline | `digiwrap.qa.davincisite.com` | local `/images/thumbs/...` media through the direct nop service |

This is not a perfect production A/B because the hostnames have slightly
different store/media settings and headers, but it compares the closest current
QA variants for the same DigiWrap content.

Latest browser-shape report:

```text
reports/cache-pilot/blob-mem-vs-nfs-homepage-20260628T211710Z/
```

Five clean-browser iterations per shape:

| Shape | Runs | ResponseStart p50 | Load p50 | Transfer p50 | Image p50 | Image p95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Blob + memory cache | 5 | 689.0 ms | 9340.9 ms | 1,523,906 bytes | 4419.0 ms | 19920.9 ms |
| NFS-like baseline | 5 | 2314.3 ms | 10286.2 ms | 529,366 bytes | 2466.5 ms | 8801.7 ms |

Interpretation:

- Blob + memory cache improved the document response start substantially.
- Full page `load` p50 was only modestly better for Blob + memory cache in this
  small run.
- Blob media was slower and heavier in the current QA shape. The Blob page
  transferred about 1.5 MB at p50 versus about 0.53 MB for the NFS-like page.
- This means "Blob + memcache is faster than NFS" is not proven yet. The
  document path is faster, but the media path can erase the gain.

Next tests before a production decision:

- compare the same exact media assets from NFS and Blob, not only whole-page
  behavior
- verify whether Blob is serving larger/unoptimized variants than NFS
- test Blob behind Azure Front Door/CDN, if that is the intended production
  delivery path
- run at least 20 clean-browser iterations after image-size parity is confirmed
- include repeat-visit browser cache tests, because static/media cache headers
  may change the result after the first page view

## DigiWrap Media Parity and In-Cluster Cache Test

On 2026-06-29, DigiWrap homepage image URLs were compared between:

```text
https://digiwrap.davinci-designer.com/
https://digiwrap.qa.davincisite.com/
```

Reports:

```text
reports/cache-pilot/image-url-compare-20260628T213254Z/
reports/cache-pilot/browser-image-compare-20260628T213845Z/
reports/cache-pilot/browser-image-compare-media-cache-20260628T214433Z/
reports/cache-pilot/homepage-shape-media-cache-vs-nfs-20260628T214631Z/
```

Findings:

- The browser-loaded homepage images matched by filename, bytes, dimensions, and
  content type.
- The matched homepage image bytes were identical: Blob/media-cache and NFS both
  served 486,438 bytes of successful image bodies in the browser capture.
- Blob was not serving larger homepage image variants. The earlier whole-page
  transfer gap was mostly static bundle and routing behavior, not image-size
  mismatch.
- A QA in-cluster media-cache pilot rewrote the DigiWrap Blob prefix to
  `/__opensoft-media-cache/` and cached image bodies inside the homepage proxy
  pod.
- A warmed single-image test for
  `0001554_digital-tissue-paper_600.jpeg` measured median times from the same
  client path of about 7.5s via media-cache, 8.7s direct to Blob, and 6.9s via
  NFS. That is not enough to justify replacing NFS with an in-cluster cache for
  performance.
- The first media-cache full-page shape test was slower than NFS:
  media-cache load p50 about 15.2s versus NFS about 8.0s. This result was
  affected by a proxy routing mistake, but it still does not prove the cache is
  better.

Important implementation lesson:

- Do not route the whole hostname `/` prefix through the Node homepage proxy.
  That forces CSS, JavaScript, fonts, and other static files through a buffering
  Node path and can make large bundles extremely slow.
- The correct QA ingress shape for this style of pilot is:
  `/__opensoft-media-cache/` prefix to the cache proxy, exact `/` to the cache
  proxy, and remaining `/` prefix traffic directly to nopCommerce.
- Static assets must keep long browser cache headers such as
  `public, max-age=31536000, immutable`. The short
  `private, max-age=120, stale-while-revalidate=60` rule is for dynamic
  anonymous HTML only.

Decision from this test: keep Blob as a DR/source-of-truth option, but do not
replace the current NFS serving path with in-cluster media-cache for performance
yet. The cheaper next tuning is static/header hygiene, direct routing for
static assets, bundle reduction, and nopCommerce server-side data or fragment
cache.

## Browser-Private HTML Cache Experiment

On 2026-06-27, the OpenSoft QA DR stack tested disabling `no-store` for the
DigiWrap DR alias only:

```text
Host: digiwrap.davinci-designer.com
Ingress: digiwrap-qa-davincisite-com/digiwrap-davinci-designer
Header: Cache-Control: private, max-age=120, stale-while-revalidate=60
Scope: HTTP 200 public responses only
Redirects/errors: Cache-Control: no-cache, no-store
Protected paths: admin, login, register, logout, cart, wishlist, checkout,
customer, order, passwordrecovery, search
```

The test also re-enabled the DigiWrap browser lazy warmer:

```text
maxIdlePages: 3
allowIntentWarm: true
```

Probe script:

```bash
node scripts/lib/nopcommerce-browser-cache-probe.js
```

Result:

- DigiWrap warm fetches completed for three public product pages.
- The later navigation to `/digital-tissue-paper` was served from Chromium disk
  cache.
- The navigation document reported `transferSize: 0`,
  `fromDiskCache: true`, and response start at about 1 ms.
- A control run against `qa1.overnightprints.eu`, still returning
  `Cache-Control: no-cache, no-store`, did not use browser cache for the warmed
  category page.

This proves the earlier browser-side result was limited by `no-store`, not only
by the warm-fetch timing.

The QA ingress implementation is an experiment, not the production target. It
required enabling ingress-nginx snippet annotations in the QA cluster and should
not be copied into production unchanged. Production should set these headers in
nopCommerce/application code, a dedicated plugin, or a carefully reviewed edge
policy with route, status, and authentication guards.

## Cache Layers

Use the layers in this order:

| Layer | Purpose | Production default |
| --- | --- | --- |
| nopCommerce process memory | Fastest cache for one pod and hot per-pod data | Yes |
| Redis Synchronized Memory | Local memory cache with Redis synchronization across pods | Preferred multi-replica target |
| Redis distributed cache | Shared cache/session coordination across pods | Required before multi-replica |
| SQL and Blob | Durable source of truth | Always |
| Browser lazy warmer | Secondary warm layer for likely user path | Yes, constrained |
| Browser/CDN | Static asset and media delivery | Static/media only |

For the current OpenSoft QA DR stack, each restored site is running one
nopCommerce pod. That means per-pod memory is a good first test because every
visitor for that site reaches the same app instance. Once a site runs more than
one replica, plain per-pod memory becomes inconsistent unless the ingress uses
sticky routing. At that point, Redis or Redis Synchronized Memory should be
enabled.

## What Not To Cache

Do not server-cache these as generic shared responses:

- admin pages
- login/register/logout
- cart, checkout, wishlist, customer, order, and password recovery
- search results with arbitrary query strings
- antiforgery forms
- any page whose output changes by authenticated customer, cart, discount,
  role, or private account state

Full-page HTML caching is only safe later if it is explicitly anonymous-only and
varies by host, store, language, currency, theme, device behavior, and customer
role. For now, cache data/models and reusable fragments instead of whole pages.

If browser-private HTML caching is enabled for public catalog pages, use these
minimum guards:

- `private`, never `public`, for dynamic nopCommerce HTML
- short TTL first, such as 60 to 120 seconds
- only successful `200` responses
- no admin, auth, cart, checkout, customer, order, wishlist, search, or password
  recovery paths, including localized path variants
- no arbitrary query-string caching
- no shared CDN caching until the app can explicitly mark anonymous-safe output

## Recommended Test Path

### Phase A: Server Warmer Without nopCommerce Code Changes

Keep the current in-cluster CronJob idea, but treat it as a server warmer, not a
browser-first feature.

Change the test shape to:

- keep the homepage and top 3 public landing pages warm on the server
- keep browser warm-fetch as the second layer, running only after load, a quiet
  wait, and browser idle
- keep lightweight `preconnect`/`dns-prefetch` for cross-origin media if it
  stays harmless in measurements
- run a Kubernetes CronJob from inside the cluster
- request each restored hostname through the real ingress and Host header
- warm `/` first, then the configured top 3 safe public landing pages
- use a crawler-style user agent so nopCommerce does not create guest customers
  from the warmer
- rate-limit per host so the warmer never competes with users
- record status, bytes, TTFB, total time, and errors

This phase warms nopCommerce's existing internal caches, WebOptimizer output,
SQL connection pools, TLS, and Blob/media metadata paths. It is not perfect, but
it is cheap and does not require app source changes.

### Phase B: nopCommerce Cache Warm Plugin

Add a small OpenSoft plugin or application extension when we have the app source
or custom image build path ready.

Recommended component name:

```text
OpenSoft.CacheWarm
```

Responsibilities:

- register a bounded memory cache for OpenSoft warmed entries
- expose an internal warm endpoint, protected by a shared secret and Kubernetes
  network policy
- warm selected scopes: `homepage`, `navigation`, `categories`, `popular-products`
- optionally warm on app startup with low priority
- expose cache health and counters for hit, miss, eviction, warm duration, and
  warm errors
- use nopCommerce services to build cache entries rather than scraping rendered
  HTML

Example internal endpoint:

```text
POST /opensoft/cache/warm?scope=homepage
X-OpenSoft-Warm-Secret: <secret>
Host: digiwrap.davinci-designer.com
```

The Kubernetes CronJob then calls the internal endpoint instead of making
browser-like page requests. That moves warming fully into the server path and
avoids spending user browser time.

### Phase C: Redis Synchronized Memory

Before increasing a site above one nopCommerce replica, enable nopCommerce
distributed cache.

First test plain Redis:

```json
"DistributedCacheConfig": {
  "Enabled": true,
  "DistributedCacheType": "Redis",
  "ConnectionString": "<redis-host>:6380,password=<secret>,ssl=True,abortConnect=False",
  "InstanceName": "nopCommerce"
}
```

Then test `Redis Synchronized Memory`, which is the better target if it behaves
well in our AKS stack. It keeps hot cache data in local app memory and uses Redis
to synchronize cache changes across instances.

## Cache Key Rules

Cache keys must be explicit and bounded. Do not key directly on arbitrary input.

Use this shape:

```text
os:nop:{storeId}:{host}:{culture}:{currency}:{role}:{scope}:{routeHash}:{version}
```

Include:

- store id
- accepted host
- language/culture
- currency
- customer role bucket, usually `Guests` for public pages
- cache scope
- normalized route or entity id
- content version or deploy version

Use short TTLs first:

| Data | First TTL |
| --- | ---: |
| homepage widgets | 5 minutes |
| category/product summary models | 5 to 15 minutes |
| navigation/category tree | 30 to 60 minutes |
| media metadata and Blob URL mapping | 1 to 6 hours |
| WebOptimizer/static bundles | existing nopCommerce/WebOptimizer setting |

The app must always be able to rebuild the data from SQL/Blob if the cache is
empty.

## Invalidation

Start with TTL plus deploy-time clear because that is simple and safe.

Then add event-driven invalidation for:

- product changes
- category changes
- manufacturer changes
- topic/page changes
- store, language, currency, and setting changes
- plugin/theme deploys
- media upload or deletion

On DR restore, cache contents are not restored. They are disposable. The restore
runbook should enable the cache configuration, start the app, then run the server
warmer before handing the site to testers.

## Kubernetes Shape

Use one namespace for shared warmer infrastructure:

```text
nopcommerce-cache
```

Use one ConfigMap for host and warm-scope configuration:

```text
opensoft-nopcommerce-server-warmer-hosts
```

Use one CronJob for steady warming:

```text
opensoft-nopcommerce-server-warmer
```

For Phase A, the CronJob calls public safe URLs through ingress.

For Phase B, the CronJob calls the protected internal warm endpoint. The secret
should live in Kubernetes Secret or Key Vault-backed secret sync, not in the
ConfigMap.

## Test Plan Changes

The next performance test should isolate the layers first, then measure the
combined user experience.

Run these phases:

1. Server warmer OFF, browser lazy warmer OFF.
2. Server warmer ON, browser lazy warmer OFF.
3. Server warmer ON, browser lazy warmer ON.

Do not run a primary test where browser lazy warming is ON and server warming is
OFF. That combination spends user resources to compensate for a cold server,
which is not the target operating model.

Measure:

- homepage p50/p95 TTFB and total time
- next-page p50/p95 TTFB and total time
- nopCommerce pod CPU/memory
- SQL CPU/DTU/vCore utilization
- warmer request count and errors
- cache hit/miss counters if Phase B is implemented

Decision rule:

- keep the server warmer if it improves p95 by at least 20 percent on most
  warmed hosts without raising errors or pod CPU/memory materially
- keep browser lazy warming only if phase 3 improves next-page p50 or p95 over
  phase 2 without hurting homepage load or increasing errors

## Current Recommendation

For the OpenSoft QA DR stack:

1. Make server warming the primary layer.
2. Keep `/` plus the top 3 public landing pages warm per site.
3. Keep browser lazy warming as the secondary layer after load, quiet wait, and
   browser idle.
4. Measure server-only first, then server-plus-browser.
5. Add Redis before any multi-replica nopCommerce test.
6. Build `OpenSoft.CacheWarm` only when we are ready to change the nopCommerce
   image/plugin layer.

This gives us a low-cost test now and a clean path to a production-grade cache
later.

## Sources

- nopCommerce appsettings, cache, distributed cache, Redis Synchronized Memory,
  and WebOptimizer settings:
  https://docs.nopcommerce.com/en/developer/tutorials/appsettings-json-file.html
- nopCommerce Azure multiple-instance notes:
  https://docs.nopcommerce.com/en/installation-and-upgrading/installing-nopcommerce/installing-on-microsoft-azure.html
- nopCommerce web farms and distributed cache guidance:
  https://docs.nopcommerce.com/en/installation-and-upgrading/installing-nopcommerce/web-farms.html
- ASP.NET Core distributed cache guidance:
  https://learn.microsoft.com/en-us/aspnet/core/performance/caching/distributed
- ASP.NET Core in-memory cache guidance:
  https://learn.microsoft.com/en-us/aspnet/core/performance/caching/memory
