// Builds the static project website (website/src + docs/ -> website/build).
//
// No framework, no external requests, no tracking. Numbers on the pages come
// from docs/benchmarks/*.json at build time ({{key}} placeholders), so the
// site never states figures that were not measured. Every Markdown file in
// docs/ is published as a documentation page (tools/website/docs.dart).
//
// Usage: dart run tools/build_website.dart [--site-url https://host/base]
//        [--repo-url https://github.com/owner/repo]
//   --site-url (or NAB_SITE_URL) enables absolute canonical/Open Graph URLs,
//   sitemap.xml and llms.txt; without them they are omitted.
//   --repo-url (or NAB_REPO_URL) enables the GitHub button and repository
//   links (license, security, contributing, "edit this page"); without it
//   they are omitted rather than pointing at a placeholder.
import 'dart:convert';
import 'dart:io';

import 'website/docs.dart';

const _pages = [
  'index',
  'getting-started',
  'docs',
  'examples',
  'architecture',
  'flutter',
  'react-native',
  'android',
  'ios',
  'versioning',
  'compatibility',
  'legal',
  'faq',
];

/// Eyebrow label shown above each page title.
const _eyebrows = {
  'getting-started': 'Guide',
  'docs': 'Documentation',
  'examples': 'Examples',
  'architecture': 'How it works',
  'flutter': 'Framework',
  'react-native': 'Framework',
  'android': 'Platform',
  'ios': 'Platform',
  'versioning': 'Keeping up',
  'compatibility': 'Tested and measured',
  'legal': 'Source policy',
  'faq': 'FAQ',
};

const _platforms = [
  ('flutter', 'Flutter', 'Dart over package:jni and package:objective_c'),
  ('react-native', 'React Native', 'TypeScript over JSI, New Architecture'),
  ('android', 'Android', 'android.jar, AndroidX, Kotlin'),
  ('ios', 'iOS', 'Objective-C headers and Swift adapters'),
];

const _nav = [
  ('docs', 'Docs'),
  ('examples', 'Examples'),
  ('architecture', 'Architecture'),
  ('compatibility', 'Compatibility'),
  ('faq', 'FAQ'),
];

/// Social preview image (website/src/images), 1200x630.
const _ogImage = 'images/og-image.jpg';

/// Budgets checked at build time (bytes).
const _maxHtml = 80 * 1024;
const _maxCss = 32 * 1024;

String? _repoUrl;

