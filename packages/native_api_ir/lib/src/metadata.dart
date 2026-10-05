import 'json_util.dart';

/// Source platform of a symbol.
enum ApiPlatform {
  /// Android SDK (Java/Kotlin APIs).
  android,

  /// Apple platforms (iOS / iPadOS / macOS).
  apple,
}

/// Whether the symbol belongs to the platform's supported public surface.
enum ApiVisibility {
  /// Public, documented SDK API.
  public,

  /// Android API present in artifacts but not in the public API list.
  hiddenOrNonSdk,

  /// Apple private API.
  private,
}

/// Whether a generator may emit the symbol.
enum SupportStatus {
  /// Fully representable.
  supported,

  /// Representable with documented approximation (e.g. generic erasure).
  partial,

  /// Not emitted; at least one diagnostic explains why.
  unsupported,
}

/// Threading requirement. Unknown is [unspecified] — never "thread-safe".
enum Threading {
  /// No information.
  unspecified,

  /// Must be called on the main thread (`@MainThread`).
  mainThread,

  /// Must be called on the UI thread (`@UiThread`).
  uiThread,

  /// Must be called off the main thread (`@WorkerThread`).
  workerThread,

  /// Documented as callable from any thread (`@AnyThread`).
  anyThread,

  /// Swift actor-isolated (planned for Apple).
  actorIsolated,

  /// Bound to a dispatch queue (planned for Apple).
  dispatchQueue,
}

/// Asynchrony model of a method.
enum AsyncKind {
  /// Synchronous call.
  none,

  /// Result delivered through a callback/listener parameter.
  callback,

  /// Returns a future-like object.
  future,

  /// Kotlin `suspend` function.
  suspend,

  /// Objective-C completion handler (planned).
  completionHandler,
}

/// How an annotation is used by generators (TRD §11).
enum AnnotationClassification {
  /// Changes generated semantics (nullability, availability, threading, ...).
  semantic,

  /// Preserved as metadata in generated docs (permissions, ranges, IntDef).
  preservable,

  /// Retained at runtime by the platform.
  runtime,

  /// Compile-time only, no generated effect.
  compileTime,

  /// Purely documentation.
  documentationOnly,

  /// Not understood; kept raw for diagnostics.
  unsupported,
}

/// A platform version: Android API level (`36`, `36.1`) or OS version.
final class ApiVersion implements Comparable<ApiVersion> {
  /// Creates a version.
  const ApiVersion(this.major, [this.minor = 0, this.patch = 0])
    : assert(major >= 0 && minor >= 0 && patch >= 0);

  /// Parses `36`, `36.1`, `17.0.1`. Throws [FormatException] otherwise.
  factory ApiVersion.parse(String text) {
    final m = RegExp(
      r'^(\d{1,6})(?:\.(\d{1,6}))?(?:\.(\d{1,6}))?$',
    ).firstMatch(text.trim());
    if (m == null) throw FormatException('Invalid version "$text"');
    return ApiVersion(
      int.parse(m[1]!),
      m[2] == null ? 0 : int.parse(m[2]!),
      m[3] == null ? 0 : int.parse(m[3]!),
    );
  }

  /// Parses or returns null.
  static ApiVersion? tryParse(String? text) {
    if (text == null) return null;
    try {
      return ApiVersion.parse(text);
    } on FormatException {
      return null;
    }
  }

  /// Major version (Android `SDK_INT`).
  final int major;

  /// Minor version (Android minor SDK release), 0 if none.
  final int minor;

  /// Patch version (Apple), 0 if none.
  final int patch;

  @override
  int compareTo(ApiVersion o) => major != o.major
      ? major.compareTo(o.major)
      : minor != o.minor
      ? minor.compareTo(o.minor)
      : patch.compareTo(o.patch);

  /// `<=`.
  bool operator <=(ApiVersion o) => compareTo(o) <= 0;

  /// `<`.
  bool operator <(ApiVersion o) => compareTo(o) < 0;

  /// `>`.
  bool operator >(ApiVersion o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) =>
      other is ApiVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => patch != 0
      ? '$major.$minor.$patch'
      : minor == 0
      ? '$major'
      : '$major.$minor';
}

/// Availability on one Apple platform (`ios`, `macos`, `maccatalyst`, ...).
final class PlatformAvailability {
  /// Creates platform availability.
  const PlatformAvailability({
    this.introduced,
    this.deprecated,
    this.obsoleted,
    this.unavailable = false,
  });

