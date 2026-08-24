# omeka2hugo/ — converter artifacts

This directory is written by `omeka-to-hugo` for the site **911digitalarchive**
(`https://911digitalarchive.org`). It holds everything the converter produces that is *not* part of
the Hugo source tree. Hugo ignores it, so it never appears in the rendered
`public/` output.

Everything here is **deterministic**: byte-identical across re-runs unless the
source dump (or the captured theme) actually changed. That makes a `git diff` of
this directory a precise record of what each conversion changed.

## Files

- **conversion-manifest.json** — every output path the converter wrote, each
  with its SHA-256, plus per-phase counts, the missing-asset total, and
  ``missing_assets_by_parent`` (that total bucketed by the parent dir of each
  miss, e.g. ``files/original`` vs ``files/thumbnails``). It also carries a
  ``skipped`` block: records that were deliberately *not* emitted because they
  aren't public-facing — non-public items/collections and unpublished simple
  pages — each as ``{reason, count, ascending ids}``, so a diff shows exactly
  which records were newly hidden or revealed. Only record types whose emit
  phase actually ran appear there. Use the manifest to see what changed between
  runs and as a CI summary. (The manifest and the missing-assets log are
  written directly and are not themselves listed inside the manifest, to avoid
  self-reference.)
- **missing-assets.log** — tab-separated list of binary files (images, PDFs,
  audio) that the content references but that were absent from the wget mirror at
  conversion time. Columns: `<absolute-url>\t<referencing-item-id>\t`
  `<expected-on-disk-path>`. Sorted and deduplicated, so a diff surfaces only
  genuinely new misses. Recover by fetching the URLs from the live origin into
  the mirror and re-running.
- **redirects.txt** — legacy Omeka URL rules that Hugo aliases can't express: browse/list endpoints (`/items/browse`, `/collections/browse`, `/tags/browse`) and query-string facets (`?collection=<id>`, `?tags=<name>`). Format `<from>\t<to>\t<status>`, sorted. The header comment shows how to translate the rules into Caddy, nginx, or a Netlify `_redirects` file at deploy time. Per-item and per-collection legacy URLs are handled by Hugo aliases instead and are not duplicated here.
- **theme/** — _(not generated this run; the `theme` phase was skipped)._ Run the `theme` phase to populate the original-frontend matching kit.

## Re-running

Re-run the same `omeka-to-hugo` command to refresh these artifacts. The
converter only rewrites files whose bytes changed, so a no-op re-run leaves this
directory untouched.
