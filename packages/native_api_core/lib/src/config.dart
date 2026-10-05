import 'dart:io';

import 'package:yaml/yaml.dart';

import 'project_info.dart';

/// Thrown for invalid configuration (diagnostic `E018`).
final class ConfigException implements Exception {
  /// Creates the exception.
  ConfigException(this.message);

  /// Explanation.
  final String message;

  @override
  String toString() => 'E018 CONFIG_INVALID: $message';
}

/// Type-mapping mode (TRD §14).
enum GenerationMode {
  /// Native semantics visible (JString, explicit release). Default.
  strictNative('strict-native'),

  /// Dart-friendly conveniences where lossless.
  ergonomicDart('ergonomic-dart'),

  /// TypeScript strict (planned).
  strictTypescript('strict-typescript'),

  /// TypeScript ergonomic (planned).
  ergonomicTypescript('ergonomic-typescript');

  const GenerationMode(this.key);

  /// YAML spelling.
  final String key;
}

/// TypeScript mapping mode for React Native (TRD §14).
enum TypescriptMode {
  /// Java `long` → `bigint` (exact). Default.
  strict('strict-typescript'),

  /// Java `long` → `number` (values beyond ±2^53 lose precision, E011).
  ergonomic('ergonomic-typescript');

  const TypescriptMode(this.key);

  /// YAML spelling.
  final String key;
}

/// Documentation mode.
enum DocumentationMode {
  /// Only metadata and links to official references. Default.
  linksOnly('links-only'),

  /// Project-authored summaries plus links.
  summary('summary');

  const DocumentationMode(this.key);

  /// YAML spelling.
  final String key;
}

/// Whether generated bindings may be published.
enum GeneratedArtifactsPolicy {
  /// Keep generated bindings in the user's project only. Default.
  localOnly('local-only'),

  /// Generated bindings may be published (requires legal review).
  allowed('allowed');

  const GeneratedArtifactsPolicy(this.key);

  /// YAML spelling.
  final String key;
}

/// Android platform configuration.
final class AndroidConfig {
  /// Creates Android configuration.
  const AndroidConfig({
    this.sdk = 'auto',
    this.platform = 'auto',
    this.minApi = 24,
    this.include = const [],
    this.classes = const [],
    this.entries = const [],
    this.depth = 1,
    this.libraries = const [],
  });

  /// `auto` or an SDK root path.
  final String sdk;

  /// `auto` (highest stable installed) or a platform such as `36`.
  final String platform;

  /// Minimum API level of the consuming app; newer APIs get guards.
  final int minApi;

  /// Java packages to generate entirely (e.g. `android.net`).
  final List<String> include;

  /// Individual classes to generate.
  final List<String> classes;

  /// Entry classes for dependency-aware generation.
  final List<String> entries;

  /// Dependency depth from entries (0 = entries only).
  final int depth;

  /// Library artifacts (`.jar`, `.aar`, class directories; relative to the
  /// project) whose classes can be selected like SDK classes, e.g. a Kotlin
  /// library. Their APIs are library APIs, not platform SDK APIs.
  final List<String> libraries;
}

/// Apple (iOS) platform configuration.
final class IosConfig {
  /// Creates iOS configuration.
  const IosConfig({
    this.sdk = 'auto',
    this.minVersion = '13.0',
    this.frameworks = const [],
    this.include = const [],
    this.classes = const [],
    this.entries = const [],
    this.depth = 1,
  });

  /// `auto` (iphonesimulator), `iphonesimulator` or `iphoneos`.
  final String sdk;

  /// Minimum iOS version of the app; newer APIs get runtime guards.
  final String minVersion;

  /// Frameworks whose headers are parsed (e.g. `[Foundation, UIKit]`).
  final List<String> frameworks;

  /// Frameworks to generate entirely.
  final List<String> include;

  /// Individual classes/protocols (`UIView` or `UIKit.UIView`).
  final List<String> classes;

  /// Entry types for dependency-aware generation.
  final List<String> entries;

  /// Dependency depth from entries (0 = entries only).
  final int depth;

  /// The xcrun SDK name.
  String get sdkName => sdk == 'auto' ? 'iphonesimulator' : sdk;
}

/// Full `native_api_bindgen.yaml` configuration.
final class BindgenConfig {
  /// Creates a configuration.
  const BindgenConfig({
    this.android = const AndroidConfig(),
    this.ios = const IosConfig(),
    this.flutter = true,
    this.reactNative = false,
    this.mode = GenerationMode.strictNative,
    this.docs = DocumentationMode.linksOnly,
    this.preserveAnnotations = true,
    this.callbacks = true,
    this.outputDir = 'lib/src/generated',
    this.reactNativeDir = 'native-api-bindings',
    this.typescriptMode = TypescriptMode.strict,
    this.generatedArtifacts = GeneratedArtifactsPolicy.localOnly,
  });

