import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_android/native_api_flutter_android.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/native_api_ios.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:native_api_react_native_android/native_api_react_native_android.dart';
import 'package:native_api_react_native_ios/native_api_react_native_ios.dart';
import 'package:path/path.dart' as p;

import 'context.dart';
import 'toolchain.dart';

/// Base command with access to the shared context.
abstract class BindgenCommand extends Command<int> {
  /// The context, created by the runner before `run`.
  late CliContext ctx;

  Logger get _log => ctx.logger;

  List<String> _multi(String name) => argResults!.wasParsed(name)
      ? argResults![name] as List<String>
      : const [];

  String? _opt(String name) => argResults![name] as String?;

  int? _intOpt(String name) {
    final v = _opt(name);
    if (v == null) return null;
    final n = int.tryParse(v);
    if (n == null) throw UsageException('--$name must be an integer', usage);
    return n;
  }

  void _selectionOptions() {
    argParser
      ..addMultiOption(
        'package',
        help: 'Generate a whole Java package (repeatable).',
      )
      ..addMultiOption('class', help: 'Generate a single class (repeatable).')
      ..addMultiOption(
        'entry',
        help: 'Dependency-aware root: includes referenced types up to --depth.',
      )
      ..addOption(
        'depth',
        help: 'Dependency depth from --entry roots (default from config: 1).',
      )
      ..addOption(
        'platform',
        help:
            'Android platform, e.g. 36 or 36.1 (default: config / highest stable).',
      )
      ..addMultiOption(
        'jar',
        help:
            'Android library artifact (.jar, .aar or class directory) whose classes can be selected (repeatable).',
      );
  }

  ExtractionRequest _request() {
    if (argResults!.options.contains('jar')) {
      ctx.extraLibraries = _multi('jar');
    }
    return ctx.request(
      packages: _multi('package'),
      classes: _multi('class'),
      entries: _multi('entry'),
      depth: _intOpt('depth'),
    );
  }

  int _notImplemented(String what) {
    final d = Diagnostic(
      DiagnosticCode.notImplemented,
      '$what is not implemented in ${ProjectInfo.name} ${ProjectInfo.generatorVersion}. '
      'Tracked in docs/roadmap.md.',
      severity: Severity.error,
    );
    _log.diagnostic(d);
    _log.result('', {'status': 'not-implemented', 'diagnostic': d.toJson()});
    return ExitCodes.notImplemented;
  }
}

/// `init`.
final class InitCommand extends BindgenCommand {
  /// Creates the command.
  InitCommand() {
    argParser.addFlag(
      'force',
      help: 'Overwrite an existing configuration file.',
    );
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Write a default ${ProjectInfo.configFileName}.';

  @override
  Future<int> run() async {
    final f = File(ctx.configPath);
    if (f.existsSync() && !(argResults!['force'] as bool)) {
      _log.error(
        '${p.relative(f.path, from: ctx.projectDir)} already exists (use --force to overwrite)',
      );
      return ExitCodes.failure;
    }
    f.writeAsStringSync(BindgenConfig.defaultYaml());
    _log.result(
      'Wrote ${p.relative(f.path, from: ctx.projectDir)}.\n'
      'Add ${ProjectInfo.stateDirName}/ and the output directory to .gitignore: generated bindings are '
      'derived from your locally installed SDK (distribution.generatedArtifacts: local-only).',
      {'written': p.relative(f.path, from: ctx.projectDir)},
    );
    return ExitCodes.ok;
  }
}

/// `detect` and `doctor`.
final class DetectCommand extends BindgenCommand {
  /// Creates `detect` (or `doctor` when [doctor] is true).
  DetectCommand({this.doctor = false});

  /// Whether this is `doctor` (adds checks and recommendations).
  final bool doctor;

  @override
  String get name => doctor ? 'doctor' : 'detect';

  @override
  String get description => doctor
      ? 'Check SDKs, toolchains and configuration, and report problems.'
      : 'Detect installed platform SDKs and toolchains.';

