// Turns docs/**/*.md into website pages (website/build/docs/...).
//
// Markdown is rendered with package:markdown (GitHub flavour). Links between
// Markdown files become links between pages; links to other repository files
// point at the repository when a URL is known and are unwrapped otherwise, so
// the site never contains a dead link.
import 'dart:io';

import 'package:markdown/markdown.dart' as md;

/// Sidebar order. Files not listed here are appended under "More", so every
/// document in docs/ is published.
const docGroups = [
  (
    'Guides',
    [
      'getting-started/README.md',
      'flutter/README.md',
      'react-native/README.md',
      'android/README.md',
      'ios/README.md',
      'native-ui.md',
      'troubleshooting/README.md',
    ],
  ),
  (
    'Architecture',
    [
      'architecture/overview.md',
      'architecture/ir.md',
      'architecture/type-mapping.md',
      'architecture/lifecycle.md',
      'architecture/rn-jsi.md',
      'technical-design.md',
    ],
  ),
  (
    'Reference',
    [
      'error-codes.md',
      'versioning.md',
      'compatibility/matrix.md',
      'benchmarks/README.md',
      'benchmarks/performance.md',
      'benchmarks/size.md',
      'sources/official-sources.md',
    ],
  ),
  ('Project', ['roadmap.md', 'test-strategy.md', 'implementation-plan.md']),
  (
    'Legal',
    [
      'legal/license-policy.md',
      'legal/source-provenance.md',
      'legal/android.md',
      'legal/apple.md',
      'legal/flutter.md',
      'legal/react-native.md',
    ],
  ),
];

class DocPage {
  DocPage(this.source, this.group);

  /// Path relative to docs/, e.g. `architecture/ir.md`.
  final String source;
  final String group;
  late String title;

  /// Shorter `<title>` when [title] does not fit a search result.
  String? seoTitle;
  late String description;
  late String html;
  final toc = <(String, String)>[];

  /// Output path relative to the site root, e.g. `docs/architecture/ir.html`.
  String get out => docOutPath(source);
}

String docOutPath(String source) {
  final noExt = source.substring(0, source.length - 3);
  return noExt == 'README' || noExt.endsWith('/README')
      ? 'docs/${noExt.substring(0, noExt.length - 6)}index.html'
      : 'docs/$noExt.html';
}

/// Relative URL from the page at [from] to the file at [to] (both relative to
/// the site root).
String relUrl(String from, String to) {
  final a = from.split('/')..removeLast();
  final b = to.split('/');
  var i = 0;
  while (i < a.length && i < b.length - 1 && a[i] == b[i]) {
    i++;
  }
  return '${'../' * (a.length - i)}${b.sublist(i).join('/')}';
}

String _normalize(String path) {
  final out = <String>[];
  for (final s in path.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..' && out.isNotEmpty && out.last != '..') {
      out.removeLast();
    } else {
      out.add(s);
    }
  }
  return out.join('/');
}

String plainText(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String clip(String s, int max) {
  if (s.length <= max) return s;
  final cut = s.substring(0, max - 1);
  final space = cut.lastIndexOf(' ');
  return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).replaceAll(RegExp(r'[\s,;:.—-]+$'), '')}…';
}

class DocSet {
  DocSet._(this.pages, this.assets);

  final List<DocPage> pages;

  /// docs/-relative files referenced by pages (copied next to them).
  final Set<String> assets;

