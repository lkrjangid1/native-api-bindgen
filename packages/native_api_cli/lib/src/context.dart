import 'dart:convert';
import 'dart:io';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_android/native_api_flutter_android.dart';
import 'package:native_api_flutter_ios/native_api_flutter_ios.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/native_api_ios.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

/// Process exit codes.
abstract final class ExitCodes {
  /// Success.
  static const ok = 0;

  /// Failure (including license BLOCK).
  static const failure = 1;

  /// Requested feature not implemented (E015).
  static const notImplemented = 2;

  /// Command-line usage error.
  static const usage = 64;
}

/// Thrown to stop a command with a diagnostic and exit code.
final class CliFailure implements Exception {
  /// Creates a failure.
  CliFailure(this.diagnostic, [this.exitCode = ExitCodes.failure]);

  /// Diagnostic to print.
  final Diagnostic diagnostic;

  /// Exit code.
  final int exitCode;
}

/// Shared state for a CLI invocation.
final class CliContext {
  /// Creates a context.
  CliContext({
    required this.logger,
    required this.projectDir,
    required this.configPath,
    this.environment,
  });

  /// Logger.
  final Logger logger;

  /// Project root (absolute).
  final String projectDir;

  /// Configuration file path (absolute).
  final String configPath;

  /// Environment override (tests).
  final Map<String, String>? environment;

  BindgenConfig? _config;

  /// Library artifacts added on the command line (`--jar`).
  List<String> extraLibraries = const [];

  /// Configured + command-line library artifacts as absolute paths; fails
  /// with E001 when one does not exist.
  List<String> androidLibraries() {
    final out = <String>[];
    for (final l in [...config.android.libraries, ...extraLibraries]) {
      final path = p.normalize(p.isAbsolute(l) ? l : p.join(projectDir, l));
      if (!File(path).existsSync() && !Directory(path).existsSync()) {
        throw CliFailure(
          Diagnostic(
            DiagnosticCode.sdkNotFound,
            'Library artifact not found: $l',
            severity: Severity.error,
          ),
        );
      }
      out.add(path);
    }
    return out;
  }

  /// Configuration (defaults if the file does not exist).
  BindgenConfig get config {
    try {
      return _config ??= BindgenConfig.loadOrDefault(configPath);
    } on ConfigException catch (e) {
      throw CliFailure(
        Diagnostic(
          DiagnosticCode.configInvalid,
          e.message,
          severity: Severity.error,
        ),
        ExitCodes.usage,
      );
    }
  }

  /// State directory for derived artifacts (IR, coverage, binding map).
  String get stateDir => p.join(projectDir, ProjectInfo.stateDirName);

  /// Locates the Android SDK or fails with E001.
  AndroidSdk androidSdk() {
    final sdk = AndroidSdkLocator(
      environment: environment,
    ).locate(configured: config.android.sdk);
    if (sdk == null) {
      throw CliFailure(
        const Diagnostic(
          DiagnosticCode.sdkNotFound,
          'Android SDK not found. Set ANDROID_HOME, or platform.android.sdk in the configuration. '
          'Install platforms with the official SDK Manager; this tool never downloads SDK components.',
          severity: Severity.error,
        ),
      );
    }
    return sdk;
  }

  /// Selects a platform (`--platform` overrides configuration) or fails.
  AndroidPlatform androidPlatform(AndroidSdk sdk, [String? override]) {
    final spec = override ?? config.android.platform;
    final platform = sdk.select(spec);
    if (platform == null) {
      throw CliFailure(
        Diagnostic(
          DiagnosticCode.sdkNotFound,
          'Android platform "$spec" with android.jar not installed. Installed: '
          '${sdk.platforms.map((x) => x.dirName).join(', ')}',
          severity: Severity.error,
        ),
      );
    }
    if (!platform.hasApiVersions) {
      logger.warn(
        '${platform.dirName}: data/api-versions.xml missing; availability and non-SDK detection disabled',
      );
    }
    return platform;
  }

