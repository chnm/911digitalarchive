# theme/ — original-frontend matching kit

Deterministic, offline inputs for reproducing the look of the original Omeka
site (theme: **nineeleven-omeka**) on the converted Hugo site. Produced
by `omeka-to-hugo`; byte-identical across re-runs.

The intended workflow is: (1) make the Hugo layouts emit the class/DOM contract
in `selectors.json`, (2) load the vendored `legacy-css/` first plus a thin
override sheet, (3) feed `theme-profile.json` / `nav.json` into your templates
for the site chrome, and (4) check the result with the `theme-verify` harness
driven by `verify-targets.tsv`.

## Files

- **theme-profile.json** — active theme name + the admin-set theme options
  (logo, tagline, colors, footer text) parsed from the Omeka `omeka_options`
  table. The authoritative source for the site chrome.
- **element-order.json** — per element set (and item type), the canonical field
  **display order** Omeka used. Render Dublin Core in this order rather than
  alphabetically.
- **nav.json** — the reconstructed primary navigation (labels, order, targets,
  including item-type facets), from the `public_navigation` option or derived.
- **selectors.json** — the HTML class/DOM contract the vendored stylesheet
  expects. `verified_against_dom` is false: confirm with the harness.
- **legacy-css/** — the original theme stylesheet(s), vendored verbatim. Load these **first** in Hugo, then your override sheet.
- **original-assets.tsv** — inventory (`relpath  sha256  bytes`) of the whole original theme tree; mirror images/fonts into Hugo `static/` as needed.
- **verify-targets.tsv** — a deterministic sample of
  `original_url  hugo_path  kind` pairs for the `theme-verify` harness to diff.
  The converter chooses the sample; the (browser-based) harness does the
  rendering, so nothing here touches the network.

## Determinism

All JSON is emitted with sorted keys; TSVs are sorted; the asset inventory is
hashed and sorted. Nothing here records timestamps or per-run state, so a
`git diff` of this directory reflects only genuine source/theme changes.
