import 'types.dart';

/// Builders for stable, deterministic symbol IDs.
///
/// Format (independent of generated file names):
/// * type:        `android.content.Intent`, nested `android.os.Handler$Callback`
/// * method:      `android.content.Intent#setData(android.net.Uri)`
/// * constructor: `android.content.Intent#<init>(java.lang.String)`
/// * field:       `android.content.Intent#ACTION_VIEW`
///
/// Parameter types are erased binary names; arrays use `[]`.
abstract final class SymbolIds {
  /// Constructor member name.
  static const constructorName = '<init>';

  /// ID of a type.
  static String type(String binaryName) => binaryName;

  /// ID of a method or constructor.
  static String method(
    String ownerId,
    String name,
    Iterable<TypeRef> parameterTypes, {
    Map<String, String> typeVariableErasures = const {},
  }) {
    final params = parameterTypes
        .map((t) => _erase(t, typeVariableErasures))
        .join(',');
    return '$ownerId#$name($params)';
  }

  /// ID of a field.
  static String field(String ownerId, String name) => '$ownerId#$name';

  /// Owner type ID of a member ID (identity for type IDs).
  static String ownerOf(String id) {
    final i = id.indexOf('#');
    return i < 0 ? id : id.substring(0, i);
  }

  /// Whether [id] denotes a member rather than a type.
  static bool isMember(String id) => id.contains('#');

  static String _erase(TypeRef t, Map<String, String> tv) => switch (t) {
    TypeVariableRef(:final name) => tv[name] ?? 'java.lang.Object',
    ArrayTypeRef(:final component) => '${_erase(component, tv)}[]',
    _ => t.erasedId,
  };
}