  /// Decodes from JSON.
  factory PlatformAvailability.fromJson(Map<String, Object?> json) {
    ApiVersion? v(String k) => ApiVersion.tryParse(json.strOrNull(k));
    return PlatformAvailability(
      introduced: v('introduced'),
      deprecated: v('deprecated'),
      obsoleted: v('obsoleted'),
      unavailable: json.boolOr('unavailable', false),
    );
  }

  /// Introduced in.
  final ApiVersion? introduced;

  /// Deprecated in.
  final ApiVersion? deprecated;

  /// Obsoleted (removed) in.
  final ApiVersion? obsoleted;

  /// Unconditionally unavailable on this platform.
  final bool unavailable;

  /// JSON form.
  Map<String, Object?> toJson() => {
    if (introduced != null) 'introduced': '$introduced',
    if (deprecated != null) 'deprecated': '$deprecated',
    if (obsoleted != null) 'obsoleted': '$obsoleted',
    if (unavailable) 'unavailable': true,
  };

  @override
  bool operator ==(Object other) =>
      other is PlatformAvailability &&
      other.introduced == introduced &&
      other.deprecated == deprecated &&
      other.obsoleted == obsoleted &&
      other.unavailable == unavailable;

  @override
  int get hashCode =>
      Object.hash(introduced, deprecated, obsoleted, unavailable);
}

/// Lifecycle versions of a symbol on its platform.
final class Availability {
  /// Creates availability metadata.
  const Availability({
    this.introduced,
    this.deprecated,
    this.removed,
    this.sdkExtensions,
    this.platforms = const {},
  });

  /// Decodes from JSON.
  factory Availability.fromJson(Map<String, Object?> json) {
    ApiVersion? v(String k) {
      final s = json.strOrNull(k);
      return s == null ? null : ApiVersion.parse(s);
    }

    return Availability(
      introduced: v('introduced'),
      deprecated: v('deprecated'),
      removed: v('removed'),
      sdkExtensions: json.strOrNull('sdkExtensions'),
      platforms: {
        for (final e in (json.objOrNull('platforms') ?? const {}).entries)
          e.key: PlatformAvailability.fromJson(
            e.value is Map<String, Object?>
                ? e.value! as Map<String, Object?>
                : throw const FormatException('platforms entries are objects'),
          ),
      },
    );
  }

  /// Unknown availability.
  static const unknown = Availability();

  /// Version the symbol was introduced in.
  final ApiVersion? introduced;

  /// Version the symbol was deprecated in.
  final ApiVersion? deprecated;

  /// Version the symbol was removed in.
  final ApiVersion? removed;

  /// Raw SDK-extension availability (`api-versions.xml` `sdks` attribute).
  final String? sdkExtensions;

  /// Apple: availability per platform (`ios`, `macos`, ...). Empty for Android.
  final Map<String, PlatformAvailability> platforms;

  /// Whether the symbol is deprecated at or before [version].
  bool isDeprecatedAt(ApiVersion version) =>
      deprecated != null && deprecated! <= version;

  /// Whether the symbol exists at [version].
  bool isAvailableAt(ApiVersion version) =>
      (introduced == null || introduced! <= version) &&
      (removed == null || removed! > version);

  /// JSON form (versions as strings so `36.1` is exact).
  Map<String, Object?> toJson() => {
    if (introduced != null) 'introduced': '$introduced',
    if (deprecated != null) 'deprecated': '$deprecated',
    if (removed != null) 'removed': '$removed',
    if (sdkExtensions != null) 'sdkExtensions': sdkExtensions,
    if (platforms.isNotEmpty)
      'platforms': {for (final e in platforms.entries) e.key: e.value.toJson()},
  };

  @override
  bool operator ==(Object other) =>
      other is Availability &&
      other.introduced == introduced &&
      other.deprecated == deprecated &&
      other.removed == removed &&
      other.sdkExtensions == sdkExtensions &&
      _platformsEq(other.platforms, platforms);

  @override
  int get hashCode =>
      Object.hash(introduced, deprecated, removed, sdkExtensions);

  @override
  String toString() =>
      'introduced=$introduced deprecated=$deprecated removed=$removed';
}

