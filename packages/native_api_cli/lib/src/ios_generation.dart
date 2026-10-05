import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:native_api_react_native_ios/native_api_react_native_ios.dart';
import 'package:path/path.dart' as p;

import 'context.dart';

/// iOS generation flows shared by `generate` and `update`.
final class IosGeneration {
  /// Creates the flows for [ctx].
  IosGeneration(this.ctx);

  /// CLI context.
  final CliContext ctx;

  Logger get _log => ctx.logger;

  /// Flutter on iOS (+ Swift adapters): writes bindings and state.
  int generateIos({
    List<String> frameworks = const [],
    List<String> classes = const [],
    List<String> entries = const [],
    int? depth,
    String? output,
  }) {
    final sdk = ctx.appleSdk();
    final request = ctx.iosRequest(
      frameworks: frameworks,
      classes: classes,
      entries: entries,
      depth: depth,
    );
    final temp = Directory.systemTemp.createTempSync('nab_swift_');
    late final ApiModule module;
    late final List<ApiModule> swiftModules;
    try {
      final adapters = ctx.swiftAdapters(sdk, temp);
      swiftModules = adapters.swift;
      module = ctx.extractIos(
        sdk,
        request,
        headerFiles: adapters.headers,
        extraClasses: adapters.classes,
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
    for (final s in swiftModules) {
      ctx.writeState(
        s,
        const [],
        const {},
        subdir:
            'ios-swift/${s.types.isEmpty ? 'empty' : s.types.first.namespace}',
      );
      final cov = CoverageReport.of(s);
      _log.info(
        'Swift ${s.types.isEmpty ? '' : s.types.first.namespace}: ${s.types.where((t) => t.isGeneratable).length} of ${s.types.length} types adapted; skipped members by reason: ${cov.excludedByReason}',
        event: 'swift-adapters',
      );
    }
    final out = ctx.generateFlutterIos(module);
    final outDir = p.normalize(
      p.join(ctx.projectDir, output ?? ctx.config.outputDir),
    );
    final written = writeGeneration(
      OutputGuard(outDir),
      out,
      manifestName: '.native_api_bindgen_manifest_ios',
    );
    ctx.writeState(out.module, out.bindings, const {}, subdir: 'ios');
    // Snapshot for `diff ios` (like ir-android-<api>.json).
    OutputGuard(
      ctx.stateDir,
    ).writeStreaming('ir-ios-${sdk.version}.json', module.writeCanonicalJson);
    final cov = CoverageReport.of(out.module);
    final summary = StringBuffer()
      ..writeln(
        'Generated Flutter bindings for iOS (${sdk.name} ${sdk.version})',
      )
      ..writeln(
        '  output: ${p.relative(outDir, from: ctx.projectDir)} (${written.length} files)',
      )
      ..writeln(
        '  types: ${out.module.types.where((t) => t.isGeneratable).length} generated of ${out.module.types.length} parsed',
      )
      ..writeln('  members bound: ${out.bindings.length}');
    if (cov.excludedByReason.isNotEmpty) {
      summary.writeln('  skipped (by reason):');
      cov.excludedByReason.forEach((k, v) => summary.writeln('    $k: $v'));
    }
    _log.result(summary.toString().trimRight(), {
      'sdk': sdk.toJson(),
      'output': p.relative(outDir, from: ctx.projectDir),
      'files': written,
      'bindings': out.bindings.length,
      'coverage': cov.toJson(),
    });
    return ExitCodes.ok;
  }

  /// React Native on iOS: writes the library half and state.
  int generateReactNativeIos({
    List<String> frameworks = const [],
    List<String> classes = const [],
    List<String> entries = const [],
    int? depth,
    String? output,
    required TypescriptMode mode,
  }) {
    final sdk = ctx.appleSdk();
    final module = ctx.extractIos(
      sdk,
      ctx.iosRequest(
        frameworks: frameworks,
        classes: classes,
        entries: entries,
        depth: depth,
      ),
    );
    final out = RnObjCEmitter(
      module,
      options: RnObjCOptions(
        minIos: ApiVersion.parse(ctx.config.ios.minVersion),
        mode: mode,
        linkFrameworks: {
          ...ctx.config.ios.frameworks,
          ...ctx.config.ios.include,
          ...frameworks,
        }.toList()..sort(),
      ),
    ).emit();
    final outDir = p.normalize(
      p.join(ctx.projectDir, output ?? ctx.config.reactNativeDir),
    );
    final written = writeGeneration(
      OutputGuard(outDir),
      out,
      manifestName: '.native_api_bindgen_manifest_ios',
    );
    ctx.writeState(out.module, out.bindings, const {}, subdir: 'ios-rn');
    final cov = CoverageReport.of(out.module);
    final summary = StringBuffer()
      ..writeln(
        'Generated React Native bindings for iOS (${sdk.name} ${sdk.version}, ${mode.key})',
      )
      ..writeln(
        '  output: ${p.relative(outDir, from: ctx.projectDir)} (${written.length} files; import from \'<library>/ios\')',
      )
      ..writeln('  members bound: ${out.bindings.length}');
    if (cov.excludedByReason.isNotEmpty) {
      summary.writeln('  skipped (by reason):');
      cov.excludedByReason.forEach((k, v) => summary.writeln('    $k: $v'));
    }
    _log.result(summary.toString().trimRight(), {
      'sdk': sdk.toJson(),
      'output': p.relative(outDir, from: ctx.projectDir),
      'files': written,
      'bindings': out.bindings.length,
      'coverage': cov.toJson(),
    });
    return ExitCodes.ok;
  }
}
