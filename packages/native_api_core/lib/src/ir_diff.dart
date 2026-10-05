import 'package:native_api_ir/native_api_ir.dart';

/// Categories reported by `diff` (TRD §40).
enum DiffKind {
  /// Symbol added.
  added,

  /// Symbol removed.
  removed,

  /// Newly deprecated.
  deprecated,

  /// Signature (return/field type, modifiers, throws) changed.
  signatureChanged,

  /// Availability metadata changed.
  availabilityChanged,

  /// Annotation set changed.
  annotationChanged,

  /// Documentation metadata changed.
  documentationChanged,

  /// Became unsupported / hidden.
  unsupportedNewlyDetected,
}

/// A single diff entry.
final class DiffEntry implements Comparable<DiffEntry> {
  /// Creates an entry.
  const DiffEntry(this.kind, this.symbolId, [this.detail]);

  /// Category.
  final DiffKind kind;

  /// Symbol ID.
  final String symbolId;

  /// Optional detail, e.g. `return type: int → long`.
  final String? detail;

  @override
  int compareTo(DiffEntry o) {
    final k = kind.index.compareTo(o.kind.index);
    return k != 0 ? k : symbolId.compareTo(o.symbolId);
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'symbolId': symbolId,
    if (detail != null) 'detail': detail,
  };
}

Map<String, ApiNode> _index(ApiModule m) => {
  for (final t in m.types) ...{
    t.id: t,
    for (final x in t.methods) x.id: x,
    for (final x in t.fields) x.id: x,
  },
};

String _sig(ApiNode n) => switch (n) {
  final ApiMethod m =>
    '${m.returnType.display} throws ${m.throws.map((t) => t.display).join(',')}',
  final ApiField f =>
    f.type.display + (f.constantValue == null ? '' : ' = ${f.constantValue}'),
  final ApiType t =>
    '${t.kind.name} extends ${t.superClass?.display} implements '
        '${(t.interfaces.map((i) => i.display).toList()..sort()).join(',')}',
};

String _anns(ApiNode n) =>
    (n.annotations.map((a) => a.type).toSet().toList()..sort()).join(',');

/// Computes a deterministic diff from [from] to [to] using machine-readable
/// signatures only (never documentation prose).
List<DiffEntry> diffModules(ApiModule from, ApiModule to) {
  final a = _index(from);
  final b = _index(to);
  final out = <DiffEntry>[];
  for (final id in b.keys) {
    if (!a.containsKey(id)) out.add(DiffEntry(DiffKind.added, id));
  }
  for (final id in a.keys) {
    final x = a[id]!;
    final y = b[id];
    if (y == null) {
      out.add(DiffEntry(DiffKind.removed, id));
      continue;
    }
    if (!x.isDeprecated && y.isDeprecated) {
      out.add(DiffEntry(DiffKind.deprecated, id));
    }
    final sx = _sig(x), sy = _sig(y);
    final mx = (x.modifiers.map((m) => m.jsonName).toList()..sort()).join(' ');
    final my = (y.modifiers.map((m) => m.jsonName).toList()..sort()).join(' ');
    if (sx != sy) {
      out.add(DiffEntry(DiffKind.signatureChanged, id, '$sx → $sy'));
    } else if (mx != my) {
      out.add(DiffEntry(DiffKind.signatureChanged, id, 'modifiers: $mx → $my'));
    }
    if (x.availability != y.availability) {
      out.add(
        DiffEntry(
          DiffKind.availabilityChanged,
          id,
          '${x.availability} → ${y.availability}',
        ),
      );
    }
    final ax = _anns(x), ay = _anns(y);
    if (ax != ay) {
      out.add(DiffEntry(DiffKind.annotationChanged, id, '[$ax] → [$ay]'));
    }
    if (x.documentation.reference != y.documentation.reference) {
      out.add(DiffEntry(DiffKind.documentationChanged, id));
    }
    if (x.isGeneratable && !y.isGeneratable) {
      out.add(DiffEntry(DiffKind.unsupportedNewlyDetected, id));
    }
  }
  return out..sort();
}

/// Renders a diff as text grouped by category.
String renderDiff(List<DiffEntry> entries) {
  final b = StringBuffer();
  for (final k in DiffKind.values) {
    final group = entries.where((e) => e.kind == k).toList();
    if (group.isEmpty) continue;
    b.writeln(_title(k));
    for (final e in group) {
      b.writeln(e.symbolId);
      if (e.detail != null) b.writeln('  ${e.detail}');
    }
    b.writeln();
  }
  return b.isEmpty ? 'No differences.' : b.toString().trimRight();
}

String _title(DiffKind k) => switch (k) {
  DiffKind.added => 'ADDED',
  DiffKind.removed => 'REMOVED',
  DiffKind.deprecated => 'DEPRECATED',
  DiffKind.signatureChanged => 'SIGNATURE CHANGED',
  DiffKind.availabilityChanged => 'AVAILABILITY CHANGED',
  DiffKind.annotationChanged => 'ANNOTATION CHANGED',
  DiffKind.documentationChanged => 'DOCUMENTATION METADATA CHANGED',
  DiffKind.unsupportedNewlyDetected => 'UNSUPPORTED NEWLY DETECTED',
};
