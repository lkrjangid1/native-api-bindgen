import 'dart:convert';
import 'dart:io';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_android/native_api_flutter_android.dart';
import 'package:native_api_generator/native_api_generator.dart';
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
      return openPlatform(platform);
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

  /// Persists derived state used by coverage / why-* commands.
  void writeState(
    ApiModule planned,
    List<BindingMapEntry> bindings,
    Map<String, int> closure,
  ) {
    final guard = OutputGuard(stateDir);
    guard.writeString('ir.json', planned.toCanonicalJson());
    guard.writeString(
      'binding_map.json',
      canonicalJson({
        'bindings': [for (final b in bindings) b.toJson()],
      }),
    );
    guard.writeString(
      'coverage.json',
      canonicalJson(CoverageReport.of(planned).toJson()),
    );
    guard.writeString('closure.json', canonicalJson({'closure': closure}));
  }

  /// Loads persisted state, or null.
  ({ApiModule module, List<Map<String, Object?>> bindings})? readState() {
    final ir = File(p.join(stateDir, 'ir.json'));
    final map = File(p.join(stateDir, 'binding_map.json'));
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