  @override
  Future<int> run() async {
    final tc = detectToolchain(ctx);
    final lines = <String>[];
    var problems = 0;
    void line(String label, String value, {bool ok = true, String? fix}) {
      lines.add('${label.padRight(22)}${ok ? '' : '✗ '}$value');
      if (!ok) {
        problems++;
        if (doctor && fix != null) lines.add('${''.padRight(24)}→ $fix');
      }
    }

    final sdk = tc.androidSdk;
    if (sdk == null) {
      line(
        'Android SDK:',
        'not found',
        ok: false,
        fix:
            'Install Android Studio or the command-line tools; set ANDROID_HOME.',
      );
    } else {
      line('Android SDK:', 'detected (${sdk.source})');
      final stable = sdk.platforms
          .where((x) => x.hasAndroidJar && x.isStable)
          .map((x) => '${x.apiLevel}')
          .toList();
      line(
        'Platform APIs:',
        stable.isEmpty ? 'none' : stable.join(', '),
        ok: stable.isNotEmpty,
        fix: 'sdkmanager "platforms;android-36"',
      );
      final selected = sdk.select(ctx.config.android.platform);
      if (selected != null) {
        line(
          'Selected platform:',
          '${selected.dirName} (API ${selected.apiLevel}, revision ${selected.revision ?? '?'})',
        );
        line(
          '  api-versions.xml:',
          selected.hasApiVersions ? 'present' : 'missing',
          ok: selected.hasApiVersions,
          fix: 'Reinstall the platform package.',
        );
        line(
          '  annotations.zip:',
          selected.hasAnnotations ? 'present' : 'missing',
          ok: selected.hasAnnotations,
          fix: 'Reinstall the platform package.',
        );
      } else {
        line(
          'Selected platform:',
          '"${ctx.config.android.platform}" not installed',
          ok: false,
        );
      }
      line(
        'Build tools:',
        sdk.buildTools.isEmpty ? 'not found' : sdk.buildTools.last,
        ok: sdk.buildTools.isNotEmpty,
        fix: 'sdkmanager "build-tools;36.0.0"',
      );
      line(
        'NDK:',
        sdk.ndks.isEmpty
            ? 'not installed (not required for JNI bindings)'
            : sdk.ndks.last,
      );
      line(
        'SDK manager:',
        sdk.hasSdkManager ? 'detected' : 'not found (optional)',
      );
    }
    line(
      'JDK:',
      tc.jdk?.version ?? 'not found',
      ok: tc.jdk != null,
      fix: 'Install a JDK 17+ and set JAVA_HOME.',
    );
    line('Dart:', tc.dartVersion);
    line(
      'Flutter:',
      tc.flutterVersion ?? 'not found',
      ok: tc.flutterVersion != null || !doctor,
      fix: 'Install Flutter to build apps that use the bindings.',
    );
    line(
      'JNI generator:',
      'built-in (Dart extension types over package:jni ^1.0)',
    );
    line(
      'JNI runtime:',
      tc.jniResolved ?? 'package:jni not in this project\'s pubspec.lock',
      ok: tc.jniResolved != null || !doctor,
      fix: 'flutter pub add jni jni_flutter',
    );
    if (Platform.isMacOS) {
      line('Xcode:', tc.xcodeVersion ?? 'not found');
      line('iOS SDK:', tc.iosSdkVersion ?? 'not found');
      line(
        'iOS generation:',
        'Flutter (Dart over package:objective_c), React Native (JSI + Objective-C++)',
      );
      if (doctor) {
        final apple = XcodeLocator().locate(sdkName: ctx.config.ios.sdkName);
        line(
          'libclang:',
          apple != null && File(apple.libclangPath).existsSync()
              ? 'Xcode toolchain'
              : 'not found',
          ok: apple != null && File(apple.libclangPath).existsSync(),
          fix: 'xcode-select -s /Applications/Xcode.app',
        );
      }
    }
    line(
      'Config:',
      File(ctx.configPath).existsSync()
          ? p.relative(ctx.configPath, from: ctx.projectDir)
          : 'defaults (run init)',
    );
    if (doctor) {
      final report = LicenseAuditor().audit(
        ctx.projectDir,
        dependencies: false,
      );
      line(
        'License status:',
        '${report.status.label} (files only; run audit-license for dependencies)',
        ok: report.status != AuditStatus.block,
        fix: 'native-api-bindgen audit-license',
      );
    }
    _log.result(lines.join('\n'), {...tc.toJson(), 'problems': problems});
    return doctor && problems > 0 ? ExitCodes.failure : ExitCodes.ok;
  }
}

/// `inspect <android|ios|symbol>`.
final class InspectCommand extends BindgenCommand {
  /// Creates the command.
  InspectCommand() {
    argParser.addOption(
      'platform',
      help: 'Android platform (default: config).',
    );
  }

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Show the platform SDK summary (android|ios) or a symbol\'s IR as JSON.';

  @override
  String get invocation =>
      '${runner!.executableName} inspect <android|ios|SYMBOL>';