  /// Parses YAML text. Unknown keys are rejected so typos are not ignored.
  factory BindgenConfig.parse(String text) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw ConfigException('YAML error: ${e.message}');
    }
    if (doc == null) return const BindgenConfig();
    final root = _map(doc, 'root');
    _keys(root, 'root', {
      'platform',
      'targets',
      'generation',
      'output',
      'distribution',
    });

    final platform = _optMap(root['platform'], 'platform');
    _keys(platform, 'platform', {'android', 'ios'});
    final a = _optMap(platform['android'], 'platform.android');
    _keys(a, 'platform.android', {
      'sdk',
      'platform',
      'minApi',
      'include',
      'classes',
      'entries',
      'depth',
      'libraries',
    });
    final ios = _optMap(platform['ios'], 'platform.ios');
    _keys(ios, 'platform.ios', {
      'sdk',
      'minVersion',
      'frameworks',
      'include',
      'classes',
      'entries',
      'depth',
    });
    final iosSdk = _str(ios['sdk'], 'platform.ios.sdk', 'auto');
    if (!{'auto', 'iphonesimulator', 'iphoneos'}.contains(iosSdk)) {
      throw ConfigException(
        'platform.ios.sdk must be auto, iphonesimulator or iphoneos',
      );
    }
    final iosMin = '${ios['minVersion'] ?? '13.0'}';
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){0,2}$').hasMatch(iosMin)) {
      throw ConfigException('platform.ios.minVersion must look like 13.0');
    }
    final iosDepth = _int(ios['depth'], 'platform.ios.depth', 1);
    if (iosDepth < 0 || iosDepth > 8) {
      throw ConfigException('platform.ios.depth must be 0..8');
    }

    final targets = _optMap(root['targets'], 'targets');
    _keys(targets, 'targets', {'flutter', 'reactNative'});
    final gen = _optMap(root['generation'], 'generation');
    _keys(gen, 'generation', {
      'mode',
      'typescriptMode',
      'docs',
      'annotations',
      'callbacks',
    });
    final output = _optMap(root['output'], 'output');
    _keys(output, 'output', {'dir', 'reactNativeDir'});
    final dist = _optMap(root['distribution'], 'distribution');
    _keys(dist, 'distribution', {'generatedArtifacts', 'documentationMode'});

    final minApi = _int(a['minApi'], 'platform.android.minApi', 24);
    if (minApi < 1 || minApi > 1000) {
      throw ConfigException('platform.android.minApi out of range: $minApi');
    }
    final depth = _int(a['depth'], 'platform.android.depth', 1);
    if (depth < 0 || depth > 8) {
      throw ConfigException('platform.android.depth must be 0..8');
    }
    final docsKey = dist['documentationMode'] ?? gen['docs'];
    final annotations = gen['annotations'] ?? 'preserve';
    if (annotations != 'preserve' && annotations != 'drop') {
      throw ConfigException('generation.annotations must be preserve|drop');
    }
    return BindgenConfig(
      android: AndroidConfig(
        sdk: _str(a['sdk'], 'platform.android.sdk', 'auto'),
        platform: '${a['platform'] ?? 'auto'}',
        minApi: minApi,
        include: _names(a['include'], 'platform.android.include'),
        classes: _names(a['classes'], 'platform.android.classes'),
        entries: _names(a['entries'], 'platform.android.entries'),
        depth: depth,
        libraries: _paths(a['libraries'], 'platform.android.libraries'),
      ),
      ios: IosConfig(
        sdk: iosSdk,
        minVersion: iosMin,
        frameworks: _names(ios['frameworks'], 'platform.ios.frameworks'),
        include: _names(ios['include'], 'platform.ios.include'),
        classes: _names(ios['classes'], 'platform.ios.classes'),
        entries: _names(ios['entries'], 'platform.ios.entries'),
        depth: iosDepth,
      ),
      flutter: _bool(targets['flutter'], 'targets.flutter', true),
      reactNative: _bool(targets['reactNative'], 'targets.reactNative', false),
      mode: _enum(gen['mode'], GenerationMode.values, (m) => m.key, 'mode'),
      docs: _enum(
        docsKey,
        DocumentationMode.values,
        (m) => m.key,
        'documentationMode',
      ),
      preserveAnnotations: annotations == 'preserve',
      callbacks: _bool(gen['callbacks'], 'generation.callbacks', true),
      outputDir: _str(output['dir'], 'output.dir', 'lib/src/generated'),
      reactNativeDir: _str(
        output['reactNativeDir'],
        'output.reactNativeDir',
        'native-api-bindings',
      ),
      typescriptMode: _enum(
        gen['typescriptMode'],
        TypescriptMode.values,
        (m) => m.key,
        'typescriptMode',
      ),
      generatedArtifacts: _enum(
        dist['generatedArtifacts'],
        GeneratedArtifactsPolicy.values,
        (m) => m.key,
        'generatedArtifacts',
      ),
    );
  }

  /// Loads [path] if it exists, otherwise returns defaults.
  static BindgenConfig loadOrDefault(String path) {
    final f = File(path);
    return f.existsSync()
        ? BindgenConfig.parse(f.readAsStringSync())
        : const BindgenConfig();
  }

  /// Android settings.
  final AndroidConfig android;

  /// Apple (iOS) settings.
  final IosConfig ios;

  /// Generate Flutter bindings.
  final bool flutter;

  /// Generate React Native bindings (not yet implemented).
  final bool reactNative;

  /// Type-mapping mode.
  final GenerationMode mode;

  /// Documentation mode.
  final DocumentationMode docs;

  /// Preserve annotation metadata in generated docs.
  final bool preserveAnnotations;

  /// Generate callback implementations.
  final bool callbacks;

  /// Output directory, relative to the project root.
  final String outputDir;

  /// React Native bindings library directory, relative to the project root.
  final String reactNativeDir;

  /// TypeScript mapping mode for React Native output.
  final TypescriptMode typescriptMode;

  /// Distribution policy for generated bindings.
  final GeneratedArtifactsPolicy generatedArtifacts;

  /// Stable fingerprint of options that influence generated output.
  String get fingerprint => [
    android.platform,
    android.minApi,
    android.include.join(','),
    android.classes.join(','),
    android.entries.join(','),
    android.depth,
    android.libraries.join(','),
    mode.key,
    docs.key,
    preserveAnnotations,
    callbacks,
    typescriptMode.key,
    ios.sdkName,
    ios.minVersion,
    ios.frameworks.join(','),
    ios.include.join(','),
    ios.classes.join(','),
    ios.entries.join(','),
    ios.depth,
  ].join('|');

  /// Default configuration file written by `init`.
  static String defaultYaml() =>
      '''
# ${ProjectInfo.configFileName} — configuration for ${ProjectInfo.name}.
# Generated bindings are derived from SDKs installed on this machine.

platform:
  android:
    sdk: auto          # or an SDK path; ANDROID_HOME / ANDROID_SDK_ROOT are honoured
    platform: auto     # highest stable installed platform, or e.g. 36
    minApi: 24         # APIs newer than this get runtime availability guards
    include: []        # whole Java packages, e.g. [android.net]
    classes: []        # individual classes
    entries:           # dependency-aware generation roots
      - android.content.Intent
    depth: 1           # how far to follow referenced types from entries

  ios:
    sdk: auto          # iphonesimulator (default) or iphoneos, via xcrun
    minVersion: "13.0" # APIs newer than this get runtime availability guards
    frameworks: []     # headers to parse, e.g. [Foundation, UIKit]
    include: []        # frameworks to generate entirely
    classes: []        # individual classes/protocols, e.g. [UIDevice]
    entries: []        # dependency-aware roots
    depth: 1

targets:
  flutter: true
  reactNative: false   # not yet implemented

generation:
  mode: strict-native               # Dart: strict-native | ergonomic-dart
  typescriptMode: strict-typescript # RN: strict-typescript (long = bigint) | ergonomic-typescript
  annotations: preserve
  callbacks: true

output:
  dir: lib/src/generated              # Flutter bindings
  reactNativeDir: native-api-bindings # React Native bindings library

distribution:
  generatedArtifacts: local-only   # safest default; see docs/legal
  documentationMode: links-only
''';
}

