import 'dart:convert';

import 'package:native_api_ir/native_api_ir.dart';
import 'package:xml/xml_events.dart';

import 'classfile/byte_reader.dart';
import 'zip_reader.dart';

/// An external annotation from `annotations.zip`.
final class ExternalAnnotation {
  /// Creates an external annotation.
  const ExternalAnnotation(this.type, this.values);

  /// Annotation type, e.g. `androidx.annotation.RequiresPermission`.
  final String type;

  /// Values.
  final Map<String, String> values;
}

/// Lazily loaded index over `platforms/android-N/data/annotations.zip`
/// (IntelliJ external-annotation format, one `annotations.xml` per package).
///
/// Item keys are normalized to stable symbol IDs so they can be joined with
/// class-file data:
/// * `android.content.Intent` (type)
/// * `android.content.Intent#ACTION_VIEW` (field)
/// * `android.content.Intent#setData(android.net.Uri)` (method)
/// * `...#setData(android.net.Uri)@0` (parameter 0)
final class AnnotationsIndex {
  /// Creates an index over [zip]. [resolveClass] maps a source-style name
  /// (`android.os.Handler.Callback`) to a binary name or null.
  AnnotationsIndex(this._zip, this._resolveClass);

  /// Empty index (no annotations.zip available).
  AnnotationsIndex.empty() : _zip = null, _resolveClass = _none;

  static String? _none(String _) => null;

  final ZipReader? _zip;
  final String? Function(String sourceName) _resolveClass;
  final _loaded = <String, Map<String, List<ExternalAnnotation>>>{};

  /// Diagnostics produced while loading.
  final diagnostics = <Diagnostic>[];

  /// Annotations for [key] (see class docs) in [packageName].
  List<ExternalAnnotation> lookup(String packageName, String key) =>
      (_loaded[packageName] ??= _load(packageName))[key] ?? const [];

  Map<String, List<ExternalAnnotation>> _load(String pkg) {
    final zip = _zip;
    if (zip == null) return const {};
    final entry = '${pkg.replaceAll('.', '/')}/annotations.xml';
    final out = <String, List<ExternalAnnotation>>{};
    try {
      final bytes = zip.read(entry, maxBytes: 16 << 20);
      if (bytes == null) return out;
      String? key;
      String? annType;
      var values = <String, String>{};
      for (final e in parseEvents(utf8.decode(bytes, allowMalformed: true))) {
        if (e is XmlStartElementEvent) {
          String? attr(String n) {
            for (final a in e.attributes) {
              if (a.name == n) return a.value;
            }
            return null;
          }

          if (e.name == 'item') {
            key = _normalizeKey(attr('name') ?? '');
          } else if (e.name == 'annotation') {
            annType = attr('name');
            values = {};
            if (e.isSelfClosing && key != null && annType != null) {
              (out[key] ??= []).add(ExternalAnnotation(annType, const {}));
              annType = null;
            }
          } else if (e.name == 'val' && annType != null) {
            values[attr('name') ?? 'value'] = attr('val') ?? '';
          }
        } else if (e is XmlEndElementEvent) {
          if (e.name == 'annotation' && key != null && annType != null) {
            (out[key] ??= []).add(ExternalAnnotation(annType, values));
            annType = null;
          } else if (e.name == 'item') {
            key = null;
          }
        }
      }
    } on MalformedInputException catch (e) {
      diagnostics.add(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'annotations.zip $entry: ${e.message}',
        ),
      );
    } on Exception catch (e) {
      diagnostics.add(
        Diagnostic(DiagnosticCode.invalidAst, 'annotations.zip $entry: $e'),
      );
    }
    return out;
  }

  /// Converts an item name to a symbol key. Returns null if unparseable.
  String? _normalizeKey(String raw) {
    final name = raw.trim();
    final paren = name.indexOf('(');
    if (paren < 0) {
      // "<class>" or "<class> <field>"
      final sp = name.indexOf(' ');
      if (sp < 0) return _resolveClass(name);
      final cls = _resolveClass(name.substring(0, sp));
      return cls == null ? null : '$cls#${name.substring(sp + 1)}';
    }
    // "<class> <ret> <name>(<params>)[ <index>]" or "<class> <Name>(<params>)"
    final head = name.substring(0, paren);
    final close = name.lastIndexOf(')');
    if (close < paren) return null;
    final params = _splitTopLevel(name.substring(paren + 1, close));
    final tail = name.substring(close + 1).trim();
    final parts = _splitSpaces(head);
    if (parts.length < 2) return null;
    final cls = _resolveClass(parts.first);
    if (cls == null) return null;
    final simple = cls.substring(cls.lastIndexOf(RegExp(r'[.$]')) + 1);
    var member = parts.last;
    if (parts.length == 2 && member == simple) {
      member = SymbolIds.constructorName;
    }
    final erased = <String>[];
    for (final p in params) {
      final e = _erase(p);
      if (e == null) return null;
      erased.add(e);
    }
    final id = '$cls#$member(${erased.join(',')})';
    return tail.isEmpty ? id : '$id@$tail';
  }

  String? _erase(String type) {
    var t = type.trim();
    var dims = 0;
    if (t.endsWith('...')) {
      dims++;
      t = t.substring(0, t.length - 3);
    }
    t = _stripGenerics(t);
    while (t.endsWith('[]')) {
      dims++;
      t = t.substring(0, t.length - 2).trim();
    }
    const prims = {
      'boolean',
      'byte',
      'char',
      'short',
      'int',
      'long',
      'float',
      'double',
    };
    String? base;
    if (prims.contains(t)) {
      base = t;
    } else if (t.length == 1 || !t.contains('.')) {
      // Type variable: erasure is unknown here; Object is the common case.
      base = 'java.lang.Object';
    } else {
      base = _resolveClass(t);
    }
    if (base == null) return null;
    return base + '[]' * dims;
  }

  static String _stripGenerics(String t) {
    final b = StringBuffer();
    var depth = 0;
    for (final c in t.split('')) {
      if (c == '<') {
        depth++;
      } else if (c == '>') {
        depth--;
      } else if (depth == 0) {
        b.write(c);
      }
    }
    return b.toString().trim();
  }

  static List<String> _splitTopLevel(String s) {
    if (s.trim().isEmpty) return const [];
    final out = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '<') depth++;
      if (c == '>') depth--;
      if (c == ',' && depth == 0) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out;
  }

  static List<String> _splitSpaces(String s) {
    // Return types can contain generics with spaces: split at top level.
    final out = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '<') depth++;
      if (c == '>') depth--;
      if (c == ' ' && depth == 0) {
        if (i > start) out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    if (start < s.length) out.add(s.substring(start));
    return out;
  }
}