  @override
  Future<int> run() async {
    final args = argResults!.rest;
    if (args.length != 1) {
      throw UsageException('Expected exactly one argument', usage);
    }
    final what = args.single;
    if (what == 'ios') return _inspectIos();
    final platform = ctx.androidPlatform(ctx.androidSdk(), _opt('platform'));
    final ex = ctx.openExtractor(platform);
    if (what == 'android') {
      final pkgs = <String, int>{};
      for (final c in ex.classes.classNames) {
        final i = c.lastIndexOf('.');
        final pkg = i < 0 ? '' : c.substring(0, i);
        pkgs[pkg] = (pkgs[pkg] ?? 0) + 1;
      }
      final sorted = pkgs.keys.toList()..sort();
      _log.result(
        'Android API ${platform.apiLevel} (${platform.dirName}, revision ${platform.revision ?? '?'})\n'
        'android.jar classes: ${ex.classes.classNames.length}\n'
        'packages: ${pkgs.length}\n'
        'api-versions.xml classes: ${ex.apiVersions?.classes.length ?? 'n/a'}',
        {
          'platform': platform.toJson(),
          'classes': ex.classes.classNames.length,
          'packages': {for (final k in sorted) k: pkgs[k]},
          'apiVersionsClasses': ex.apiVersions?.classes.length,
        },
      );
      return ExitCodes.ok;
    }
    final node = _findSymbol(ex, what);
    _log.result(canonicalJson(node.toJson()).trimRight(), node.toJson());
    return ExitCodes.ok;
  }
}

extension on InspectCommand {
  int _inspectIos() {
    final sdk = ctx.appleSdk();
    final fws = <String>[];
    final dir = Directory(p.join(sdk.path, 'System', 'Library', 'Frameworks'));
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        final name = p.basename(e.path);
        if (name.endsWith('.framework') &&
            Directory(p.join(e.path, 'Headers')).existsSync()) {
          fws.add(name.substring(0, name.length - '.framework'.length));
        }
      }
    }
    fws.sort();
    ctx.logger.result(
      '${sdk.name} SDK ${sdk.version} (${sdk.xcodeVersion})\n'
      'frameworks with public headers: ${fws.length}',
      {...sdk.toJson(), 'frameworks': fws},
    );
    return ExitCodes.ok;
  }
}

ApiNode _findSymbol(AndroidApiExtractor ex, String symbol) {
  final hash = symbol.indexOf('#');
  final typeName = hash < 0 ? symbol : symbol.substring(0, hash);
  final binary = ex.resolveClassName(typeName);
  final type = binary == null ? null : ex.loadType(binary);
  if (type == null) {
    throw CliFailure(
      Diagnostic(
        DiagnosticCode.sdkNotFound,
        'Type $typeName not found or not public',
        severity: Severity.error,
        symbolId: symbol,
      ),
    );
  }
  if (hash < 0) return type;
  final member = symbol.substring(hash + 1);
  final full = '${type.id}#$member';
  final matches = [
    for (final n in [...type.methods, ...type.fields])
      if (n.id == full ||
          n.name == member ||
          ((member == SymbolIds.constructorName || member == type.name) &&
              n is ApiMethod &&
              n.isConstructor))
        n,
  ];
  if (matches.length == 1) return matches.single;
  if (matches.isEmpty) {
    throw CliFailure(
      Diagnostic(
        DiagnosticCode.sdkNotFound,
        'No member $member in ${type.id}',
        severity: Severity.error,
        symbolId: symbol,
      ),
    );
  }
  throw CliFailure(
    Diagnostic(
      DiagnosticCode.sdkNotFound,
      'Ambiguous: ${matches.map((m) => m.id).join(', ')}',
      severity: Severity.error,
      symbolId: symbol,
    ),
    ExitCodes.usage,
  );
}

/// `generate <android|flutter|ios|react-native|all>`.
final class GenerateCommand extends BindgenCommand {
  /// Creates the command.
  GenerateCommand() {
    _selectionOptions();
    argParser
      ..addOption(
        'output',
        help: 'Output directory (default: config output.dir).',
      )
      ..addOption(
        'mode',
        allowed: ['strict-native', 'ergonomic-dart'],
        help: 'Dart type-mapping mode (default: config).',
      )
      ..addOption(
        'ts-mode',
        allowed: ['strict-typescript', 'ergonomic-typescript'],
        help: 'TypeScript mode for react-native (default: config).',
      )
      ..addMultiOption(
        'framework',
        help: 'ios: generate a whole Apple framework, e.g. UIKit (repeatable).',
      );
  }

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generate IR (android) or bindings: flutter (Android), ios (Flutter on iOS), '
      'react-native (configured platforms), react-native-android, react-native-ios.';

