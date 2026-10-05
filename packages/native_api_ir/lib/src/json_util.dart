import 'dart:convert';

/// Maximum nesting depth accepted when decoding IR JSON.
const int maxJsonDepth = 64;

/// Encodes [value] as canonical JSON: map keys sorted recursively, two-space
/// indentation, trailing newline. Output is byte-stable for equal input.
String canonicalJson(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(_canonicalize(value, 0))}\n';

Object? _canonicalize(Object? value, int depth) {
  if (depth > maxJsonDepth) {
    throw const FormatException('JSON nesting too deep');
  }
  if (value is Map) {
    final keys = value.keys.map((k) => k as String).toList()..sort();
    return {for (final k in keys) k: _canonicalize(value[k], depth + 1)};
  }
  if (value is List) {
    return [for (final v in value) _canonicalize(v, depth + 1)];
  }
  return value;
}

/// Typed accessors that raise [FormatException] on malformed input.
extension JsonReader on Map<String, Object?> {
  /// Required string.
  String str(String key) {
    final v = this[key];
    if (v is String) return v;
    throw FormatException('Expected string at "$key", got ${_kind(v)}');
  }

  /// Optional string.
  String? strOrNull(String key) {
    final v = this[key];
    if (v == null || v is String) return v as String?;
    throw FormatException('Expected string at "$key", got ${_kind(v)}');
  }

  /// Optional int.
  int? intOrNull(String key) {
    final v = this[key];
    if (v == null || v is int) return v as int?;
    throw FormatException('Expected int at "$key", got ${_kind(v)}');
  }

  /// Boolean with default.
  bool boolOr(String key, bool fallback) {
    final v = this[key];
    if (v == null) return fallback;
    if (v is bool) return v;
    throw FormatException('Expected bool at "$key", got ${_kind(v)}');
  }

  /// Required object.
  Map<String, Object?> obj(String key) {
    final v = this[key];
    if (v is Map<String, Object?>) return v;
    throw FormatException('Expected object at "$key", got ${_kind(v)}');
  }

  /// Optional object.
  Map<String, Object?>? objOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is Map<String, Object?>) return v;
    throw FormatException('Expected object at "$key", got ${_kind(v)}');
  }

  /// List of objects decoded with [decode]; missing key yields empty list.
  List<T> list<T>(String key, T Function(Map<String, Object?>) decode) {
    final v = this[key];
    if (v == null) return const [];
    if (v is! List) {
      throw FormatException('Expected list at "$key", got ${_kind(v)}');
    }
    return [
      for (final e in v)
        if (e is Map<String, Object?>)
          decode(e)
        else
          throw FormatException('Expected object in "$key", got ${_kind(e)}'),
    ];
  }

  /// List of strings; missing key yields empty list.
  List<String> strings(String key) {
    final v = this[key];
    if (v == null) return const [];
    if (v is List && v.every((e) => e is String)) return v.cast<String>();
    throw FormatException('Expected list of strings at "$key"');
  }

  /// Enum value by `name`.
  T enumValue<T extends Enum>(String key, List<T> values, {T? fallback}) {
    final v = this[key];
    if (v == null && fallback != null) return fallback;
    for (final e in values) {
      if (e.name == v) return e;
    }
    throw FormatException('Unknown value "$v" at "$key"');
  }
}

String _kind(Object? v) => v == null ? 'null' : v.runtimeType.toString();
