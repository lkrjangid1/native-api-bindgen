import 'dart:io';

import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

/// An installed Android SDK Platform package (`platforms/android-N`).
final class AndroidPlatform implements Comparable<AndroidPlatform> {
  /// Creates platform info.
  const AndroidPlatform({
    required this.directory,
    required this.dirName,
    required this.apiLevel,
    required this.properties,
  });

  /// Absolute directory.
  final String directory;

  /// Directory name, e.g. `android-36.1`.
  final String dirName;

  /// API level from `AndroidVersion.ApiLevel` (falls back to the dir name).
  final ApiVersion apiLevel;

  /// Parsed `source.properties`.
  final Map<String, String> properties;

  /// `Pkg.Revision`.
  String? get revision => properties['Pkg.Revision'];

  /// `AndroidVersion.ExtensionLevel`.
  String? get extensionLevel => properties['AndroidVersion.ExtensionLevel'];

  /// Preview codename (empty/absent for stable releases).
  String? get codename {
    final c =
        properties['AndroidVersion.CodeName'] ??
        properties['Platform.CodeName'];
    return (c == null || c.isEmpty) ? null : c;
  }

  /// Whether this is a stable (non-preview) platform.
  bool get isStable => codename == null;

  /// `android.jar` path.
  String get androidJar => p.join(directory, 'android.jar');

  /// `data/api-versions.xml` path.
  String get apiVersionsXml => p.join(directory, 'data', 'api-versions.xml');

  /// `data/annotations.zip` path.
  String get annotationsZip => p.join(directory, 'data', 'annotations.zip');

  /// Whether the required jar exists.
  bool get hasAndroidJar => File(androidJar).existsSync();

  /// Whether availability metadata exists.
  bool get hasApiVersions => File(apiVersionsXml).existsSync();

  /// Whether external annotations exist.
  bool get hasAnnotations => File(annotationsZip).existsSync();

  @override
  int compareTo(AndroidPlatform o) => apiLevel.compareTo(o.apiLevel);

  /// JSON form (no absolute paths).
  Map<String, Object?> toJson() => {
    'name': dirName,
    'apiLevel': '$apiLevel',
    'revision': revision,
    'extensionLevel': extensionLevel,
    'stable': isStable,
    'androidJar': hasAndroidJar,
    'apiVersions': hasApiVersions,
    'annotations': hasAnnotations,
  };
}

/// A discovered Android SDK.
final class AndroidSdk {
  /// Creates SDK info.
  const AndroidSdk({
    required this.root,
    required this.source,
    required this.platforms,
    required this.buildTools,
    required this.ndks,
    required this.hasSdkManager,
    required this.sourcePackages,
  });

  /// SDK root (absolute).
  final String root;

  /// How it was found: `config`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `default`.
  final String source;

  /// Installed platforms, ascending.
  final List<AndroidPlatform> platforms;

  /// Installed build-tools versions, ascending.
  final List<String> buildTools;

  /// Installed NDK versions, ascending.
  final List<String> ndks;

  /// Whether `cmdline-tools/*/bin/sdkmanager` exists.
  final bool hasSdkManager;

  /// Installed `sources/android-N` packages.
  final List<String> sourcePackages;

  /// Selects a platform: `auto` = highest stable platform with android.jar.
  /// Returns null if not found.
  AndroidPlatform? select(String spec) {
    final usable = platforms.where((x) => x.hasAndroidJar).toList();
    if (spec == 'auto') {
      final stable = usable.where((x) => x.isStable).toList();
      return stable.isEmpty ? null : stable.last;
    }
    final want = ApiVersion.tryParse(spec);
    for (final x in usable.reversed) {
      if (x.dirName == spec ||
          x.dirName == 'android-$spec' ||
          x.apiLevel == want) {
        return x;
      }
    }
    return null;
  }

  /// JSON form (root is reported because it is the user's own machine data,
  /// but it is never embedded in generated output).
  Map<String, Object?> toJson() => {
    'root': root,
    'source': source,
    'platforms': [for (final x in platforms) x.toJson()],
    'buildTools': buildTools,
    'ndk': ndks,
    'sdkManager': hasSdkManager,
    'sources': sourcePackages,
  };
}

/// Locates the Android SDK using documented mechanisms: an explicit path,
/// `ANDROID_HOME`, `ANDROID_SDK_ROOT` (deprecated alias), then the default
/// Android Studio location per OS. Never downloads anything.
final class AndroidSdkLocator {
  /// Creates a locator. [environment] and [homeDir] are injectable for tests.
  AndroidSdkLocator({Map<String, String>? environment, String? homeDir})
    : _env = environment ?? Platform.environment,
      _home = homeDir;

  final Map<String, String> _env;
  final String? _home;