void main(List<String> args) {
  final root = _repoRoot();
  final siteUrlArg = args.indexOf('--site-url');
  var siteUrl = siteUrlArg >= 0 && siteUrlArg + 1 < args.length
      ? args[siteUrlArg + 1]
      : Platform.environment['NAB_SITE_URL'];
  if (siteUrl != null && siteUrl.isEmpty) siteUrl = null;
  if (siteUrl != null && siteUrl.endsWith('/')) {
    siteUrl = siteUrl.substring(0, siteUrl.length - 1);
  }
  final repoArg = args.indexOf('--repo-url');
  var repoUrl = repoArg >= 0 && repoArg + 1 < args.length
      ? args[repoArg + 1]
      : Platform.environment['NAB_REPO_URL'];
  if (repoUrl != null && repoUrl.isEmpty) repoUrl = null;
  if (repoUrl != null && repoUrl.endsWith('/')) {
    repoUrl = repoUrl.substring(0, repoUrl.length - 1);
  }
  _repoUrl = repoUrl;
  final src = '$root/website/src';
  final out = Directory('$root/website/build');
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final data = _data(root);
  final problems = <String>[];
  final titles = <String, String>{};
  final descriptions = <String, String>{};
  final written = <String>[];
  void write(String path, String content) {
    final f = File('${out.path}/$path');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    written.add(path);
  }

  final css = File('$src/assets/style.css').readAsStringSync();
  if (css.length > _maxCss) problems.add('style.css exceeds $_maxCss bytes');
  write('style.css', css);
  write('site.js', File('$src/assets/site.js').readAsStringSync());
  File('$src/assets/icon.svg').copySync('${out.path}/icon.svg');
  // Screenshots and diagrams shared with the README (docs/images).
  Directory('${out.path}/images').createSync();
  for (final f in Directory('$root/docs/images').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.png') && !name.endsWith('.svg')) continue;
    f.copySync('${out.path}/images/$name');
  }
  // Website-only images: WebP variants of docs/images and the social image.
  for (final f in Directory('$src/images').listSync().whereType<File>()) {
    f.copySync('${out.path}/images/${f.uri.pathSegments.last}');
  }

  final docs = DocSet.load('$root/docs', repoUrl, problems);
  for (final a in docs.assets) {
    final to = File('${out.path}/docs/$a')..parent.createSync(recursive: true);
    File('$root/docs/$a').copySync(to.path);
  }

  void checkPage(String path, String html) {
    if (html.length > _maxHtml) problems.add('$path exceeds $_maxHtml bytes');
    problems.addAll(_unbalanced(html).map((e) => '$path: $e'));
  }

  /// Search-result limits and uniqueness, for every page.
  void checkMeta(String path, String fullTitle, String description) {
    if (titles.containsKey(fullTitle)) {
      problems.add('$path: duplicate title (also ${titles[fullTitle]})');
    }
    if (descriptions.containsKey(description)) {
      problems.add(
        '$path: duplicate description (also ${descriptions[description]})',
      );
    }
    titles[fullTitle] = path;
    descriptions[description] = path;
    if (fullTitle.length > 60) {
      problems.add(
        '$path: title longer than 60 characters (${fullTitle.length})',
      );
    }
    if (description.length < 70 || description.length > 160) {
      problems.add(
        '$path: description should be 70-160 characters (${description.length})',
      );
    }
  }

  final modified = _lastModified(root);

  for (final slug in _pages) {
    final raw = File('$src/pages/$slug.html').readAsStringSync();
    final meta = _frontMatter(raw, slug);
    final title = meta['title']!;
    final description = meta['description']!;
    final fullTitle = slug == 'index' ? title : '$title — native-api-bindgen';
    checkMeta('$slug.html', fullTitle, description);
    var body = raw.substring(raw.indexOf('-->') + 3).trim();
    // Repository-only fragments (<!--repo-->...<!--/repo-->, `{{repo}}`).
    body = body.replaceAllMapped(
      RegExp(r'<!--repo-->([\s\S]*?)<!--/repo-->'),
      (m) => repoUrl == null ? '' : m[1]!.replaceAll('{{repo}}', repoUrl),
    );
    body = body.replaceAll('<!--docs-index-->', docs.index());
    body = body.replaceAllMapped(RegExp(r'\{\{([a-z0-9_.]+)\}\}'), (m) {
      final v = data[m[1]];
      if (v == null) problems.add('$slug: unknown data key ${m[1]}');
      return v ?? '';
    });
    if (body.contains('<script')) {
      problems.add('$slug: scripts are not allowed');
    }
    body = body
        .replaceAll('<table>', '<div class="table-wrap"><table>')
        .replaceAll('</table>', '</table></div>');
    final main = slug == 'index' ? body : _pageMain(slug, body);
    final html = _layout(
      path: '$slug.html',
      active: slug,
      fullTitle: fullTitle,
      description: description,
      main: main,
      siteUrl: siteUrl,
      jsonLd: _jsonLd(
        slug,
        title,
        description,
        siteUrl,
        modified['website/src/pages/$slug.html'],
      ),
    );
    checkPage('$slug.html', html);
    write('$slug.html', html);
  }

  for (var i = 0; i < docs.pages.length; i++) {
    final p = docs.pages[i];
    final prev = i > 0 ? docs.pages[i - 1] : null;
    final next = i + 1 < docs.pages.length ? docs.pages[i + 1] : null;
    final fullTitle = _docTitle(p);
    checkMeta(p.out, fullTitle, p.description);
    final html = _layout(
      path: p.out,
      active: 'docs',
      fullTitle: fullTitle,
      description: p.description,
      main: _docMain(p, docs, prev, next),
      siteUrl: siteUrl,
      jsonLd: [
        _article(
          p.title,
          p.description,
          siteUrl == null ? null : '$siteUrl/${p.out}',
          siteUrl,
          modified['docs/${p.source}'],
        ),
        if (siteUrl != null)
          _breadcrumbs(siteUrl, [('Docs', 'docs.html'), (p.title, p.out)]),
      ],
    );
    checkPage(p.out, html);
    write(p.out, html);
  }

  write(
    'robots.txt',
    'User-agent: *\nAllow: /\n${siteUrl == null ? '' : 'Sitemap: $siteUrl/sitemap.xml\n'}',
  );
  if (siteUrl != null) {
    String url(String loc, String? lastmod) =>
        '  <url><loc>$siteUrl/$loc</loc>${lastmod == null ? '' : '<lastmod>$lastmod</lastmod>'}</url>';
    final urls = [
      for (final p in _pages)
        url(
          p == 'index' ? '' : '$p.html',
          modified['website/src/pages/$p.html'],
        ),
      for (final p in docs.pages) url(p.out, modified['docs/${p.source}']),
    ];
    write(
      'sitemap.xml',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
          '${urls.join('\n')}\n</urlset>\n',
    );
  }
  write(
    'site.webmanifest',
    '${const JsonEncoder.withIndent('  ').convert({
      'name': 'native-api-bindgen',
      'short_name': 'bindgen',
      'description': 'Generated Flutter and React Native bindings for public Android and iOS platform APIs.',
      'start_url': './',
      'display': 'standalone',
      'background_color': '#ffffff',
      'theme_color': '#2563eb',
      'icons': [
        {'src': 'icon.svg', 'sizes': 'any', 'type': 'image/svg+xml'},
      ],
    })}\n',
  );
  write('.nojekyll', '');
  // GitHub Pages serves 404.html for unknown paths. Links are root-relative
  // because the page is served at any depth.
  final notFound = _layout(
    path: '404.html',
    active: '',
    fullTitle: 'Page not found — native-api-bindgen',
    description:
        'This page does not exist. Browse the native-api-bindgen documentation or start from the home page.',
    main:
        '''
<section class="page-head">
  <div class="wrap">
    <p class="eyebrow">404</p>
    <h1>Page not found</h1>
    <p class="lead">The page you asked for does not exist or has moved.</p>
  </div>
</section>
<div class="wrap page-body prose">
<p><a href="${siteUrl ?? ''}/">Home</a> · <a href="${siteUrl ?? ''}/docs.html">Documentation</a> · <a href="${siteUrl ?? ''}/getting-started.html">Get started</a></p>
</div>''',
    siteUrl: siteUrl,
    jsonLd: const <Object>[],
    noindex: true,
    rootBase: siteUrl == null ? null : '$siteUrl/',
  );
  write('404.html', notFound);
  // llms.txt (https://llmstxt.org): a Markdown map of the site for AI tools.
  if (siteUrl != null) {
    final b = StringBuffer()
      ..writeln('# native-api-bindgen')
      ..writeln()
      ..writeln(
        '> Generates typed Flutter (Dart) and React Native (TypeScript) bindings for public Android and iOS platform APIs from the SDKs installed on the developer\'s machine. Apache-2.0, beta (0.1.0-beta.1) on pub.dev, npm and Homebrew.',
      )
      ..writeln()
      ..writeln('## Site')
      ..writeln();
    for (final p in _pages) {
      final meta = _frontMatter(
        File('$src/pages/$p.html').readAsStringSync(),
        p,
      );
      b.writeln(
        '- [${meta['title']}]($siteUrl/${p == 'index' ? '' : '$p.html'}): ${meta['description']}',
      );
    }
    String? group;
    for (final p in docs.pages) {
      if (p.group != group) {
        group = p.group;
        b
          ..writeln()
          ..writeln('## Docs: $group')
          ..writeln();
      }
      b.writeln('- [${p.title}]($siteUrl/${p.out}): ${p.description}');
    }
    write('llms.txt', b.toString());
  }

  // Every relative href/src in every page must point at a built file.
  for (final path in written.where((p) => p.endsWith('.html'))) {
    final html = File('${out.path}/$path').readAsStringSync();
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/') + 1)
        : '';
    for (final m in RegExp(r'(?:href|src)="([^"]*)"').allMatches(html)) {
      var target = m[1]!;
      if (target.isEmpty ||
          target.startsWith('#') ||
          RegExp(r'^[a-z]+:').hasMatch(target)) {
        continue;
      }
      target = target.split('#').first.split('?').first;
      if (target.isEmpty) continue;
      var resolved = _normalizePath('$dir$target');
      if (target.endsWith('/') || resolved.isEmpty) {
        resolved = resolved.isEmpty ? 'index.html' : '$resolved/index.html';
      }
      if (!File('${out.path}/$resolved').existsSync()) {
        problems.add('$path: broken link ${m[1]}');
      }
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  stdout.writeln(
    'website/build: ${_pages.length} pages + ${docs.pages.length} docs pages${siteUrl == null ? ' (no --site-url: canonical URLs and sitemap omitted)' : ''}',
  );
}

String _normalizePath(String path) {
  final out = <String>[];
  for (final s in path.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(s);
    }
  }
  return out.join('/');
}

