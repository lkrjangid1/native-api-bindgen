// Builds the static project website (website/src -> website/build).
//
// No framework, no external requests, no tracking. Numbers on the pages come
// from docs/benchmarks/*.json at build time ({{key}} placeholders), so the
// site never states figures that were not measured.
//
// Usage: dart run tools/build_website.dart [--site-url https://host/base]
//   --site-url (or NAB_SITE_URL) enables absolute canonical/Open Graph URLs
//   and sitemap.xml; without it they are omitted.
import 'dart:convert';
import 'dart:io';

const _pages = [
  'index',
  'getting-started',
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

const _nav = [
  ('getting-started', 'Get started'),
  ('architecture', 'Architecture'),
  ('flutter', 'Flutter'),
  ('react-native', 'React Native'),
  ('android', 'Android'),
  ('ios', 'iOS'),
  ('compatibility', 'Compatibility'),
  ('legal', 'Legal'),
  ('faq', 'FAQ'),
];

/// Budgets checked at build time (bytes).
const _maxHtml = 60 * 1024;
const _maxCss = 16 * 1024;

void main(List<String> args) {
  final root = _repoRoot();
  final siteUrlArg = args.indexOf('--site-url');
  var siteUrl = siteUrlArg >= 0 && siteUrlArg + 1 < args.length
      ? args[siteUrlArg + 1]
      : Platform.environment['NAB_SITE_URL'];
  if (siteUrl != null && siteUrl.endsWith('/')) {
    siteUrl = siteUrl.substring(0, siteUrl.length - 1);
  }
  final src = '$root/website/src';
  final out = Directory('$root/website/build');
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final data = _data(root);
  final problems = <String>[];
  final titles = <String, String>{};
  final descriptions = <String, String>{};
  final css = File('$src/assets/style.css').readAsStringSync();
  if (css.length > _maxCss) problems.add('style.css exceeds $_maxCss bytes');
  File('${out.path}/style.css').writeAsStringSync(css);
  File('$src/assets/icon.svg').copySync('${out.path}/icon.svg');

  for (final slug in _pages) {
    final raw = File('$src/pages/$slug.html').readAsStringSync();
    final meta = _frontMatter(raw, slug);
    final title = meta['title']!;
    final description = meta['description']!;
    if (titles.containsKey(title)) problems.add('duplicate title: $title');
    if (descriptions.containsKey(description)) {
      problems.add('duplicate description on $slug');
    }
    titles[title] = slug;
    descriptions[description] = slug;
    final fullTitle = slug == 'index' ? title : '$title — native-api-bindgen';
    if (fullTitle.length > 60) {
      problems.add(
        '$slug: title longer than 60 characters (${fullTitle.length})',
      );
    }
    if (description.length < 50 || description.length > 160) {
      problems.add(
        '$slug: description should be 50-160 characters (${description.length})',
      );
    }
    var body = raw.substring(raw.indexOf('-->') + 3).trim();
    body = body.replaceAllMapped(RegExp(r'\{\{([a-z0-9_.]+)\}\}'), (m) {
      final v = data[m[1]];
      if (v == null) problems.add('$slug: unknown data key ${m[1]}');
      return v ?? '';
    });
    if (body.contains('<script')) {
      problems.add('$slug: scripts are not allowed');
    }
    final html = _layout(
      slug: slug,
      title: title,
      description: description,
      body: body,
      siteUrl: siteUrl,
    );
    if (html.length > _maxHtml) {
      problems.add('$slug.html exceeds $_maxHtml bytes');
    }
    problems.addAll(_unbalanced(html).map((e) => '$slug: $e'));
    for (final m in RegExp(r'href="([^"#:]+)(#[^"]*)?"').allMatches(html)) {
      final target = m[1]!;
      if (target.endsWith('.css') ||
          target.endsWith('.svg') ||
          target.endsWith('.webmanifest')) {
        continue;
      }
      final page = target == './' ? 'index' : target.replaceAll('.html', '');
      if (!_pages.contains(page)) {
        problems.add('$slug: broken internal link $target');
      }
    }
    File('${out.path}/$slug.html').writeAsStringSync(html);
  }

  File('${out.path}/robots.txt').writeAsStringSync(
    'User-agent: *\nAllow: /\n${siteUrl == null ? '' : 'Sitemap: $siteUrl/sitemap.xml\n'}',
  );
  if (siteUrl != null) {
    final urls = [
      for (final p in _pages)
        '  <url><loc>$siteUrl/${p == 'index' ? '' : '$p.html'}</loc></url>',
    ];
    File('${out.path}/sitemap.xml').writeAsStringSync(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
      '${urls.join('\n')}\n</urlset>\n',
    );
  }
  File('${out.path}/site.webmanifest').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'name': 'native-api-bindgen',
      'short_name': 'bindgen',
      'description': 'Generated Flutter and React Native bindings for public Android and iOS platform APIs.',
      'start_url': './',
      'display': 'standalone',
      'background_color': '#ffffff',
      'theme_color': '#1f4e79',
      'icons': [
        {'src': 'icon.svg', 'sizes': 'any', 'type': 'image/svg+xml'},
      ],
    })}\n',
  );
  File('${out.path}/.nojekyll').writeAsStringSync('');

  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  stdout.writeln(
    'website/build: ${_pages.length} pages${siteUrl == null ? ' (no --site-url: canonical URLs and sitemap omitted)' : ''}',
  );
}

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

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _layout({
  required String slug,
  required String title,
  required String description,
  required String body,
  required String? siteUrl,
}) {
  final href = slug == 'index' ? './' : '$slug.html';
  final pageUrl = siteUrl == null
      ? null
      : '$siteUrl/${slug == 'index' ? '' : '$slug.html'}';
  final fullTitle = slug == 'index' ? title : '$title — native-api-bindgen';
  final jsonLd = slug == 'index'
      ? [
          {
            '@context': 'https://schema.org',
            '@type': 'WebSite',
            'name': 'native-api-bindgen',
            'description': description,
            'url': ?pageUrl,
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
          },
        ]
      : [
          {
            '@context': 'https://schema.org',
            '@type': 'TechArticle',
            'headline': title,
            'description': description,
            'url': ?pageUrl,
            'inLanguage': 'en',
          },
        ];
  final nav = [
    for (final (s, label) in _nav)
      '<a href="$s.html"${s == slug ? ' aria-current="page"' : ''}>$label</a>',
  ].join('\n        ');
  return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_esc(fullTitle)}</title>
  <meta name="description" content="${_esc(description)}">
