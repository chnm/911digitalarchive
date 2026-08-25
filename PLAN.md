# 911 Digital Archive — Omeka → Hugo Migration Plan

Tracks what the Omeka Classic → static Hugo migration has accomplished and what
remains. The site is served as a static Hugo build behind Caddy; media (`/files/*`)
is redirected to object storage by a fronting server.

_Last updated: 2026-08-24._

---

## Status snapshot

| Area | State | Notes |
|---|---|---|
| Container build (CI) | ✅ Fixed | `hugobuildargs` default was whitespace-split by `ARG`; removed so CI supplies flags per branch. |
| Legacy-URL redirects reach the deploy | ✅ Fixed | `redirects.caddy` now ships inside `/srv` (was `/etc/caddy/`, outside the extracted artifact). |
| Redirect infinite loops | ✅ Fixed | Removed self-referential `/items/ → /items/` and `/collections/ → /collections/` map entries. |
| Media (`/files/*`) | ✅ Working | Resolves `200` on dev via the object-storage handoff. |
| Analytics (Matomo) | ✅ Wired | `stats.rrchnm.org`, `idsite=2`; firing on dev. Confirm `idsite` for prod. |
| Favicon | ➖ Intentionally none | Original `911digitalarchive.org` has no favicon (`/favicon.ico` 404, no `<link rel=icon>`); parity kept. |
| **Theme / design fidelity** | ❌ Placeholder | Layouts are bare; `assets/css/site.css` says `minimal placeholder; expand later`. `omeka2hugo/theme/` matching kit unused. |
| **Search** | ⚠️ Partial | Pagefind index builds & ships to `/srv/pagefind/`, but no page loads it (no UI). |
| Redirect generator | ⚠️ Bug upstream | `omeka-to-hugo` emits identity redirects (`from == to`); the artifact was hand-patched and now diverges from the manifest. |
| Conversion reproducibility | ⚠️ At risk | Manifest `source_root`/`db_sqlite` point to an ephemeral scratchpad that no longer exists. |

Scale: **70,359 items**, **247 collections**, **277** `redirects.txt` rules
(`omeka2hugo/redirects.txt`), **8** live Caddy map keys (`redirects.caddy`, was 10
before the loop fix).

Branch `fix-hugo-build-args` carries the shipped fixes:
`55f67818` (build), `3bc16680` (redirects → `/srv`), `f4009c32a` (loop fix).

---

## Workstreams & next steps (prioritized)

### 1. Theme & design fidelity — the biggest gap

The Hugo layouts are an admitted placeholder: unstyled nav + lists that look
nothing like the original site. A complete matching kit already exists in
`omeka2hugo/theme/` for the original `nineeleven-omeka` theme but has **not been
applied**. Its README defines the workflow:

1. Make the Hugo layouts emit the class/DOM contract in `theme/selectors.json`
   (currently `verified_against_dom: false` — confirm with the harness).
2. Load the vendored `theme/legacy-css/` **first**, then a thin override sheet.
3. Feed `theme/theme-profile.json` (logo, tagline, colors, footer) and
   `theme/nav.json` (primary nav) into the templates for the site chrome.
4. Render Dublin Core fields in `theme/element-order.json` order (not alphabetical).
5. Verify against `theme/verify-targets.tsv` with the `theme-verify` harness.
6. Mirror needed images/fonts from `theme/original-assets.tsv` into Hugo `static/`.

This is the bulk of the remaining work.

### 2. Search — Pagefind now, SQLite-in-the-browser for scale

Hybrid strategy: keep **Pagefind** where it's the better fit; add
**SQLite-in-the-browser** (`sql.js-httpvfs`) where Pagefind fails at runtime.
911 is a ~70k-item site, so it is a prime candidate for the SQLite route — but
that is a **Phase 0 decision**, not an assumption (see below).

**2a. Finish the Pagefind wiring (near-term, low effort).** The index already
builds (`npx pagefind … --glob "items/*/index.html"`) and ships to
`/srv/pagefind/`; item pages carry `data-pagefind-body` / `-filter` / `-meta`.
What's missing is the frontend: no layout loads `pagefind-ui.{js,css}`, there's
no search box or `/search` page. Add a search partial + page and hook it into the
header. This makes the existing index usable immediately and gives a working
baseline to measure the SQLite route against.

**2b. SQLite-in-the-browser (`sql.js-httpvfs`) — for large sites.** Detailed
plan below. Put both backends behind one thin `search(query) -> results[]`
interface so Pagefind sites and SQLite sites share the same UI.

### 3. Redirects — fix upstream, decide on query facets

- **Generator fix (durable):** `omeka-to-hugo` adds a trailing-slash variant of
  each from-path, turning `/items → /items/` into the identity `/items/ → /items/`
  (the loop we hand-patched out). The generator should skip emitting redirects
  where `from == to`. Until then, `redirects.caddy` diverges from the manifest
  (`counts.redirects_caddy: 10` vs. 8 shipped) and a regen would reintroduce the
  loops. `omeka2hugo/redirects.txt` is already correct — no change there.