/// Splits the leading `<h1>` and `.lead` paragraph of a page into a header band.
String _pageMain(String slug, String body) {
  final head = RegExp(
    r'^<h1>([\s\S]*?)</h1>\s*(<p class="lead">[\s\S]*?</p>)?',
  ).firstMatch(body);
  final h1 = head?[1] ?? slug;
  final lead = head?[2] ?? '';
  final rest = head == null ? body : body.substring(head.end).trim();
  return '''
<section class="page-head">
  <div class="wrap">
    <p class="eyebrow">${_eyebrows[slug] ?? ''}</p>
    <h1>$h1</h1>
    $lead
  </div>
</section>
<div class="wrap page-body prose">
$rest
</div>''';
}

String _docMain(DocPage p, DocSet docs, DocPage? prev, DocPage? next) {
  final toc = p.toc.isEmpty
      ? ''
      : '''
  <nav class="toc" aria-label="On this page">
    <p>On this page</p>
    <ul>
${p.toc.map((t) => '      <li><a href="#${t.$1}">${_esc(t.$2)}</a></li>').join('\n')}
    </ul>
  </nav>''';
  final edit = _repoUrl == null
      ? '<span>Source: <code>docs/${p.source}</code></span>'
      : '<a href="$_repoUrl/blob/main/docs/${p.source}">Edit this page on GitHub</a>';
  String pager(DocPage? d, String label, String cls) => d == null
      ? '<span></span>'
      : '<a class="$cls" href="${relUrl(p.out, d.out)}"><small>$label</small>${_esc(d.title)}</a>';
  return '''
<div class="wrap docs-shell">
  <article class="doc prose">
    <nav class="crumbs" aria-label="Breadcrumb"><a href="${relUrl(p.out, 'docs.html')}">Docs</a><span>/</span>${p.group}</nav>
    <h1>${_esc(p.title)}</h1>
${p.html}
    <div class="doc-foot">$edit</div>
    <nav class="pager" aria-label="Previous and next">${pager(prev, 'Previous', 'prev')}${pager(next, 'Next', 'next')}</nav>
  </article>
  <aside class="docs-side" aria-label="Documentation">
${docs.sidebar(p.out)}  </aside>
$toc
</div>''';
}