${pageUrl == null ? '' : '  <link rel="canonical" href="$pageUrl">\n'}  <meta property="og:type" content="${slug == 'index' ? 'website' : 'article'}">
  <meta property="og:title" content="${_esc(fullTitle)}">
  <meta property="og:description" content="${_esc(description)}">
${pageUrl == null ? '' : '  <meta property="og:url" content="$pageUrl">\n'}  <meta property="og:site_name" content="native-api-bindgen">
  <meta name="theme-color" content="#1f4e79">
  <link rel="icon" href="icon.svg" type="image/svg+xml">
  <link rel="manifest" href="site.webmanifest">
  <link rel="stylesheet" href="style.css">
  <script type="application/ld+json">${jsonEncode(jsonLd.length == 1 ? jsonLd.single : jsonLd)}</script>
</head>
<body>
  <a class="skip" href="#content">Skip to content</a>
  <header class="site">
    <div class="wrap">
      <a class="brand" href="./"${href == './' ? ' aria-current="page"' : ''}>native-api-bindgen</a>
      <span class="badge" title="APIs, output and configuration may change">Experimental</span>
      <nav aria-label="Main">
        $nav
      </nav>
    </div>
  </header>
  <main id="content" class="wrap">
$body
  </main>
  <footer class="site">
    <div class="wrap">
      <p>Apache-2.0. Generated bindings are derived from SDKs installed on your machine and stay local by default.</p>
      <p>Independent open-source project, not affiliated with or endorsed by Google, Apple, Meta or the Dart/Flutter teams. Android is a trademark of Google LLC. Apple, iOS, Xcode, Objective-C and Swift are trademarks of Apple Inc. Flutter and Dart are trademarks of Google LLC. React and React Native are trademarks of Meta Platforms, Inc.</p>
    </div>
  </footer>
</body>
</html>
''';
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
  return {
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
