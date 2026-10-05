# Website

Static pages in `src/pages` (HTML fragments with a `title`/`description` header) and `src/assets`. Build:

```sh
dart run tools/build_website.dart [--site-url https://<host>/<base>]
```

Output goes to `website/build` (not committed). `{{key}}` placeholders are filled from `docs/benchmarks/*.json`, so pages only show measured numbers. The build fails on broken internal links, duplicate or over-long titles/descriptions, unbalanced tags, scripts in page bodies, and size budgets. `.github/workflows/website.yml` builds, checks external links and deploys to GitHub Pages.