/// `<title>` for a docs page: the full form when it fits a search result
/// (60 characters), otherwise shorter forms.
String _docTitle(DocPage p) {
  final t = p.seoTitle ?? p.title;
  for (final candidate in [
    '$t · native-api-bindgen docs',
    '$t · native-api-bindgen',
    t,
  ]) {
    if (candidate.length <= 60) return candidate;
  }
  return clip(t, 60);
}

Map<String, Object?> _publisher(String? siteUrl) => {
  '@type': 'Organization',
  'name': 'native-api-bindgen',
  if (siteUrl != null) 'url': '$siteUrl/',
  if (siteUrl != null)
    'logo': {'@type': 'ImageObject', 'url': '$siteUrl/icon.svg'},
};

Map<String, Object?> _article(
  String headline,
  String description,
  String? pageUrl,
  String? siteUrl,
  String? modified,
) => {
  '@context': 'https://schema.org',
  '@type': 'TechArticle',
  'headline': headline,
  'description': description,
  'url': ?pageUrl,
  'mainEntityOfPage': ?pageUrl,
  if (siteUrl != null) 'image': '$siteUrl/$_ogImage',
  'dateModified': ?modified,
  'inLanguage': 'en',
  'author': _publisher(siteUrl),
  'publisher': _publisher(siteUrl),
  if (siteUrl != null)
    'isPartOf': {
      '@type': 'WebSite',
      'name': 'native-api-bindgen',
      'url': '$siteUrl/',
    },
};

Map<String, Object?> _breadcrumbs(
  String siteUrl,
  List<(String, String)> trail,
) => {
  '@context': 'https://schema.org',
  '@type': 'BreadcrumbList',
  'itemListElement': [
    for (final (i, (name, path)) in [('Home', ''), ...trail].indexed)
      {
        '@type': 'ListItem',
        'position': i + 1,
        'name': name,
        'item': '$siteUrl/$path',
      },
  ],
};

