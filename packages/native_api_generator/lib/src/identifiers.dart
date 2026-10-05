/// Language-specific identifier escaping (TRD §57).
abstract final class Identifiers {
  /// Dart reserved words: never valid as identifiers.
  static const dartReserved = {
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  /// Dart built-in identifiers: valid as member and parameter names, but not
  /// as type names or import prefixes.
  static const dartBuiltIn = {
    'abstract',
    'as',
    'covariant',
    'deferred',
    'dynamic',
    'export',
    'extension',
    'external',
    'factory',
    'Function',
    'get',
    'implements',
    'import',
    'interface',
    'late',
    'library',
    'mixin',
    'operator',
    'part',
    'required',
    'set',
    'static',
    'typedef',
  };

  /// `dart:core` names used unqualified by generated code; generated types
  /// must not shadow them.
  static const dartCoreUsed = {
    'Object',
    'String',
    'Map',
    'List',
    'Function',
    'StackTrace',
    'Iterable',
    'Type',
    'Never',
    'Null',
    'Record',
    'Enum',
    'int',
    'double',
    'bool',
    'num',
    'dynamic',
    'Future',
    'Stream',
    'Deprecated',
    'override',
  };

  /// Members of `Object`/`JObject` that generated members must not shadow
  /// with incompatible signatures.
  static const dartObjectMembers = {
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'reference',
    'release',
    'isReleased',
    'releasedBy',
    'jClass',
    'isA',
    'as',
    'isInstanceOf',
    'use',
    'type',
  };

  /// TypeScript reserved words (for the React Native target).
  static const typescriptReserved = {
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'false',
    'finally',
    'for',
    'function',
    'if',
    'import',
    'in',
    'instanceof',
    'new',
    'null',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typeof',
    'var',
    'void',
    'while',
    'with',
    'implements',
    'interface',
    'let',
    'package',
    'private',
    'protected',
    'public',
    'static',
    'yield',
    'any',
    'boolean',
    'number',
    'string',
    'symbol',
    'type',
    'from',
    'of',
    'arguments',
    'eval',
    'await',
    'async',
    'unknown',
    'never',
    'undefined',
  };

  static final _valid = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Escapes a Java identifier for use as a Dart member or parameter name.
  /// Reserved words get a trailing `$`; Java identifiers are already valid
  /// Dart identifiers otherwise (both allow `$` and `_`). Leading `_` would
  /// make the name library-private in Dart, so it is prefixed with `$`.
  static String dartMember(String name) {
    var n = name;
    if (!_valid.hasMatch(n)) n = n.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), r'$');
    if (n.startsWith('_')) n = '\$$n';
    if (dartReserved.contains(n) || dartObjectMembers.contains(n)) n = '$n\$';
    return n;
  }

  /// Escapes a Java simple type name for use as a Dart type name.
  static String dartType(String name) {
    var n = name.replaceAll(r'$', '_');
    if (n.startsWith('_')) n = '\$$n';
    if (dartReserved.contains(n) ||
        dartBuiltIn.contains(n) ||
        dartCoreUsed.contains(n)) {
      n = '$n\$';
    }
    return n;
  }

  /// Escapes for TypeScript: characters outside `[A-Za-z0-9_$]` become `$`
  /// (JVM names such as Kotlin's `<set-?>`), a leading digit gets `_`.
  static String typescript(String name) {
    var n = name;
    if (!_valid.hasMatch(n)) n = n.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), r'$');
    if (n.isEmpty || RegExp(r'^[0-9]').hasMatch(n)) n = '_$n';
    return typescriptReserved.contains(n) ? '${n}_' : n;
  }

  /// Dart library prefix for a Java package: `android.content` →
  /// `android_content`.
  static String packagePrefix(String pkg) =>
      pkg.isEmpty ? r'$default' : pkg.replaceAll('.', '_');
}