/// A raw annotation plus its classification.
final class ApiAnnotation implements Comparable<ApiAnnotation> {
  /// Creates an annotation record.
  const ApiAnnotation(
    this.type, {
    this.values = const {},
    this.classification = AnnotationClassification.unsupported,
    this.source = 'classfile',
  });

  /// Decodes from JSON.
  factory ApiAnnotation.fromJson(Map<String, Object?> json) {
    final raw = json.objOrNull('values') ?? const {};
    return ApiAnnotation(
      json.str('type'),
      values: {
        for (final e in raw.entries)
          e.key: e.value is String
              ? e.value as String
              : throw const FormatException('Annotation values are strings'),
      },
      classification: json.enumValue(
        'classification',
        AnnotationClassification.values,
      ),
      source: json.str('source'),
    );
  }

  /// Fully-qualified annotation type, e.g. `android.annotation.NonNull`.
  final String type;

  /// Element values rendered as stable strings.
  final Map<String, String> values;

  /// Classification.
  final AnnotationClassification classification;

  /// Where the annotation came from: `classfile`, `classfile-invisible`,
  /// `annotations.zip`.
  final String source;

  /// Simple name of [type].
  String get simpleName => type.substring(type.lastIndexOf('.') + 1);

  /// JSON form.
  Map<String, Object?> toJson() => {
    'type': type,
    if (values.isNotEmpty) 'values': values,
    'classification': classification.name,
    'source': source,
  };

  @override
  int compareTo(ApiAnnotation other) {
    final c = type.compareTo(other.type);
    return c != 0 ? c : source.compareTo(other.source);
  }

  @override
  bool operator ==(Object other) =>
      other is ApiAnnotation &&
      other.type == type &&
      other.source == source &&
      other.classification == classification &&
      _mapEq(other.values, values);

  @override
  int get hashCode => Object.hash(type, source, classification, values.length);
}

/// Where a symbol came from. Never contains absolute user paths.
final class Provenance {
  /// Creates provenance metadata.
  const Provenance({
    required this.platform,
    required this.sourceKind,
    required this.sdkVersion,
    this.localArtifact,
    this.artifactEntry,
    this.officialReference,
  });

  /// Decodes from JSON.
  factory Provenance.fromJson(Map<String, Object?> json) => Provenance(
    platform: json.enumValue('platform', ApiPlatform.values),
    sourceKind: json.str('sourceKind'),
    sdkVersion: json.str('sdkVersion'),
    localArtifact: json.strOrNull('localArtifact'),
    artifactEntry: json.strOrNull('artifactEntry'),
    officialReference: json.strOrNull('officialReference'),
  );

  /// Platform.
  final ApiPlatform platform;

  /// `sdk`, `api-versions`, `annotations`, `fixture`, `headers`.
  final String sourceKind;

  /// SDK version, e.g. `36`.
  final String sdkVersion;

  /// File name of the local artifact (e.g. `android.jar`), not a path.
  final String? localArtifact;

  /// Entry inside the artifact (e.g. `android/content/Intent.class`).
  final String? artifactEntry;

  /// URL of the official reference page.
  final String? officialReference;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'platform': platform.name,
    'sourceKind': sourceKind,
    'sdkVersion': sdkVersion,
    if (localArtifact != null) 'localArtifact': localArtifact,
    if (artifactEntry != null) 'artifactEntry': artifactEntry,
    if (officialReference != null) 'officialReference': officialReference,
  };
}

/// Documentation metadata. Never contains copied third-party prose.
final class Documentation {
  /// Creates documentation metadata.
  const Documentation({this.summary, this.sourceType = 'none', this.reference});

  /// Decodes from JSON.
  factory Documentation.fromJson(Map<String, Object?> json) => Documentation(
    summary: json.strOrNull('summary'),
    sourceType: json.str('sourceType'),
    reference: json.strOrNull('reference'),
  );

  /// Project-authored summary, if any.
  final String? summary;

  /// `none`, `link`, `project-authored`.
  final String sourceType;

  /// Link to the official documentation page.
  final String? reference;

  /// JSON form.
  Map<String, Object?> toJson() => {
    if (summary != null) 'summary': summary,
    'sourceType': sourceType,
    if (reference != null) 'reference': reference,
  };
}

bool _platformsEq(
  Map<String, PlatformAvailability> a,
  Map<String, PlatformAvailability> b,
) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