  @override
  String get invocation =>
      '${runner!.executableName} generate <android|flutter|ios|react-native|react-native-android|react-native-ios|all> [options]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final target = rest.isEmpty ? 'all' : rest.first;
    ctx.extraLibraries = _multi('jar');
    switch (target) {
      case 'ios':
        return _ios();
      case 'react-native-android':
        return _reactNative();
      case 'react-native-ios':
        return _reactNativeIos();
      case 'react-native':
        return _reactNativeConfigured();
      case 'android':
        final platform = ctx.androidPlatform(
          ctx.androidSdk(),
          _opt('platform'),
        );
        final r = ctx.openExtractor(platform).extract(_request());
        final path = OutputGuard(ctx.stateDir).writeString(
          'ir-android-${platform.apiLevel}.json',
          r.module.toCanonicalJson(),
        );
        _log.result(
          'Wrote IR for ${r.module.types.length} types to ${p.relative(path, from: ctx.projectDir)}',
          {
            'types': r.module.types.length,
            'ir': p.relative(path, from: ctx.projectDir),
          },
        );
        return ExitCodes.ok;
      case 'flutter' || 'all':
        var code = ExitCodes.ok;
        if (target == 'flutter' || ctx.config.flutter) code = _flutter();
        if (target == 'all' && ctx.config.reactNative && code == ExitCodes.ok) {
          code = _reactNativeConfigured();
        }
        final ios = ctx.config.ios;
        if (target == 'all' &&
            code == ExitCodes.ok &&
            ctx.config.flutter &&
            [...ios.include, ...ios.classes, ...ios.entries].isNotEmpty &&
            _iosAvailable()) {
          code = _ios();
        }
        return code;
      default:
        throw UsageException('Unknown target "$target"', usage);
    }
  }

  int _ios() {
    final sdk = ctx.appleSdk();
    final module = ctx.extractIos(
      sdk,
      ctx.iosRequest(
        frameworks: _multi('framework'),
        classes: _multi('class'),
        entries: _multi('entry'),
        depth: _intOpt('depth'),
      ),
    );
    final out = ctx.generateFlutterIos(module);
    final outDir = p.normalize(
      p.join(ctx.projectDir, _opt('output') ?? ctx.config.outputDir),
    );
    final written = writeGeneration(
      OutputGuard(outDir),
      out,
      manifestName: '.native_api_bindgen_manifest_ios',
    );
    ctx.writeState(out.module, out.bindings, const {}, subdir: 'ios');
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

  bool get _iosSelected {
    final ios = ctx.config.ios;
    return [...ios.include, ...ios.classes, ...ios.entries].isNotEmpty;
  }

  bool get _androidSelected {
    final a = ctx.config.android;
    return [
      ...a.include,
      ...a.classes,
      ...a.entries,
      ..._multi('package'),
      ..._multi('class'),
      ..._multi('entry'),
    ].isNotEmpty;
  }

  /// Whether configured iOS generation can run here; logs why not.
  bool _iosAvailable() {
    if (Platform.isMacOS) return true;
    _log.warn(
      'platform.ios is configured but iOS bindings can only be generated on macOS with Xcode; skipped',
    );
    return false;
  }

  /// React Native for every platform with a selection (Android first).
  int _reactNativeConfigured() {
    var code = ExitCodes.ok;
    if (_androidSelected || !_iosSelected) code = _reactNative();
    if (code == ExitCodes.ok && _iosSelected && _iosAvailable()) {
      code = _reactNativeIos();
    }
    return code;
  }

  TypescriptMode get _tsMode => switch (_opt('ts-mode')) {
    'ergonomic-typescript' => TypescriptMode.ergonomic,
    'strict-typescript' => TypescriptMode.strict,
    _ => ctx.config.typescriptMode,
  };

  int _reactNativeIos() {
    final sdk = ctx.appleSdk();
    final module = ctx.extractIos(
      sdk,
      ctx.iosRequest(
        frameworks: _multi('framework'),
        classes: _multi('class'),
        entries: _multi('entry'),
        depth: _intOpt('depth'),
      ),
    );
    final mode = _tsMode;
    final out = RnObjCEmitter(
      module,
      options: RnObjCOptions(
        minIos: ApiVersion.parse(ctx.config.ios.minVersion),
        mode: mode,
        linkFrameworks: {
          ...ctx.config.ios.frameworks,
          ...ctx.config.ios.include,
          ..._multi('framework'),
        }.toList()..sort(),
      ),
    ).emit();
    final outDir = p.normalize(
      p.join(ctx.projectDir, _opt('output') ?? ctx.config.reactNativeDir),
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

  int _reactNative() {
    final platform = ctx.androidPlatform(ctx.androidSdk(), _opt('platform'));
    final mode = _tsMode;
    final extraction = ctx.openExtractor(platform).extract(_request());
    for (final d in extraction.diagnostics) {
      _log.diagnostic(d);
    }
    final out = RnJsiEmitter(
      extraction.module,
      options: RnJsiOptions(
        minApi: ApiVersion(ctx.config.android.minApi),
        mode: mode,
        callbacks: ctx.config.callbacks,
      ),
    ).emit();
    final outDir = p.normalize(
      p.join(ctx.projectDir, _opt('output') ?? ctx.config.reactNativeDir),
    );
    final written = writeGeneration(OutputGuard(outDir), out);
    ctx.writeState(out.module, out.bindings, extraction.closureDepth);
    final cov = CoverageReport.of(out.module);
    _log.result(
      'Generated React Native bindings (Android API ${platform.apiLevel}, ${mode.key})\n'
      '  output: ${p.relative(outDir, from: ctx.projectDir)} (${written.length} files)\n'
      '  members bound: ${out.bindings.length}',
      {
        'platform': '${platform.apiLevel}',
        'output': p.relative(outDir, from: ctx.projectDir),
        'files': written,
        'bindings': out.bindings.length,
        'coverage': cov.toJson(),
      },
    );
    return ExitCodes.ok;
  }

  int _flutter() {
    final platform = ctx.androidPlatform(ctx.androidSdk(), _opt('platform'));
    final mode = switch (_opt('mode')) {
      'ergonomic-dart' => GenerationMode.ergonomicDart,
      'strict-native' => GenerationMode.strictNative,
      _ => null,
    };
    final res = ctx.generateFlutter(platform, _request(), mode: mode);
    final outDir = p.normalize(
      p.join(ctx.projectDir, _opt('output') ?? ctx.config.outputDir),
    );
    final written = writeGeneration(OutputGuard(outDir), res.output);
    ctx.writeState(
      res.output.module,
      res.output.bindings,
      res.extraction.closureDepth,
    );
    final cov = CoverageReport.of(res.output.module);
    final summary = StringBuffer()
      ..writeln(
        'Generated Flutter bindings for Android API ${platform.apiLevel}',
      )
      ..writeln(
        '  output: ${p.relative(outDir, from: ctx.projectDir)} (${written.length} files)',
      )
      ..writeln(
        '  types: ${res.output.module.types.where((t) => t.isGeneratable).length} generated of ${res.output.module.types.length} parsed',
      )
      ..writeln('  members bound: ${res.output.bindings.length}');
    if (cov.excludedByReason.isNotEmpty) {
      summary.writeln('  skipped (by reason):');
      cov.excludedByReason.forEach((k, v) => summary.writeln('    $k: $v'));
    }
    _log.result(summary.toString().trimRight(), {
      'platform': '${platform.apiLevel}',
      'output': p.relative(outDir, from: ctx.projectDir),
      'files': written,
      'bindings': res.output.bindings.length,
      'coverage': cov.toJson(),
    });
    return ExitCodes.ok;
  }
}

/// `update`.
final class UpdateCommand extends BindgenCommand {
  /// Creates the command.
  UpdateCommand() {
    argParser.addFlag(
      'all',
      help: 'Also snapshot IR for every installed stable platform (for diff).',
    );
  }

  @override
  String get name => 'update';

  @override
  String get description =>
      'Detect SDKs, regenerate bindings, and report coverage and license status.';

  @override
  Future<int> run() async {
    final sdk = ctx.androidSdk();
    final platform = ctx.androidPlatform(sdk);
    final b = StringBuffer()
      ..writeln(
        'Detected Android API ${platform.apiLevel} (${platform.dirName})',
      );
    final tc = detectToolchain(ctx);
    if (tc.iosSdkVersion != null) {
      b.writeln(
        'Detected iOS SDK ${tc.iosSdkVersion} (generation not yet implemented)',
      );
    }
    final previous = ctx.readState()?.module;
    b
      ..writeln()
      ..writeln('Generating Flutter (Android)...');
    final res = ctx.generateFlutter(platform, ctx.request());
    final outDir = p.join(ctx.projectDir, ctx.config.outputDir);
    writeGeneration(OutputGuard(outDir), res.output);
    ctx.writeState(
      res.output.module,
      res.output.bindings,
      res.extraction.closureDepth,
    );
    if (argResults!['all'] as bool) {
      for (final pl in sdk.platforms.where(
        (x) => x.hasAndroidJar && x.isStable,
      )) {
        final m = ctx.openExtractor(pl).extract(ctx.request()).module;
        OutputGuard(
          ctx.stateDir,
        ).writeString('ir-android-${pl.apiLevel}.json', m.toCanonicalJson());
      }
      b.writeln('IR snapshots written for all installed stable platforms');
    }
    final cov = CoverageReport.of(res.output.module);
    b
      ..writeln()
      ..writeln('Generated:')
      ..writeln('  classes: ${cov.generated['classes'] ?? 0}')
      ..writeln('  interfaces/callbacks: ${cov.generated['callbacks'] ?? 0}')
      ..writeln('  constructors: ${cov.generated['constructors'] ?? 0}')
      ..writeln('  methods: ${cov.generated['methods'] ?? 0}')
      ..writeln(
        '  fields+constants: ${(cov.generated['fields'] ?? 0) + (cov.generated['constants'] ?? 0)}',
      )
      ..writeln('  annotations: ${cov.generated['annotations'] ?? 0}');
    if (cov.excludedByReason.isNotEmpty) {
      b.writeln('Skipped:');
      cov.excludedByReason.forEach((k, v) => b.writeln('  $k: $v'));
    }
    if (previous != null) {
      final d = diffModules(previous, res.output.module);
      b.writeln('API changes since last update: ${d.length}');
    }
    final audit = LicenseAuditor().audit(ctx.projectDir);
    b
      ..writeln()
      ..writeln('License audit: ${audit.status.label}')
      ..writeln('Tests: not run by update (run your app\'s test suite)');
    _log.result(b.toString().trimRight(), {
      'platform': '${platform.apiLevel}',
      'coverage': cov.toJson(),
      'licenseAudit': audit.status.label,
    });
    return audit.status == AuditStatus.block ? ExitCodes.failure : ExitCodes.ok;
  }
}

/// `diff <android|ios> --from A --to B`.
final class DiffCommand extends BindgenCommand {
  /// Creates the command.
  DiffCommand() {
    _selectionOptions();
    argParser
      ..addOption('from', help: 'Older platform (e.g. 35).')
      ..addOption('to', help: 'Newer platform (e.g. 36).');
  }

  @override
  String get name => 'diff';

  @override
  String get description =>
      'Diff the API between two installed platform versions (machine-readable signatures only).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final platformName = rest.isEmpty ? 'android' : rest.first;
    if (platformName == 'ios') return _notImplemented('iOS diff');
    if (platformName != 'android') {
      throw UsageException('Unknown platform "$platformName"', usage);
    }
    final from = _opt('from'), to = _opt('to');
    if (from == null || to == null) {
      throw UsageException('--from and --to are required', usage);
    }
    final sdk = ctx.androidSdk();
    final req = _request();
    final a = ctx
        .openExtractor(ctx.androidPlatform(sdk, from))
        .extract(req)
        .module;
    final b = ctx
        .openExtractor(ctx.androidPlatform(sdk, to))
        .extract(req)
        .module;
    final entries = diffModules(a, b);
    _log.result(renderDiff(entries), {
      'from': from,
      'to': to,
      'changes': [for (final e in entries) e.toJson()],
    });
    return ExitCodes.ok;
  }
}

/// `coverage`.
final class CoverageCommand extends BindgenCommand {
  /// Creates the command.
  CoverageCommand() {
    argParser
      ..addFlag(
        'sdk',
        help:
            'Compute target coverage over the entire selected platform (not just the last generation).',
      )
      ..addOption('platform', help: 'Android platform for --sdk.');
  }

  @override
  String get name => 'coverage';

  @override
  String get description =>
      'Report generated vs. discovered API with reason codes for every exclusion.';

  @override
  Future<int> run() async {
    ApiModule module;
    String scope;
    if (argResults!['sdk'] as bool) {
      final platform = ctx.androidPlatform(ctx.androidSdk(), _opt('platform'));
      final ex = ctx.openExtractor(platform);
      final raw = ex
          .extract(ExtractionRequest(classes: ex.classes.classNames, depth: 0))
          .module;
      module = planDartJni(raw, callbacks: ctx.config.callbacks);
      scope =
          'entire android.jar of ${platform.dirName} (Flutter/Dart JNI target)';
    } else {
      final state = ctx.readState();
      if (state == null) {
        _log.error(
          'No generation state found; run "generate flutter" first or pass --sdk.',
        );
        return ExitCodes.failure;
      }
      module = state.module;
      scope = 'last generation (${module.types.length} types in closure)';
    }
    final report = CoverageReport.of(module);
    _log.result('Scope: $scope\n${report.toText()}', {
      'scope': scope,
      ...report.toJson(),
    });
    return ExitCodes.ok;
  }
}

/// `graph <symbol>`.
final class GraphCommand extends BindgenCommand {
  /// Creates the command.
  GraphCommand() {
    argParser
      ..addOption('depth', defaultsTo: '1', help: 'Edges to follow.')
      ..addOption('platform', help: 'Android platform (default: config).');
  }

  @override
  String get name => 'graph';

  @override
  String get description =>
      'Print the API dependency graph of a type (text or --json).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageException('Expected a type name', usage);
    final ex = ctx.openExtractor(
      ctx.androidPlatform(ctx.androidSdk(), _opt('platform')),
    );
    final root = ex.resolveClassName(rest.single);
    if (root == null) {
      throw CliFailure(
        Diagnostic(
          DiagnosticCode.sdkNotFound,
          'Type ${rest.single} not found',
          severity: Severity.error,
        ),
      );
    }
    final depth = _intOpt('depth') ?? 1;
    final known = ex.classes.classNames.toSet();
    Iterable<String> n(String id) {
      final t = ex.loadType(id);
      return t == null ? const [] : referencedTypeIds(t).where(known.contains);
    }

    final closure = computeClosure([root], n, maxDepth: depth);
    _log.result(renderTree(root, n, maxDepth: depth), graphJson(closure, n));
    return ExitCodes.ok;
  }
}