Object _jsonLd(
  String slug,
  String title,
  String description,
  String? siteUrl,
  String? modified,
) {
  final pageUrl = siteUrl == null
      ? null
      : '$siteUrl/${slug == 'index' ? '' : '$slug.html'}';
  if (slug != 'index') {
    return [
      _article(title, description, pageUrl, siteUrl, modified),
      if (siteUrl != null) _breadcrumbs(siteUrl, [(title, '$slug.html')]),
    ];
  }
  return [
    {
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      'name': 'native-api-bindgen',
      'description': description,
      'url': ?pageUrl,
      'inLanguage': 'en',
      'publisher': _publisher(siteUrl),
    },
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareSourceCode',
      'name': 'native-api-bindgen',
      'description': description,
      'programmingLanguage': [
        'Dart',
        'TypeScript',
        'C++',
        'Objective-C++',
        'Java',
        'Swift',
      ],
      'license': 'https://www.apache.org/licenses/LICENSE-2.0',
      'runtimePlatform': ['Flutter', 'React Native'],
      'version': '0.1.0-beta.1',
      'url': ?pageUrl,
      if (_repoUrl != null) 'codeRepository': _repoUrl,
    },
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      'name': 'native-api-bindgen',
      'description': description,
      'applicationCategory': 'DeveloperApplication',
      'operatingSystem': 'macOS, Linux, Windows',
      'softwareVersion': '0.1.0-beta.1',
      'license': 'https://www.apache.org/licenses/LICENSE-2.0',
      'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
      'url': ?pageUrl,
      if (siteUrl != null) 'image': '$siteUrl/$_ogImage',
      'downloadUrl': 'https://pub.dev/packages/native_api_bindgen',
    },
  ];
}

const _githubIcon =
    '<svg viewBox="0 0 16 16" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>';

const _themeIcons =
    '<svg class="i-moon" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z"/></svg>'
    '<svg class="i-sun" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><circle cx="12" cy="12" r="4.5" fill="currentColor"/><g stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></g></svg>';

String _layout({
  required String path,
  required String active,
  required String fullTitle,
  required String description,
  required String main,
  required String? siteUrl,
  required Object jsonLd,
  bool noindex = false,
  String? rootBase,
}) {
  final base = rootBase ?? '../' * (path.split('/').length - 1);
  final pageUrl = siteUrl == null || noindex
      ? null
      : '$siteUrl/${path == 'index.html' ? '' : path}';
  final image = siteUrl == null ? null : '$siteUrl/$_ogImage';
  const imageAlt =
      'native-api-bindgen: Android and iOS SDK APIs turned into typed Dart and TypeScript bindings';
  final social = [
    if (noindex) '<meta name="robots" content="noindex">',
    if (pageUrl != null) '<link rel="canonical" href="$pageUrl">',
    '<meta property="og:type" content="${path == 'index.html' ? 'website' : 'article'}">',
    '<meta property="og:site_name" content="native-api-bindgen">',
    '<meta property="og:locale" content="en_US">',
    '<meta property="og:title" content="${_esc(fullTitle)}">',
    '<meta property="og:description" content="${_esc(description)}">',
    if (pageUrl != null) '<meta property="og:url" content="$pageUrl">',
    if (image != null) ...[
      '<meta property="og:image" content="$image">',
      '<meta property="og:image:width" content="1200">',
      '<meta property="og:image:height" content="630">',
      '<meta property="og:image:alt" content="$imageAlt">',
    ],
    '<meta name="twitter:card" content="${image == null ? 'summary' : 'summary_large_image'}">',
    '<meta name="twitter:title" content="${_esc(fullTitle)}">',
    '<meta name="twitter:description" content="${_esc(description)}">',
    if (image != null) '<meta name="twitter:image" content="$image">',
    if (image != null) '<meta name="twitter:image:alt" content="$imageAlt">',
  ].map((l) => '  $l\n').join();
  String link(String slug) => '$base$slug.html';
  String cur(String slug) => slug == active ? ' aria-current="page"' : '';
  final platformActive = _platforms.any((p) => p.$1 == active);
  final platforms = [
    for (final (slug, label, desc) in _platforms)
      '<a href="${link(slug)}"${cur(slug)}><strong>$label</strong><span>$desc</span></a>',
  ].join('\n            ');
  final nav = [
    for (final (slug, label) in _nav)
      '<a class="nav-link" href="${link(slug)}"${cur(slug)}>$label</a>',
  ].join('\n          ');
  final repo = _repoUrl;
  final isHome = path == 'index.html';
  return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_esc(fullTitle)}</title>
  <meta name="description" content="${_esc(description)}">
  <meta name="google-site-verification" content="Wh3NtRP5KxDYNAeBecAL9ccoGKLN7H6ll8bsdeZUZE4" />