- **Query-facet rules:** `redirects.txt` includes ~250 per-collection facets
  (`/items/browse?collection=N → /collections/N/`), but Caddy's `map` keys on path
  only, so they collapse to `/items/`. If preserving those inbound links matters
  (SEO), handle them at a query-aware layer (fronting server rule or client JS).

### 4. Conversion reproducibility

`conversion-manifest.json` records `source_root` / `db_sqlite` under a
`/tmp/…/websites-mirrorer/…` scratchpad that is gone. Re-running the converter —
for new content, re-theming, or the generator fix above — needs the wget mirror +
SQLite dump re-established. Capture the source location and exact `omeka-to-hugo`
command somewhere durable (this doc, or a `docs/CONVERSION.md`).

### 5. Content QA

The item template renders title + a subset of Dublin Core + the file link.
Confirm across the corpus: all element sets/item types render (in
`element-order.json` order), and every media kind displays (image, audio, video,
PDF, multi-file items). `missing_assets: 0` is reassuring but came from a
redirects-only converter run — re-confirm against the full-content conversion.

### 6. Production cutover checklist

Before pointing `911digitalarchive.org` at the Hugo deploy:

- [ ] `main` build with `--minify` succeeds end-to-end (prod build path).
- [ ] Prod Caddy imports `redirects.caddy` from the deployed content root.
- [ ] `/files/*` → object-storage rule exists on the prod fronting server.
- [ ] Matomo `idsite` correct for prod.
- [ ] Spot-check legacy redirects and a sample of items/collections on prod.

---

## Static search implementation plan (SQLite-in-the-browser)

**Goal:** Add SQLite-in-the-browser full-text search (via `sql.js-httpvfs`) to the
large static sites where Pagefind fails at runtime, while keeping Pagefind on the
small sites where it's the better fit.

**Architecture:** Hybrid. Small sites stay on Pagefind. Large sites host a single
read-only `.sqlite` file (built with FTS5) that the browser queries over HTTP
Range requests, fetching only the pages each query touches instead of downloading
a whole index.

### Phase 0 — Validate the premise and lock decisions

The highest-leverage step, because it can shrink or cancel the project.

Before writing any code, confirm *where* Pagefind actually fails on the large
sites. Reproduce the failure and determine whether it is:

- **Build-time** — the indexer crashing/OOM during `pagefind` runs. A large FTS5
  build also costs memory, so migrating may not help. Consider sharding the
  Pagefind build or raising Node's heap instead.
- **Runtime** — index too big to ship, or slow first query. This is the case
  SQLite-in-the-browser genuinely solves.

Only route a site to SQLite if its failure is genuinely runtime.

Then lock the decisions that shape everything downstream:

- Which specific sites cross into the SQLite route (confirm the rest stay on Pagefind).
- Confirm every indexed field is genuinely **public** — the entire `.sqlite` is
  world-readable, so nothing sensitive goes in it.
- Page size — start at **1024** for text search (more, smaller Range requests).
- Single-file vs. sharded, based on each site's DB size and the host's file-size limits.
- Hosting topology per site — Caddy serving directly, or HAProxy fronting a Caddy/nginx origin.

**Deliverable:** A one-page decision doc listing, per site, its route (Pagefind vs.
SQLite), page size, sharding yes/no, and hosting topology — plus explicit success
criteria (e.g. "first query returns in <X ms, transfers <Y KB, over a site of N pages").

### Phase 1 — Build the index pipeline

The backend half. Can be developed in parallel with Phase 2 against a sample DB.

Write an indexer that runs *after* the SSG build: it walks the rendered output,
parses each page into `url`, `title`, and `body`, and loads them into a SQLite
FTS5 external-content table.

Key points:

- Build with the **native `sqlite3` CLI**, not sql.js — the CLI has FTS5 compiled
  in, avoiding the classic trap of stock sql.js lacking it.
- Finish every build with the mandatory ritual, or queries will fetch far more of
  the file than they should:
  - `INSERT INTO <fts>(<fts>) VALUES('rebuild');`
  - `INSERT INTO <fts>(<fts>) VALUES('optimize');`
  - `pragma journal_mode = delete;` (required before changing page size)
  - `pragma page_size = 1024;`
  - `vacuum;`
- If sharding (from Phase 0), run phiresky's `create_db.sh` to split the DB and
  emit its JSON config.
- Add ordinary B-tree indices on any columns you filter/sort on outside of FTS.

Wire this into CI/CD so the `.sqlite` is regenerated and published on every content
deploy, exactly like the Pagefind index is today.

**Deliverable:** A repeatable `build-search-index` step that outputs a
query-efficient `search.sqlite` (or shards + config) into the publish directory,
integrated into the pipeline.

### Phase 2 — Client integration

The frontend half.

