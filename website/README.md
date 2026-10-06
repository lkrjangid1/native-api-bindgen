# Website

Static pages in `src/pages` (HTML fragments with a `title`/`description` header) and `src/assets` (`style.css` with light/dark themes, `site.js` for the theme toggle and copy buttons). Every Markdown file in `docs/` is also published under `docs/` on the site with a sidebar, table of contents and previous/next links; the sidebar order is `docGroups` in `tools/website/docs.dart` (unlisted files appear under "More"). Build:

```sh
dart run tools/build_website.dart [--site-url https://lkrjangid1.github.io/native-api-bindgen-docs/]
```

Preview locally (serve the **build** output, not `src/pages` — the source pages are fragments without `<head>`, styles or images):

```sh
dart run tools/build_website.dart && python3 -m http.server 8000 -d website/build
```

Output goes to `website/build` (not committed). `{{key}}` placeholders are filled from `docs/benchmarks/*.json`, so pages only show measured numbers. The build fails on broken internal links, duplicate or over-long titles/descriptions, unbalanced tags, scripts in page bodies, and size budgets. `.github/workflows/website.yml` builds, checks external links and deploys to GitHub Pages.