$social  <meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#0a0f1a" media="(prefers-color-scheme: dark)">
  <meta name="color-scheme" content="light dark">
  <script>try{var t=localStorage.getItem('nab-theme');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}</script>
  <link rel="icon" href="${base}icon.svg" type="image/svg+xml">
  <link rel="manifest" href="${base}site.webmanifest">
  <link rel="stylesheet" href="${base}style.css">
${jsonLd is List && jsonLd.isEmpty ? '' : '  <script type="application/ld+json">${jsonEncode(jsonLd)}</script>\n'}</head>
<body${isHome ? ' class="home"' : ''}>
  <a class="skip" href="#content">Skip to content</a>
  <header class="site-header">
    <div class="wrap bar">
      <a class="brand" href="$base./"${isHome ? ' aria-current="page"' : ''}><img src="${base}icon.svg" alt="" width="30" height="30"><span>native-api-bindgen</span></a>
      <span class="badge" title="0.1.0-beta.1: APIs, output and configuration may change">Beta</span>
      <input type="checkbox" id="nav-toggle" class="nav-toggle" aria-label="Open menu">
      <label for="nav-toggle" class="nav-burger" aria-hidden="true"><span></span><span></span><span></span></label>
      <div class="nav-wrap">
        <nav class="nav" aria-label="Main">
          <div class="dropdown">
            <button type="button" class="nav-link"${platformActive ? ' data-active="true"' : ''} aria-haspopup="true">Platforms<svg viewBox="0 0 12 12" width="10" height="10" aria-hidden="true"><path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg></button>
            <div class="dropdown-panel">
            $platforms
            </div>
          </div>
          $nav
        </nav>
        <div class="bar-actions">
${repo == null ? '' : '          <a class="icon-btn" href="$repo" aria-label="GitHub repository">$_githubIcon</a>\n'}          <button type="button" class="icon-btn theme-toggle" aria-label="Switch between light and dark theme">$_themeIcons</button>
          <a class="btn btn-primary btn-sm" href="${link('getting-started')}">Get started</a>
        </div>
      </div>
    </div>
  </header>
  <main id="content">
${_webp(main, base)}
  </main>
${_footer(base)}
  <script src="${base}site.js" defer></script>
</body>
</html>
''';
}

String _footer(String base) {
  final repo = _repoUrl;
  String col(String title, List<String> links) =>
      '      <div><p class="foot-title">$title</p>\n${links.map((l) => '        $l').join('\n')}\n      </div>';
  return '''
  <footer class="site-footer">
    <div class="wrap foot-grid">
      <div class="foot-brand">
        <a class="brand" href="$base./"><img src="${base}icon.svg" alt="" width="26" height="26"><span>native-api-bindgen</span></a>
        <p>Typed Flutter and React Native bindings for public Android and iOS APIs, generated from the SDKs on your machine.</p>
      </div>