  static DocSet load(String docsDir, String? repoUrl, List<String> problems) {
    final all = <String>[
      for (final f in Directory(docsDir).listSync(recursive: true))
        if (f is File && f.path.endsWith('.md'))
          f.path.substring(docsDir.length + 1),
    ]..sort();
    final pages = <DocPage>[];
    for (final (group, files) in docGroups) {
      for (final f in files) {
        if (!all.contains(f)) {
          problems.add('docs: $f is listed in docGroups but does not exist');
          continue;
        }
        pages.add(DocPage(f, group));
      }
    }
    final listed = {for (final p in pages) p.source};
    pages.addAll([
      for (final f in all)
        if (!listed.contains(f)) DocPage(f, 'More'),
    ]);
    final known = {for (final p in pages) p.source};
    final assets = <String>{};
    for (final page in pages) {
      final raw = File('$docsDir/${page.source}').readAsStringSync();
      // Optional SEO overrides, invisible on GitHub:
      // <!-- seo-title: ... --> and <!-- description: ... -->.
      String? override(String key) => RegExp(
        '<!--\\s*$key:\\s*([\\s\\S]*?)\\s*-->',
      ).firstMatch(raw)?[1]?.replaceAll(RegExp(r'\s+'), ' ');
      page.seoTitle = override('seo-title');
      var html = md
          .markdownToHtml(raw, extensionSet: md.ExtensionSet.gitHubWeb)
          .replaceAll(
            RegExp(r'<!--\s*(?:seo-title|description):[\s\S]*?-->\n?'),
            '',
          );
      // Title from the first <h1>, without internal TRD section references.
      final h1 = RegExp(r'<h1[^>]*>([\s\S]*?)</h1>').firstMatch(html);
      final rawTitle = h1 == null ? page.source : h1[1]!;
      page.title = plainText(
        rawTitle.replaceAll(RegExp(r'\s*\((?:TRD|stage)[^)]*\)'), ''),
      );
      if (h1 != null) html = html.replaceFirst(h1[0]!, '');
      // Description: the opening paragraphs (not disclaimers in blockquotes),
      // joined until they say enough for a search snippet.
      final prose = html.replaceAll(
        RegExp(r'<blockquote>[\s\S]*?</blockquote>'),
        '',
      );
      final intro = StringBuffer();
      for (final m in RegExp(r'<p>([\s\S]*?)</p>').allMatches(prose)) {
        if (intro.length >= 110) break;
        if (intro.isNotEmpty) intro.write(' ');
        intro.write(plainText(m[1]!));
      }
      var description = override('description') ?? clip(intro.toString(), 155);
      if (description.length < 70) {
        description =
            '${page.title}: native-api-bindgen documentation for generated Flutter and React Native bindings.';
        description = clip(description, 155);
      }
      page.description = description;

      // Links.
      final dir = page.source.contains('/')
          ? page.source.substring(0, page.source.lastIndexOf('/'))
          : '';
      String? resolve(String href) {
        if (href.startsWith('#') || RegExp(r'^[a-z]+:').hasMatch(href)) {
          return href;
        }
        final hash = href.indexOf('#');
        final frag = hash >= 0 ? href.substring(hash) : '';
        final path = Uri.decodeFull(hash >= 0 ? href.substring(0, hash) : href);
        final target = _normalize(dir.isEmpty ? path : '$dir/$path');
        if (target.startsWith('../')) {
          final repoPath = _normalize('docs/$target');
          return repoUrl == null ? null : '$repoUrl/blob/main/$repoPath$frag';
        }
        var mdTarget = target;
        if (!mdTarget.endsWith('.md') &&
            File('$docsDir/$target/README.md').existsSync()) {
          mdTarget = target.isEmpty ? 'README.md' : '$target/README.md';
        }
        if (mdTarget.endsWith('.md')) {
          if (!known.contains(mdTarget)) {
            problems.add('docs/${page.source}: broken link $href');
            return null;
          }
          return '${relUrl(page.out, docOutPath(mdTarget))}$frag';
        }
        if (File('$docsDir/$target').existsSync()) {
          if (target.startsWith('images/')) {
            return relUrl(page.out, target);
          }
          assets.add(target);
          return '${relUrl(page.out, 'docs/$target')}$frag';
        }
        problems.add('docs/${page.source}: broken link $href');
        return null;
      }

      html = html.replaceAllMapped(RegExp(r'<a href="([^"]*)">([\s\S]*?)</a>'), (
        m,
      ) {
        final to = resolve(m[1]!.replaceAll('&amp;', '&'));
        if (to == null) return m[2]!;
        final external = RegExp(r'^https?:').hasMatch(to);
        return '<a href="$to"${external ? ' rel="noopener"' : ''}>${m[2]}</a>';
      });
      html = html.replaceAllMapped(RegExp(r'<img src="([^"]*)"'), (m) {
        final to = resolve(m[1]!);
        return '<img loading="lazy" src="${to ?? m[1]}"';
      });
      // Section anchors and table of contents.
      html = html.replaceAllMapped(
        RegExp(r'<h([23]) id="([^"]+)">([\s\S]*?)</h\1>'),
        (m) {
          if (m[1] == '2') page.toc.add((m[2]!, plainText(m[3]!)));
          return '<h${m[1]} id="${m[2]}">${m[3]}<a class="anchor" href="#${m[2]}" aria-label="Link to this section">#</a></h${m[1]}>';
        },
      );
      html = html
          .replaceAll('<table>', '<div class="table-wrap"><table>')
          .replaceAll('</table>', '</table></div>');
      page.html = html.trim();
    }
    final titles = <String>{};
    for (final p in pages) {
      if (!titles.add(p.title)) {
        problems.add('docs: duplicate title ${p.title}');
      }
    }
    return DocSet._(pages, assets);
  }

  /// Sidebar for the page at [current] (site-root-relative output path).
  String sidebar(String current) {
    final b = StringBuffer();
    b.write(
      '<a class="side-home${current == 'docs.html' ? ' active' : ''}" href="${relUrl(current, 'docs.html')}">Overview</a>\n',
    );
    String? group;
    for (final p in pages) {
      if (p.group != group) {
        if (group != null) b.write('</ul>\n');
        group = p.group;
        b.write('<p class="side-group">${p.group}</p>\n<ul>\n');
      }
      final active = p.out == current;
      b.write(
        '<li><a href="${relUrl(current, p.out)}"${active ? ' aria-current="page"' : ''}>${_esc(p.title)}</a></li>\n',
      );
    }
    if (group != null) b.write('</ul>\n');
    return b.toString();
  }

  /// Grouped cards for the documentation hub (docs.html).
  String index() {
    final b = StringBuffer();
    String? group;
    for (final p in pages) {
      if (p.group != group) {
        if (group != null) b.write('</div>\n');
        group = p.group;
        b.write(
          '<h2 id="${p.group.toLowerCase()}">${p.group}</h2>\n<div class="doc-cards">\n',
        );
      }
      b.write(
        '<a class="doc-card" href="${p.out}"><strong>${_esc(p.title)}</strong><span>${_esc(clip(p.description, 120))}</span></a>\n',
      );
    }
    if (group != null) b.write('</div>\n');
    return b.toString();
  }
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
