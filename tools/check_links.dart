// Validates external links in Markdown documentation. Network access is
// explicit (this script only runs when invoked; generation never needs it).
//
// Usage: dart run tools/check_links.dart [files or directories...]
import 'dart:async';
import 'dart:io';

final _link = RegExp(r'https?://[^\s)<>`"\]]+');

Future<void> main(List<String> args) async {
  final roots = args.isEmpty ? ['README.md', 'docs'] : args;
  final links = <String, Set<String>>{};
  for (final r in roots) {
    final entity = FileSystemEntity.typeSync(r);
    final files = entity == FileSystemEntityType.directory
        ? Directory(r)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.md'))
        : [File(r)];
    for (final f in files) {
      for (final m in _link.allMatches(f.readAsStringSync())) {
        final url = m[0]!.replaceAll(RegExp(r'[.,;:]+$'), '');
        if (url.contains('<') || url.contains('example.com')) continue;
        (links[url] ??= {}).add(f.path);
      }
    }
  }
  final client = HttpClient()
    ..userAgent = 'native-api-bindgen-link-check'
    ..connectionTimeout = const Duration(seconds: 15);
  var failures = 0;
  for (final url in links.keys.toList()..sort()) {
    int? status;
    String? error;
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      req.followRedirects = true;
      final res = await req.close().timeout(const Duration(seconds: 20));
      status = res.statusCode;
      await res.drain<void>();
    } on Object catch (e) {
      error = '$e';
    }
    final ok = status != null && status < 400;
    if (!ok) failures++;
    stdout.writeln('${ok ? 'OK  ' : 'FAIL'} ${status ?? error} $url');
  }
  client.close();
  stdout.writeln('${links.length} links checked, $failures failed');
  exitCode = failures == 0 ? 0 : 1;
}
