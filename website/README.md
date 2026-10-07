# Website

Static pages in `src/pages` (HTML fragments with a `title`/`description` header) and `src/assets` (`style.css` with light/dark themes, `site.js` for the theme toggle and copy buttons). Every Markdown file in `docs/` is also published under `docs/` on the site with a sidebar, table of contents and previous/next links; the sidebar order is `docGroups` in `tools/website/docs.dart` (unlisted files appear under "More"). Build:

```sh
dart run tools/build_website.dart [--site-url https://lkrjangid1.github.io/native-api-bindgen-docs/]
```

Preview locally (serve the **build** output, not `src/pages` — the source pages are fragments without `<head>`, styles or images):

```sh
dart run tools/build_website.dart && python3 -m http.server 8000 -d website/build
```

Output goes to `website/build` (not committed). `{{key}}` placeholders are filled from `docs/benchmarks/*.json`, so pages only show measured numbers. The build fails on broken internal links, duplicate or over-long titles/descriptions, unbalanced tags, scripts in page bodies, and size budgets.

SEO: every page gets a canonical URL, Open Graph and Twitter card tags (`src/images/og-image.jpg`, 1200×630), JSON-LD (TechArticle + BreadcrumbList; WebSite and SoftwareApplication on the home page) and a `lastmod` in `sitemap.xml` from git history; the build also writes `404.html` (noindex) and `llms.txt`. A doc page's search title and description can be set with `<!-- seo-title: ... -->` and `<!-- description: ... -->` under its `# heading` (invisible on GitHub). PNGs under `images/` are served as WebP when `src/images/<name>.webp` exists. Check every page:

```sh
dart run tools/check_seo.dart website/build [--site-url https://lkrjangid1.github.io/native-api-bindgen-docs/]
```

`.github/workflows/website.yml` builds, runs the SEO checks, checks external links and deploys to GitHub Pages.
