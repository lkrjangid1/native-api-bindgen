// Checks every page of the built website for search-engine basics. Runs on
// website/build after tools/build_website.dart; offline.
//
// Usage: dart run tools/check_seo.dart [website/build] [--site-url URL]
//   With --site-url (or NAB_SITE_URL), canonical/Open Graph URLs, sitemap.xml
//   and llms.txt are checked too.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final urlArg = args.indexOf('--site-url');
  var siteUrl = urlArg >= 0 && urlArg + 1 < args.length
      ? args[urlArg + 1]
      : Platform.environment['NAB_SITE_URL'];
  if (siteUrl != null && siteUrl.isEmpty) siteUrl = null;
  if (siteUrl != null && siteUrl.endsWith('/')) {
    siteUrl = siteUrl.substring(0, siteUrl.length - 1);
  }
  final positional = [
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') && (i == 0 || args[i - 1] != '--site-url'))
        args[i],
  ];
  final root = positional.isEmpty ? 'website/build' : positional.first;

  final problems = <String>[];
  final titles = <String, String>{};
  final descriptions = <String, String>{};
  final indexable = <String>{};
  final pages =
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.html'))
          .map((f) => f.path.substring(root.length + 1))
          .toList()
        ..sort();

  for (final path in pages) {
    final html = File('$root/$path').readAsStringSync();
    void fail(String message) => problems.add('$path: $message');
    final head = html.split('</head>').first;
    String? meta(String key) => RegExp(
      '<meta (?:name|property)="${RegExp.escape(key)}" content="([^"]*)"',
    ).firstMatch(head)?[1];

    if (!RegExp(r'<html lang="[a-z]{2}').hasMatch(html)) fail('no html lang');
    if (meta('viewport') == null) fail('no viewport meta');
    final noindex = (meta('robots') ?? '').contains('noindex');
    if (path == '404.html' && !noindex) fail('404 page must be noindex');
    if (!noindex) indexable.add(path);

    final title = RegExp(r'<title>([^<]*)</title>').firstMatch(head)?[1];
    if (title == null || title.trim().isEmpty) {
      fail('missing <title>');
    } else {
      if (title.length > 60) fail('title is ${title.length} chars (max 60)');
      if (titles[title] case final other?) fail('title duplicates $other');
      titles[title] = path;
    }
    final description = meta('description');
    if (description == null) {
      fail('missing meta description');
    } else {
      if (description.length < 70 || description.length > 160) {
        fail('description is ${description.length} chars (70-160)');
      }
      if (!noindex) {
        if (descriptions[description] case final other?) {
          fail('description duplicates $other');
        }
        descriptions[description] = path;
      }
    }

    // Open Graph / Twitter.
    for (final key in [
      'og:type',
      'og:title',
      'og:description',
      'og:site_name',
      'twitter:card',
    ]) {
      if (meta(key) == null) fail('missing $key');
    }
    final canonical = RegExp(
      r'<link rel="canonical" href="([^"]*)"',
    ).allMatches(head).toList();
    if (siteUrl != null) {
      for (final key in ['og:image', 'og:image:alt', 'twitter:image']) {
        if (meta(key) == null) fail('missing $key');
      }
      if (!noindex) {
        final expected = '$siteUrl/${path == 'index.html' ? '' : path}';
        if (canonical.length != 1 || canonical.single[1] != expected) {
          fail('canonical should be $expected');
        }
        if (meta('og:url') != expected) fail('og:url should be $expected');
      }
    }
    if (canonical.length > 1) fail('more than one canonical');

    // Structured data must parse.
    for (final m in RegExp(
      r'<script type="application/ld\+json">([\s\S]*?)</script>',
    ).allMatches(html)) {
      try {
        final data = jsonDecode(m[1]!);
        for (final item in data is List ? data : [data]) {
          if (item is! Map ||
              item['@context'] != 'https://schema.org' ||
              item['@type'] == null) {
            fail('JSON-LD item without schema.org @context/@type');
          }
        }
      } on FormatException catch (e) {
        fail('invalid JSON-LD: ${e.message}');
      }
    }
    if (!noindex && !head.contains('application/ld+json')) {
      fail('no structured data');
    }

    // Content structure.
    final body = html
        .substring(html.indexOf('<body'))
        .replaceAll(RegExp(r'<(pre|script)\b[\s\S]*?</\1>'), '');
    final h1s = RegExp(r'<h1[\s>]').allMatches(body).length;
    if (h1s != 1) fail('$h1s <h1> elements (expected 1)');
    var previous = 1;
    for (final m in RegExp(
      r'<h([1-6])[\s>]',
    ).allMatches(body.substring(body.indexOf('<main')))) {
      final level = int.parse(m[1]!);
      if (level > previous + 1) {
        fail('heading jumps from h$previous to h$level');
        break;
      }
      previous = level;
    }
    for (final img in RegExp(r'<img\b[^>]*>').allMatches(body)) {
      final tag = img[0]!;
      final src = RegExp(r'src="([^"]*)"').firstMatch(tag)?[1];
      if (!tag.contains(' alt="')) fail('<img src="$src"> without alt');
      if (!tag.contains(' width="') || !tag.contains(' height="')) {
        fail('<img src="$src"> without width/height (layout shift)');
      }
    }
    for (final a in RegExp(r'<a\b[^>]*>([\s\S]*?)</a>').allMatches(body)) {
      final text = a[1]!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      final label = RegExp(r'aria-label="([^"]+)"').firstMatch(a[0]!);
      final hasImgAlt = RegExp(r'<img [^>]*alt="[^"]+"').hasMatch(a[1]!);
      if (text.isEmpty &&
          label == null &&
          !hasImgAlt &&
          !a[1]!.contains('<span')) {
        fail(
          'link without text: ${a[0]!.substring(0, a[0]!.indexOf('>') + 1)}',
        );
      }
    }
    final words = body
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => RegExp(r'[A-Za-z]').hasMatch(w))
        .length;
    if (!noindex && words < 250) fail('thin content: $words words');
  }

  // robots.txt, sitemap.xml and llms.txt.
  final robots = File('$root/robots.txt');
  if (!robots.existsSync()) {
    problems.add('robots.txt missing');
  } else if (RegExp(
    r'^Disallow: /\s*$',
    multiLine: true,
  ).hasMatch(robots.readAsStringSync())) {
    problems.add('robots.txt blocks the whole site');
  }
  if (siteUrl != null) {
    if (!robots.readAsStringSync().contains('Sitemap: $siteUrl/sitemap.xml')) {
      problems.add('robots.txt does not reference the sitemap');
    }
    final sitemap = File('$root/sitemap.xml');
    if (!sitemap.existsSync()) {
      problems.add('sitemap.xml missing');
    } else {
      final locs = {
        for (final m in RegExp(
          r'<loc>([^<]*)</loc>',
        ).allMatches(sitemap.readAsStringSync()))
          m[1]!,
      };
      for (final path in indexable) {
        final url = '$siteUrl/${path == 'index.html' ? '' : path}';
        if (!locs.remove(url)) problems.add('sitemap.xml lacks $url');
      }
      for (final url in locs) {
        problems.add('sitemap.xml lists $url, which is not an indexable page');
      }
    }
    if (!File('$root/llms.txt').existsSync()) problems.add('llms.txt missing');
  }

  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  stdout.writeln(
    'SEO checks passed for ${pages.length} pages (${indexable.length} indexable)${siteUrl == null ? '; no --site-url: URLs, sitemap and llms.txt not checked' : ''}',
  );
}