/// `explain`, `why-generated`, `why-skipped`.
final class ExplainCommand extends BindgenCommand {
  /// Creates one of the three explain-style commands.
  ExplainCommand(this.name, this.description) {
    argParser.addOption(
      'platform',
      help: 'Android platform (default: config).',
    );
  }

  @override
  final String name;

  @override
  final String description;

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageException('Expected a symbol', usage);
    final symbol = rest.single;
    final state = ctx.readState();
    ApiNode? node;
    Map<String, Object?>? binding;
    if (state != null) {
      final id = _normalize(state.module, symbol);
      node = id == null ? null : state.module.nodeById(id);
      binding = node == null
          ? null
          : state.bindings.where((b) => b['symbolId'] == node!.id).firstOrNull;
    }
    var fromState = node != null;
    if (node == null) {
      final ex = ctx.openExtractor(
        ctx.androidPlatform(ctx.androidSdk(), _opt('platform')),
      );
      final raw = _findSymbol(ex, symbol);
      final owner = ex.loadType(SymbolIds.ownerOf(raw.id))!;
      final planned = planDartJni(
        ApiModule(
          platform: ApiPlatform.android,
          sdkVersion: owner.provenance.sdkVersion,
          generatorVersion: ProjectInfo.generatorVersion,
          types: [owner],
        ),
        callbacks: ctx.config.callbacks,
      );
      node = planned.nodeById(raw.id);
      fromState = false;
    }
    final n = node!;
    final type = n is ApiType ? n : null;
    final prov = type?.provenance;
    final b = StringBuffer()..writeln('Symbol: ${n.id}');
    if (n is ApiMethod) {
      b.writeln(
        'Signature: ${n.isConstructor ? 'constructor' : n.returnType.display} ${n.name}(${n.parameters.map((x) => '${x.type.display} ${x.name}').join(', ')})',
      );
      b.writeln('JNI descriptor: ${n.nativeDescriptor}');
    } else if (n is ApiField) {
      b.writeln(
        'Field: ${n.type.display} ${n.name}${n.constantValue == null ? '' : ' = ${n.constantValue!.literal}'}',
      );
    }
    b
      ..writeln('Visibility: ${n.visibility.name}')
      ..writeln(
        'Availability: ${n.availability.introduced ?? '?'}+${n.availability.deprecated == null ? '' : ', deprecated in ${n.availability.deprecated}'}',
      )
      ..writeln('Support (Flutter/Dart JNI): ${n.support.name}');
    if (prov != null) {
      b.writeln(
        'Provenance: ${prov.localArtifact} › ${prov.artifactEntry} (SDK ${prov.sdkVersion})',
      );
    }
    if (n.documentation.reference != null) {
      b.writeln('Official reference: ${n.documentation.reference}');
    }
    for (final a in n.annotations) {
      b.writeln(
        'Annotation: @${a.type} [${a.classification.name}, ${a.source}]',
      );
    }
    if (n.diagnostics.isNotEmpty) {
      b.writeln(name == 'why-skipped' ? 'Why skipped:' : 'Diagnostics:');
      for (final d in n.diagnostics) {
        b.writeln('  ${d.code.code} ${d.code.label}: ${d.message}');
      }
    }
    if (binding != null) {
      b
        ..writeln('Generated as: ${binding['generated']}')
        ..writeln('Output file: ${binding['file']}')
        ..writeln('Generator: ${binding['generator']}')
        ..writeln('Runtime adapter: ${binding['runtimeAdapter']}')
        ..writeln(
          'Parser: native_api_android (class file${n.annotations.any((a) => a.source == 'annotations.zip') ? ' + annotations.zip' : ''}${n.availability.introduced != null ? ' + api-versions.xml' : ''})',
        );
    } else if (name == 'why-generated') {
      b.writeln(
        n.isGeneratable
            ? 'Not part of the last generation${fromState ? '' : ' (no generation state; analysed on the fly)'}; would be generated if selected.'
            : 'Not generated (see diagnostics).',
      );
    }
    if (name == 'why-skipped' && n.isGeneratable && n.diagnostics.isEmpty) {
      b.writeln('Not skipped: this symbol is supported.');
    }
    _log.result(b.toString().trimRight(), {
      'node': n.toJson(),
      'binding': ?binding,
      'fromState': fromState,
    });
    return ExitCodes.ok;
  }

  String? _normalize(ApiModule m, String symbol) {
    if (m.nodeById(symbol) != null) return symbol;
    final hash = symbol.indexOf('#');
    final typePart = hash < 0 ? symbol : symbol.substring(0, hash);
    var candidate = typePart;
    while (m.typeById(candidate) == null) {
      final i = candidate.lastIndexOf('.');
      if (i < 0) return null;
      candidate = '${candidate.substring(0, i)}\$${candidate.substring(i + 1)}';
    }
    if (hash < 0) return candidate;
    final member = symbol.substring(hash + 1);
    final t = m.typeById(candidate)!;
    final matches = [
      for (final n in [...t.methods, ...t.fields])
        if (n.id == '$candidate#$member' || n.name == member) n.id,
    ];
    return matches.length == 1 ? matches.single : null;
  }
}