${col('Product', ['<a href="${base}getting-started.html">Get started</a>', '<a href="${base}docs.html">Documentation</a>', '<a href="${base}examples.html">Examples</a>', '<a href="${base}compatibility.html">Compatibility</a>'])}
${col('Platforms', [for (final (s, l, _) in _platforms) '<a href="$base$s.html">$l</a>'])}
${col('Project', [if (repo != null) '<a href="$repo">GitHub</a>', if (repo != null) '<a href="$repo/blob/main/CONTRIBUTING.md">Contributing</a>', if (repo != null) '<a href="$repo/blob/main/SECURITY.md">Security</a>', repo == null ? '<a href="${base}legal.html">License (Apache-2.0)</a>' : '<a href="$repo/blob/main/LICENSE">License (Apache-2.0)</a>', '<a href="${base}legal.html">Legal &amp; source policy</a>', '<a href="${base}faq.html">FAQ</a>'])}
    </div>
    <div class="wrap foot-legal">
      <p>Apache-2.0. Generated bindings are derived from SDKs installed on your machine and stay local by default.</p>
      <p>Native API Bindgen is an independent open-source project. It is not affiliated with or endorsed by Google, Apple, Meta, or the Dart/Flutter project. Platform SDKs, documentation, trademarks, and other third-party materials remain the property of their respective owners and are subject to their applicable licenses and terms.</p>
      <p>Android is a trademark of Google LLC. Apple, iOS, Xcode, Objective-C and Swift are trademarks of Apple Inc. Flutter and Dart are trademarks of Google LLC. React and React Native are trademarks of Meta Platforms, Inc.</p>
    </div>
  </footer>''';
}

/// Serves the WebP variant of a PNG under images/ when one is built, with
/// the PNG as the fallback.
String _webp(String html, String base) => html.replaceAllMapped(
  RegExp(r'<img ([^>]*?)src="((?:\.\./)*images/([\w-]+))\.png"([^>]*)>'),
  (m) {
    final webp = File('${_repoRoot()}/website/src/images/${m[3]}.webp');
    if (!webp.existsSync()) return m[0]!;
    return '<picture><source srcset="${m[2]}.webp" type="image/webp"><img ${m[1]}src="${m[2]}.png"${m[4]}></picture>';
  },
);

/// Last commit date (YYYY-MM-DD) per repository-relative file, for
/// sitemap.xml and dateModified. Empty when git history is unavailable.
Map<String, String> _lastModified(String root) {
  final r = Process.runSync('git', [
    '-C',
    root,
    'log',
    '--format=@%cs',
    '--name-only',
    '--',
    'website/src/pages',
    'docs',
  ]);
  final out = <String, String>{};
  if (r.exitCode != 0) return out;
  String? date;
  for (final line in (r.stdout as String).split('\n')) {
    if (line.startsWith('@')) {
      date = line.substring(1);
    } else if (line.isNotEmpty && date != null) {
      out.putIfAbsent(line, () => date!);
    }
  }
  return out;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Reports unbalanced tags (void elements excluded).
List<String> _unbalanced(String html) {
  const voids = {'meta', 'link', 'br', 'img', 'hr', 'input', 'source'};
  final stack = <String>[];
  final out = <String>[];
  final noComments = html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final noRaw = noComments.replaceAll(
    RegExp(r'<(script|pre)\b[^>]*>.*?</\1>', dotAll: true),
    '',
  );
  for (final m in RegExp(
    r'<(/?)([a-zA-Z][a-zA-Z0-9]*)\b[^>]*?(/?)>',
  ).allMatches(noRaw)) {
    final name = m[2]!.toLowerCase();
    if (name == 'html' && m[1] == '' && stack.isEmpty) {
      stack.add(name);
      continue;
    }
    if (voids.contains(name) || m[3] == '/') continue;
    if (m[1] == '') {
      stack.add(name);
    } else if (stack.isNotEmpty && stack.last == name) {
      stack.removeLast();
    } else {
      out.add(
        'unexpected </$name> (open: ${stack.isEmpty ? '-' : stack.last})',
      );
      return out;
    }
  }
  if (stack.isNotEmpty) out.add('unclosed <${stack.join('>, <')}>');
  return out;
}

String _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/website/src/pages/index.html').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('repository root not found');
    }
    dir = dir.parent;
  }
  return dir.path;
}

Map<String, String> _frontMatter(String raw, String slug) {
  final start = raw.indexOf('<!--');
  final end = raw.indexOf('-->');
  if (start != 0 || end < 0) {
    throw FormatException('$slug: missing front matter');
  }
  final meta = <String, String>{};
  for (final line in raw.substring(4, end).split('\n')) {
    final i = line.indexOf(':');
    if (i > 0) meta[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  for (final k in ['title', 'description']) {
    if ((meta[k] ?? '').isEmpty) throw FormatException('$slug: missing $k');
  }
  return meta;
}

String _int(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _fixed(num n, int digits) => n.toStringAsFixed(digits);

Map<String, String> _data(String root) {
  Map<String, Object?> j(String f) =>
      jsonDecode(File('$root/docs/benchmarks/$f').readAsStringSync())
          as Map<String, Object?>;
  num apk(Map<String, Object?> m, String k) =>
      (m[k]! as Map)['apk_bytes'] as num;
  final size = j('size-2026-10-05-android36.json');
  final rnSize = j('size-2026-10-05-rn-android36.json');
  Map<String, Object?> med(String f) =>
      j(f)['median_of_runs']! as Map<String, Object?>;
  final fa = med('perf-2026-10-05-flutter-android.json');
  final fi = med('perf-2026-10-05-flutter-ios.json');
  final ra = med('perf-2026-10-05-rn-android.json');
  final ri = med('perf-2026-10-05-rn-ios.json');
  num n(Map<String, Object?> m, String k) => m[k]! as num;
  final covA = j('coverage-2026-10-05-android36.json');
  final covI = j('coverage-2026-10-05-ios-foundation-uikit.json');
  String cov(Map<String, Object?> c, String section, String k) =>
      _int((c[section]! as Map)[k] as num);
  String pct(Map<String, Object?> c, String k) => _fixed(
    100 *
        ((c['generated']! as Map)[k] as num) /
        ((c['discovered']! as Map)[k] as num),
    1,
  );
  final wp7 = j('size-startup-2026-10-05-wp7.json');
  final iosSize = wp7['ios_release_device_arm64']! as Map<String, Object?>;
  num app(String k) => (iosSize[k]! as Map)['runner_app_bytes'] as num;
  final bytes = j('bytes-2026-10-05.json');
  num b(String section, String k) => (bytes[section]! as Map)[k] as num;
  return {
    'coverage.android.methods_generated': cov(covA, 'generated', 'methods'),
    'coverage.android.methods_discovered': cov(covA, 'discovered', 'methods'),
    'coverage.android.methods_pct': pct(covA, 'methods'),
    'coverage.android.classes_generated': cov(covA, 'generated', 'classes'),
    'coverage.android.classes_discovered': cov(covA, 'discovered', 'classes'),
    'coverage.ios.methods_generated': cov(covI, 'generated', 'methods'),
    'coverage.ios.methods_discovered': cov(covI, 'discovered', 'methods'),
    'coverage.ios.methods_pct': pct(covI, 'methods'),
    'coverage.ios.classes_generated': cov(covI, 'generated', 'classes'),
    'coverage.ios.classes_discovered': cov(covI, 'discovered', 'classes'),
    'size.ios.baseline_app': _int(app('baseline')),
    'size.ios.one_api_full_app': _int(app('one-api-full')),
    'size.ios.one_api_delta': _int(app('one-api-full') - app('baseline')),
    'bytes.flutter_android.jni_1mb_ms': _fixed(
      b('flutter_android_profile_emulator', 'jni_bytes_roundtrip_1mb_ms'),
      2,
    ),
    'bytes.flutter_android.channel_1mb_ms': _fixed(
      b(
        'flutter_android_profile_emulator',
        'methodchannel_bytes_roundtrip_1mb_ms',
      ),
      2,
    ),
    'size.flutter.baseline_apk': _int(apk(size, 'baseline')),
    'size.flutter.one_api_slice_apk': _int(apk(size, 'one-api-slice')),
    'size.flutter.one_api_fullsdk_apk': _int(apk(size, 'one-api-fullsdk')),
    'size.flutter.one_api_delta': _int(
      apk(size, 'one-api-slice') - apk(size, 'baseline'),
    ),
    'size.rn.baseline_apk': _int(apk(rnSize, 'rn-baseline')),
    'size.rn.one_api_slice_apk': _int(apk(rnSize, 'rn-one-api-slice')),
    'size.rn.one_api_fullsdk_apk': _int(apk(rnSize, 'rn-one-api-fullsdk')),
    'perf.flutter_android.jni_call_us': _fixed(
      n(fa, 'jni_instance_call_int_ns') / 1000,
      2,
    ),
    'perf.flutter_android.methodchannel_us': _fixed(
      n(fa, 'methodchannel_bundle_size_us'),
      0,
    ),
    'perf.flutter_ios.msgsend_ns': _fixed(
      n(fi, 'msgsend_instance_getter_int_ns'),
      0,
    ),
    'perf.flutter_ios.methodchannel_us': _fixed(
      n(fi, 'methodchannel_view_tag_us'),
      1,
    ),
    'perf.rn_android.jsi_jni_us': _fixed(
      n(ra, 'jsi_jni_instance_call_int_ns') / 1000,
      2,
    ),
    'perf.rn_ios.jsi_objc_us': _fixed(
      n(ri, 'jsi_objc_getter_int_ns') / 1000,
      2,
    ),
    'perf.rn_ios.uikit_main_us': _fixed(
      n(ri, 'jsi_objc_uikit_getter_main_thread_ns') / 1000,
      1,
    ),
  };
}