- Add `sql.js-httpvfs`, and **self-host** its two static assets
  (`sqlite.worker.js` and `sql-wasm.wasm`) rather than hotlinking a CDN — that
  code runs with full page access, so this matters for supply-chain safety.
- Build the search UI:
  - Debounced input (~150 ms).
  - Query with `MATCH`, ordered by `rank` (FTS5's implicit BM25 score).
  - `snippet()` for highlighted excerpts.
  - Trailing `*` on the term for prefix / as-you-type matching.
  - Join results back to the source table for the URL.
- Set `requestChunkSize` to **exactly match** the page size chosen in Phase 0.
- Handle cold-start honestly: ~1 MB of WASM (≈500 KB gzipped) loads before the
  first query. **Lazy-load on first focus** of the search box, not on page load,
  and show a small loading state.
- During development, surface `getStats()` (`totalFetchedBytes`, `totalRequests`)
  on screen — the fastest signal that an index is missing or a query is scanning.

Put both search backends behind one thin interface (`search(query) -> results[]`)
so Pagefind sites and SQLite sites share the same UI, results markup, and keyboard
handling. This keeps the hybrid from becoming two codebases.

**Deliverable:** A working search component, tested locally against a
**range-capable** static server. (Many SSG dev servers don't serve Range requests,
so it may look broken locally — test against a real static file server.)

### Phase 3 — Hosting and infrastructure

Configure whichever server touches the file. The unifying rule: **never compress
the `.sqlite`** — compression and Range are mutually exclusive.

**Caddy (serving directly):**

- Exclude the `.sqlite` from `encode` via a matcher so its `Accept-Ranges` header
  survives:
  ```caddy
  example.com {
      root * /srv/site
      @compressible not path *.sqlite
      encode @compressible zstd gzip
      file_server
  }
  ```
- Don't ship a precompressed `.gz` sidecar of the DB.

**HAProxy (fronting an origin):**

- Relies on transparent passthrough — it forwards `Range` and returns 206 without
  interference.
- Keep the DB's content-type out of the `compression type` list.
- Don't expect the built-in cache to help; it can't cache 206 responses.

**Both:**

- Serve the `.sqlite` as `application/octet-stream` (or `application/vnd.sqlite3`).
- Add CORS for the `Range` header if the DB is on a different origin than the site.

**Deliverable:** Infra config committed and verified end-to-end (through HAProxy if
present, not just against the origin) with:

```bash
curl -s -D - -o /dev/null -H "Range: bytes=0-1023" https://example.com/search.sqlite
```

Expect `206 Partial Content`, `Content-Range: bytes 0-1023/<total>`, and
`Content-Length: 1024`. A `200` with the full length means range serving is broken
— usually compression somewhere in the chain.

### Phase 4 — Test and validate

- Run the range test through the full production path.
- Validate query correctness and relevance ranking against a set of known queries.
- Check the bytes-per-query budget via `getStats`; add indices if anything scans.
- Test cross-browser and on mobile (WASM cold-start is heaviest on low-end devices).
- The key comparison: run the actual failing large sites through the new path and
  confirm they now work and beat the Pagefind baseline against the Phase 0 success
  criteria.

**Deliverable:** A short validation report confirming the target sites meet the
criteria, plus a list of any indices/tuning added.

### Phase 5 — Rollout

- Pilot on a single large site first; monitor real-world query latency and transfer
  sizes.
- Roll to the remaining large sites once the pilot holds.
- Leave small sites on Pagefind.
- Document the pipeline and the one maintenance caveat: `sql.js-httpvfs` isn't
  actively developed, so pin the version, keep assets self-hosted, and note
  `wa-sqlite` as the migration path if ever needed (low risk — it's a read-only,
  client-side dependency).

**Deliverable:** All target sites migrated, runbook documented, Pagefind retained
where it's the better fit.

### Sequencing

- **Phase 0 gates everything.**
- **Phases 1 and 2 run in parallel** (build the pipeline and the client against a
  sample DB simultaneously).
- **Phases 3 → 4 → 5 are sequential.**
- Realistic first milestone: one large site fully working end-to-end. Everything
  after is repetition plus tuning.

### Watch these two early

1. The **compression-breaks-Range** trap in Phase 3.
2. Confirming in Phase 0 that the failure is **runtime, not a build-time OOM** you'd
   otherwise carry straight into the new stack.

---

## Reference points

- Build fix — `Dockerfile` (`ARG hugobuildargs`, no default).
- Redirect artifact — `redirects.caddy` (imported from `/srv` at deploy).
- Redirect source & converter outputs — `omeka2hugo/redirects.txt`,
  `omeka2hugo/conversion-manifest.json`, `omeka2hugo/README.md`.
- Theme matching kit — `omeka2hugo/theme/` (+ its `README.md`).
- Pagefind index build — `Dockerfile` stage 7; item annotations in
  `layouts/items/single.html`.
- Reusable CI/deploy — `chnm/.github` `hugo--build-release-deploy.yml`
  (extracts `/srv`, deploys via `hugo-ansible-deploy`).