/// `audit-license`.
final class AuditCommand extends BindgenCommand {
  /// Creates the command.
  AuditCommand() {
    argParser
      ..addOption('path', help: 'Directory to audit (default: project).')
      ..addFlag(
        'dependencies',
        defaultsTo: true,
        help: 'Also classify pub dependencies from pubspec.lock files.',
      );
  }

  @override
  String get name => 'audit-license';

  @override
  String get description =>
      'Scan for restricted SDK artifacts and classify licenses (PASS/WARN/REVIEW_REQUIRED/BLOCK).';

  @override
  Future<int> run() async {
    final root = p.normalize(p.join(ctx.projectDir, _opt('path') ?? '.'));
    final report = LicenseAuditor().audit(
      root,
      dependencies: argResults!['dependencies'] as bool,
    );
    _log.result(report.toText(), report.toJson());
    return report.status == AuditStatus.block
        ? ExitCodes.failure
        : ExitCodes.ok;
  }
}

/// `verify-reproducible`.
final class VerifyReproducibleCommand extends BindgenCommand {
  /// Creates the command.
  VerifyReproducibleCommand() {
    _selectionOptions();
  }

  @override
  String get name => 'verify-reproducible';

  @override
  String get description =>
      'Generate twice from scratch and compare outputs byte for byte.';