  /// Candidate roots in priority order with their source label.
  List<(String, String)> candidates({String configured = 'auto'}) {
    final out = <(String, String)>[];
    if (configured != 'auto') out.add((configured, 'config'));
    final home = _env['ANDROID_HOME'];
    if (home != null && home.isNotEmpty) out.add((home, 'ANDROID_HOME'));
    final root = _env['ANDROID_SDK_ROOT'];
    if (root != null && root.isNotEmpty) out.add((root, 'ANDROID_SDK_ROOT'));
    final userHome = _home ?? _env['HOME'] ?? _env['USERPROFILE'];
    if (userHome != null) {
      if (Platform.isMacOS) {
        out.add((p.join(userHome, 'Library', 'Android', 'sdk'), 'default'));
      } else if (Platform.isWindows) {
        final local =
            _env['LOCALAPPDATA'] ?? p.join(userHome, 'AppData', 'Local');
        out.add((p.join(local, 'Android', 'Sdk'), 'default'));
      } else {
        out.add((p.join(userHome, 'Android', 'Sdk'), 'default'));
      }
    }
    return out;
  }

  /// Finds the first valid SDK (a directory containing `platforms/`).
  AndroidSdk? locate({String configured = 'auto'}) {
    for (final (path, source) in candidates(configured: configured)) {
      final dir = Directory(path);
      if (dir.existsSync() &&
          Directory(p.join(path, 'platforms')).existsSync()) {
        return inspect(p.normalize(p.absolute(path)), source);
      }
    }
    return null;
  }

  /// Inspects an SDK root.
  AndroidSdk inspect(String root, String source) {
    List<String> sub(String name) {
      final d = Directory(p.join(root, name));
      if (!d.existsSync()) return const [];
      return [
        for (final e in d.listSync())
          if (e is Directory) p.basename(e.path),
      ]..sort(_compareVersions);
    }

    final platforms = <AndroidPlatform>[];
    for (final name in sub('platforms')) {
      final dir = p.join(root, 'platforms', name);
      final props = readProperties(p.join(dir, 'source.properties'));
      final level =
          ApiVersion.tryParse(props['AndroidVersion.ApiLevel']) ??
          ApiVersion.tryParse(name.replaceFirst('android-', ''));
      if (level == null) continue;
      platforms.add(
        AndroidPlatform(
          directory: dir,
          dirName: name,
          apiLevel: level,
          properties: props,
        ),
      );
    }
    platforms.sort();
    final cmdline = sub('cmdline-tools');
    final hasSdkManager =
        cmdline.any(
          (v) =>
              File(
                p.join(root, 'cmdline-tools', v, 'bin', 'sdkmanager'),
              ).existsSync() ||
              File(
                p.join(root, 'cmdline-tools', v, 'bin', 'sdkmanager.bat'),
              ).existsSync(),
        ) ||
        File(p.join(root, 'tools', 'bin', 'sdkmanager')).existsSync();
    return AndroidSdk(
      root: root,
      source: source,
      platforms: platforms,
      buildTools: sub('build-tools'),
      ndks: sub('ndk'),
      hasSdkManager: hasSdkManager,
      sourcePackages: sub('sources'),
    );
  }
}

/// Parses a Java-style `key=value` properties file (missing file → empty).
Map<String, String> readProperties(String path) {
  final f = File(path);
  if (!f.existsSync()) return const {};
  final out = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || t.startsWith('!')) continue;
    final i = t.indexOf('=');
    if (i <= 0) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}

int _compareVersions(String a, String b) {
  final pa = RegExp(r'\d+').allMatches(a).map((m) => int.parse(m[0]!)).toList();
  final pb = RegExp(r'\d+').allMatches(b).map((m) => int.parse(m[0]!)).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  final c = pa.length.compareTo(pb.length);
  return c != 0 ? c : a.compareTo(b);
}

/// Detected JDK.
final class JdkInfo {
  /// Creates JDK info.
  const JdkInfo(this.version, this.source);

  /// Version string from `java -version`.
  final String version;

  /// `JAVA_HOME` or `PATH`.
  final String source;

  /// Major version (e.g. 17), or null.
  int? get major {
    final m = RegExp(r'"(\d+)(?:\.(\d+))?').firstMatch(version);
    if (m == null) return null;
    final first = int.parse(m[1]!);
    return first == 1 && m[2] != null ? int.parse(m[2]!) : first;
  }
}

/// Runs `java -version` from `JAVA_HOME` or `PATH`. Fixed arguments only.
JdkInfo? detectJdk({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final javaHome = env['JAVA_HOME'];
  final exe = Platform.isWindows ? 'java.exe' : 'java';
  final candidates = <(String, String)>[
    if (javaHome != null && javaHome.isNotEmpty)
      (p.join(javaHome, 'bin', exe), 'JAVA_HOME'),
    ('java', 'PATH'),
  ];
  for (final (cmd, source) in candidates) {
    try {
      final r = Process.runSync(cmd, ['-version']);
      if (r.exitCode == 0) {
        final text = '${r.stderr}${r.stdout}'.split('\n').first.trim();
        return JdkInfo(text, source);
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}