final _javaName = RegExp(
  r'^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$',
);

Map<Object?, Object?> _map(Object? v, String where) {
  if (v is Map) return v;
  throw ConfigException('$where must be a mapping');
}

Map<Object?, Object?> _optMap(Object? v, String where) =>
    v == null ? const {} : _map(v, where);

void _keys(Map<Object?, Object?> m, String where, Set<String> allowed) {
  for (final k in m.keys) {
    if (!allowed.contains(k)) {
      throw ConfigException('Unknown key "$k" in $where');
    }
  }
}

String _str(Object? v, String where, String fallback) {
  if (v == null) return fallback;
  if (v is String && v.isNotEmpty) return v;
  throw ConfigException('$where must be a non-empty string');
}

int _int(Object? v, String where, int fallback) {
  if (v == null) return fallback;
  if (v is int) return v;
  throw ConfigException('$where must be an integer');
}

bool _bool(Object? v, String where, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  throw ConfigException('$where must be true or false');
}

List<String> _names(Object? v, String where) {
  if (v == null) return const [];
  if (v is! List) throw ConfigException('$where must be a list');
  return [
    for (final e in v)
      if (e is String && _javaName.hasMatch(e))
        e
      else
        throw ConfigException('$where contains an invalid name: $e'),
  ];
}

List<String> _paths(Object? v, String where) {
  if (v == null) return const [];
  if (v is! List) throw ConfigException('$where must be a list');
  return [
    for (final e in v)
      if (e is String && e.isNotEmpty && !e.contains('\u0000'))
        e
      else
        throw ConfigException('$where contains an invalid path: $e'),
  ];
}

T _enum<T>(Object? v, List<T> values, String Function(T) key, String where) {
  if (v == null) return values.first;
  for (final e in values) {
    if (key(e) == v) return e;
  }
  throw ConfigException(
    'Invalid $where "$v"; expected one of ${values.map(key).join(', ')}',
  );
}