  @override
  Future<int> run() async {
    final platform = ctx.androidPlatform(ctx.androidSdk(), _opt('platform'));
    final req = _request();
    GenerationOutput once() => ctx.generateFlutter(platform, req).output;
    final a = once(), b = once();
    final diffs = <String>[];
    final bf = {for (final f in b.files) f.path: f.contents};
    for (final f in a.files) {
      if (bf[f.path] != f.contents) diffs.add(f.path);
    }
    if (a.files.length != b.files.length) diffs.add('<file set>');
    final ok =
        diffs.isEmpty &&
        a.module.toCanonicalJson() == b.module.toCanonicalJson();
    _log.result(
      ok
          ? 'Reproducible: ${a.files.length} files identical across two runs'
          : 'NOT reproducible: ${diffs.join(', ')}',
      {'reproducible': ok, 'files': a.files.length, 'differences': diffs},
    );
    return ok ? ExitCodes.ok : ExitCodes.failure;
  }
}

/// `clean`.
final class CleanCommand extends BindgenCommand {
  @override
  String get name => 'clean';

  @override
  String get description =>
      'Remove generated files (only files carrying the generated marker) and derived state.';

  @override
  Future<int> run() async {
    final out = p.join(ctx.projectDir, ctx.config.outputDir);
    var removed = 0;
    final manifest = File(p.join(out, '.native_api_bindgen_manifest'));
    if (manifest.existsSync()) {
      final guard = OutputGuard(out);
      for (final rel in manifest.readAsLinesSync().where(
        (l) => l.trim().isNotEmpty,
      )) {
        final f = File(guard.resolve(rel));
        if (f.existsSync() &&
            f.readAsStringSync().contains(ProjectInfo.generatedMarker)) {
          f.deleteSync();
          removed++;
        }
      }
      manifest.deleteSync();
    }
    final state = Directory(ctx.stateDir);
    if (state.existsSync()) state.deleteSync(recursive: true);
    _log.result(
      'Removed $removed generated files and ${ProjectInfo.stateDirName}/',
      {'removed': removed},
    );
    return ExitCodes.ok;
  }
}
