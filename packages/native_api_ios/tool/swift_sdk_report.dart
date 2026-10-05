import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ios/native_api_ios.dart';

/// Swift Layer 2 discovery report for SDK modules:
/// `dart run tool/swift_sdk_report.dart TipKit Charts`.
void main(List<String> modules) {
  final sdk = XcodeLocator().locate()!;
  final tc = SwiftToolchain(sdk, minIos: '18.0');
  final tmp = Directory.systemTemp.createTempSync('nab_swift_report');
  try {
    for (final m in modules) {
      final sw = Stopwatch()..start();
      final graph = SwiftModuleGraph.read(tc.extractSymbolGraph(m, tmp.path));
      final out = SwiftAdapterGenerator(
        graph,
        sdkVersion: sdk.version,
      ).generate();
      final members = [for (final t in out.module.types) ...t.methods];
      final cov = CoverageReport.of(out.module);
      stdout.writeln(
        '$m: ${sw.elapsedMilliseconds} ms, types ${out.module.types.length} '
        '(adapted ${out.module.types.where((t) => t.isGeneratable).length}), '
        'members ${members.length} (adapted ${members.where((x) => x.isGeneratable).length}), '
        'skipped by reason ${cov.excludedByReason}',
      );
    }
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