  /// Opens an extractor for [platform].
  AndroidApiExtractor openExtractor(AndroidPlatform platform) {
    logger.info(
      'SDK detected: ${platform.dirName} (API ${platform.apiLevel})',
      event: 'sdk-detected',
    );
    try {
      final libraries = androidLibraries();
      for (final l in libraries) {
        logger.info('Library: ${p.basename(l)}', event: 'library');
      }
      return openPlatform(platform, libraries: libraries);
    } on MalformedInputException catch (e) {
      throw CliFailure(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'Cannot read ${platform.dirName}: ${e.message}',
          severity: Severity.error,
        ),
      );
    }
  }

  /// Builds an extraction request from configuration plus CLI overrides.
  ExtractionRequest request({
    List<String>? packages,
    List<String>? classes,
    List<String>? entries,
    int? depth,
  }) {
    final a = config.android;
    final r = ExtractionRequest(
      packages: (packages == null || packages.isEmpty) ? a.include : packages,
      classes: (classes == null || classes.isEmpty) ? a.classes : classes,
      entries: (entries == null || entries.isEmpty) ? a.entries : entries,
      depth: depth ?? a.depth,
    );
    final cliSelection = [...?packages, ...?classes, ...?entries].isNotEmpty;
    if (cliSelection) {
      // CLI selection replaces configured selection entirely.
      return ExtractionRequest(
        packages: packages ?? const [],
        classes: classes ?? const [],
        entries: entries ?? const [],
        depth: depth ?? a.depth,
      );
    }
    if (r.isEmpty) {
      throw CliFailure(
        const Diagnostic(
          DiagnosticCode.configInvalid,
          'Nothing selected. Use --entry/--class/--package or set platform.android.entries/classes/include. '
          'Generating the entire SDK is never implicit.',
          severity: Severity.error,
        ),
        ExitCodes.usage,
      );
    }
    return r;
  }

  /// Runs Android extraction + Flutter emission.
  ({ExtractionResult extraction, GenerationOutput output}) generateFlutter(
    AndroidPlatform platform,
    ExtractionRequest request, {
    GenerationMode? mode,
  }) {
    final extraction = openExtractor(platform).extract(request);
    logger.info(
      'Parsed ${extraction.module.types.length} types',
      event: 'parsed',
    );
    for (final d in extraction.diagnostics) {
      logger.diagnostic(d);
    }
    final minApi = ApiVersion(config.android.minApi);
    final out = DartJniEmitter(
      extraction.module,
      options: DartJniOptions(
        minApi: minApi,
        mode: mode ?? config.mode,
        callbacks: config.callbacks,
      ),
    ).emit();
    for (final d in out.diagnostics) {
      logger.diagnostic(d);
    }
    return (extraction: extraction, output: out);
  }

  /// Locates the configured Apple SDK through `xcrun` or fails with E001.
  AppleSdk appleSdk() {
    final sdk = XcodeLocator().locate(sdkName: config.ios.sdkName);
    if (sdk == null || !File(sdk.libclangPath).existsSync()) {
      throw CliFailure(
        Diagnostic(
          DiagnosticCode.sdkNotFound,
          Platform.isMacOS
              ? 'Xcode with the ${config.ios.sdkName} SDK not found. Install Xcode and run '
                    '`xcode-select -s /Applications/Xcode.app`; this tool never downloads SDKs.'
              : 'iOS bindings can only be generated on macOS with Xcode installed.',
          severity: Severity.error,
        ),
      );
    }
    return sdk;
  }

  /// Builds an iOS extraction request from configuration plus CLI
  /// overrides, and the frameworks whose headers must be parsed.
  ({ObjCRequest request, List<String> parse}) iosRequest({
    List<String>? frameworks,
    List<String>? classes,
    List<String>? entries,
    int? depth,
  }) {
    final c = config.ios;
    final cli = [...?frameworks, ...?classes, ...?entries].isNotEmpty;
    final request = ObjCRequest(
      frameworks: cli ? (frameworks ?? const []) : c.include,
      classes: cli ? (classes ?? const []) : c.classes,
      entries: cli ? (entries ?? const []) : c.entries,
      depth: depth ?? c.depth,
    );
    if ([
          ...request.frameworks,
          ...request.classes,
          ...request.entries,
        ].isEmpty &&
        c.swiftModules.isEmpty) {
      throw CliFailure(
        const Diagnostic(
          DiagnosticCode.configInvalid,
          'Nothing selected for iOS. Use --framework/--class/--entry or set platform.ios.include/classes/entries. '
          'Generating the entire SDK is never implicit.',
          severity: Severity.error,
        ),
        ExitCodes.usage,
      );
    }
    final parse = <String>{
      if (c.swiftModules.isNotEmpty) 'Foundation',
      ...c.frameworks,
      ...request.frameworks,
      for (final n in [...request.classes, ...request.entries])
        if (n.contains('.')) n.substring(0, n.indexOf('.')),
    };
    if (parse.isEmpty) {
      throw CliFailure(
        const Diagnostic(
          DiagnosticCode.configInvalid,
          'No headers to parse: set platform.ios.frameworks (e.g. [Foundation, UIKit]) '
          'or qualify names as Framework.Class.',
          severity: Severity.error,
        ),
        ExitCodes.usage,
      );
    }
    return (request: request, parse: parse.toList()..sort());
  }

  /// Generates `@objc` adapters for `platform.ios.swift` modules (Swift
  /// sources + podspec into `swiftAdaptersDir`). Returns the adapter
  /// headers (binding input, in [temp]), adapter class names, and each
  /// module's Swift API with support decisions.
  ({List<String> headers, List<String> classes, List<ApiModule> swift})
  swiftAdapters(AppleSdk sdk, Directory temp) {
    final c = config.ios;
    if (c.swiftModules.isEmpty) {
      return (headers: const [], classes: const [], swift: const []);
    }
    final tc = SwiftToolchain(sdk, minIos: c.minVersion);
    final guard = OutputGuard(p.join(projectDir, c.swiftAdaptersDir));
    final headers = <String>[];
    final classes = <String>[];
    final swift = <ApiModule>[];
    final deps = <String>[];
    final frameworks = <String>[];
    for (final m in c.swiftModules) {
      final include = <String>[];
      try {
        if (m.sources.isNotEmpty) {
          final sources = [
            for (final s in m.sources)
              p.normalize(p.isAbsolute(s) ? s : p.join(projectDir, s)),
          ];
          for (final s in sources) {
            if (!File(s).existsSync()) {
              throw CliFailure(
                Diagnostic(
                  DiagnosticCode.sdkNotFound,
                  'Swift source not found: $s',
                  severity: Severity.error,
                ),
              );
            }
          }
          final mod = tc.emitModule(
            m.name,
            sources,
            p.join(temp.path, 'modules'),
          );
          include.add(p.dirname(mod));
          deps.add(m.name);
        } else {
          frameworks.add(m.name);
        }
        logger.info('Swift module: ${m.name}', event: 'swift-module');
        final graph = SwiftModuleGraph.read(
          tc.extractSymbolGraph(
            m.name,
            p.join(temp.path, 'symbolgraphs'),
            includeDirs: include,
          ),
        );
        final out = SwiftAdapterGenerator(
          graph,
          types: m.types,
          sdkVersion: sdk.version,
        ).generate();
        guard.writeString('${m.name}Adapters.swift', out.swift);
        final h = File(p.join(temp.path, '${m.name}Adapters.h'))
          ..writeAsStringSync(out.header);
        headers.add(h.path);
        swift.add(out.module);
        for (final t in out.module.types) {
          if (t.isGeneratable) {
            classes.add('${m.name}_${t.name.replaceAll('.', '_')}');
          }
        }
      } on SwiftToolchainException catch (e) {
        throw CliFailure(
          Diagnostic(
            DiagnosticCode.invalidAst,
            'Swift toolchain failed for ${m.name}: ${e.message}',
            severity: Severity.error,
          ),
        );
      }
    }
    guard.writeString(
      'NativeApiSwiftAdapters.podspec',
      SwiftAdapterGenerator.podspec(
        dependencies: deps,
        frameworks: frameworks,
        minIos: c.minVersion,
      ),
    );
    return (headers: headers, classes: classes, swift: swift);
  }

  /// Parses the requested frameworks (plus Swift adapter [headerFiles]) and
  /// extracts Apple IR.
  ApiModule extractIos(
    AppleSdk sdk,
    ({ObjCRequest request, List<String> parse}) r, {
    List<String> headerFiles = const [],
    List<String> extraClasses = const [],
  }) {
    logger.info(
      'SDK detected: ${sdk.name} ${sdk.version} (${sdk.xcodeVersion})',
      event: 'sdk-detected',
    );
    final ex = ObjCExtractor(
      libclangPath: sdk.libclangPath,
      sysroot: sdk.path,
      target: sdk.name == 'iphoneos'
          ? 'arm64-apple-ios${config.ios.minVersion}'
          : 'arm64-apple-ios${config.ios.minVersion}-simulator',
      sdkVersion: sdk.version,
      fixtureModule: headerFiles.isEmpty ? null : 'SwiftAdapters',
      fixtureArtifact: 'generated Swift adapters',
    )..parse([for (final f in r.parse) '$f/$f.h'], headerFiles: headerFiles);
    final module = ex.extract(
      ObjCRequest(
        frameworks: r.request.frameworks,
        classes: [...r.request.classes, ...extraClasses],
        entries: r.request.entries,
        depth: r.request.depth,
      ),
    );
    logger.info('Parsed ${module.types.length} types', event: 'parsed');
    for (final d in module.diagnostics) {
      logger.diagnostic(d);
    }
    if (module.diagnostics.any((d) => d.severity == Severity.error)) {
      throw CliFailure(
        module.diagnostics.firstWhere((d) => d.severity == Severity.error),
      );
    }
    return module;
  }

  /// Runs iOS extraction + Flutter (package:objective_c) emission.
  GenerationOutput generateFlutterIos(ApiModule module) {
    final out = DartObjCEmitter(
      module,
      options: DartObjCOptions(minIos: ApiVersion.parse(config.ios.minVersion)),
    ).emit();
    for (final d in out.diagnostics) {
      logger.diagnostic(d);
    }
    return out;
  }

  /// Persists derived state used by coverage / why-* commands; [subdir]
  /// separates platforms (`ios`).
  void writeState(
    ApiModule planned,
    List<BindingMapEntry> bindings,
    Map<String, int> closure, {
    String? subdir,
  }) {
    final guard = OutputGuard(
      subdir == null ? stateDir : p.join(stateDir, subdir),
    );
    guard.writeStreaming('ir.json', planned.writeCanonicalJson);
    guard.writeStreaming(
      'binding_map.json',
      (out) => writeCanonicalJsonWithList(
        out,
        const {},
        'bindings',
        bindings.map((b) => b.toJson()),
      ),
    );
    guard.writeString(
      'coverage.json',
      canonicalJson(CoverageReport.of(planned).toJson()),
    );
    guard.writeString('closure.json', canonicalJson({'closure': closure}));
  }

  /// Every persisted generation state: `android` (the root state), `ios`,
  /// `ios-rn` and `ios-swift/<Module>`.
  List<({String label, ApiModule module, List<Map<String, Object?>> bindings})>
  allStates() {
    final labels = <String>[
      'android',
      'ios',
      'ios-rn',
      if (Directory(p.join(stateDir, 'ios-swift')).existsSync())
        for (final d in Directory(
          p.join(stateDir, 'ios-swift'),
        ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
          if (d is Directory) 'ios-swift/${p.basename(d.path)}',
    ];
    return [
      for (final l in labels)
        if (readState(subdir: l == 'android' ? null : l) case final s?)
          (label: l, module: s.module, bindings: s.bindings),
    ];
  }

  /// Loads persisted state (the root, or [subdir] such as `ios`), or null.
  ({ApiModule module, List<Map<String, Object?>> bindings})? readState({
    String? subdir,
  }) {
    final dir = subdir == null ? stateDir : p.join(stateDir, subdir);
    final ir = File(p.join(dir, 'ir.json'));
    final map = File(p.join(dir, 'binding_map.json'));
    if (!ir.existsSync() || !map.existsSync()) return null;
    final decoded = decodeModule(ir.readAsStringSync());
    if (decoded.module == null) return null;
    final json = jsonDecode(map.readAsStringSync()) as Map<String, Object?>;
    return (
      module: decoded.module!,
      bindings: [
        for (final b in json['bindings']! as List<Object?>)
          b! as Map<String, Object?>,
      ],
    );
  }
}
