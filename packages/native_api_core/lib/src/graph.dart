import 'dart:collection';

import 'package:native_api_ir/native_api_ir.dart';

/// Binary names of types referenced by [type]'s public signatures:
/// superclass, interfaces, field types, parameter/return/throws types and
/// type-parameter bounds. Only generatable members are considered.
Set<String> referencedTypeIds(ApiType type) {
  final out = SplayTreeSet<String>();
  void add(TypeRef? t) {
    if (t != null) out.addAll(t.referencedTypes);
  }

  add(type.superClass);
  type.interfaces.forEach(add);
  for (final tp in type.typeParameters) {
    tp.bounds.forEach(add);
  }
  for (final f in type.fields.where((f) => f.isGeneratable)) {
    add(f.type);
  }
  for (final m in type.methods.where((m) => m.isGeneratable)) {
    add(m.returnType);
    for (final p in m.parameters) {
      add(p.type);
    }
    m.throws.forEach(add);
    for (final tp in m.typeParameters) {
      tp.bounds.forEach(add);
    }
  }
  if (type.enclosingType != null) out.add(type.enclosingType!);
  out.remove(type.id);
  return out;
}

/// Breadth-first closure from [roots] following [neighbors] up to [maxDepth]
/// edges. Returns node → depth, iterated in deterministic (sorted) order.
SplayTreeMap<String, int> computeClosure(
  Iterable<String> roots,
  Iterable<String> Function(String id) neighbors, {
  required int maxDepth,
  int maxNodes = 100000,
}) {
  final depth = SplayTreeMap<String, int>();
  final queue = Queue<String>();
  for (final r in roots.toList()..sort()) {
    if (depth.putIfAbsent(r, () => 0) == 0) queue.add(r);
  }
  while (queue.isNotEmpty) {
    final id = queue.removeFirst();
    final d = depth[id]!;
    if (d >= maxDepth) continue;
    for (final n in neighbors(id).toList()..sort()) {
      if (depth.containsKey(n)) continue;
      if (depth.length >= maxNodes) {
        throw StateError('Dependency closure exceeds $maxNodes nodes');
      }
      depth[n] = d + 1;
      queue.add(n);
    }
  }
  return depth;
}

/// Renders a dependency tree (each node expanded once) as text:
///
/// ```text
/// android.content.Intent
///  ├─ android.net.Uri
///  └─ android.os.Bundle
/// ```
String renderTree(
  String root,
  Iterable<String> Function(String id) neighbors, {
  int maxDepth = 1,
}) {
  final buf = StringBuffer()..writeln(root);
  final expanded = <String>{root};
  void walk(String id, String prefix, int depth) {
    if (depth >= maxDepth) return;
    final kids = neighbors(id).toList()..sort();
    for (var i = 0; i < kids.length; i++) {
      final last = i == kids.length - 1;
      final again = !expanded.add(kids[i]);
      buf.writeln(
        '$prefix ${last ? '└─' : '├─'} ${kids[i]}${again ? ' (…)' : ''}',
      );
      if (!again) walk(kids[i], '$prefix ${last ? '  ' : '│ '}', depth + 1);
    }
  }

  walk(root, '', 0);
  return buf.toString().trimRight();
}

/// JSON form of a dependency graph restricted to [closure].
Map<String, Object?> graphJson(
  Map<String, int> closure,
  Iterable<String> Function(String id) neighbors,
) => {
  'nodes': [
    for (final e in closure.entries) {'id': e.key, 'depth': e.value},
  ],
  'edges': [
    for (final id in closure.keys)
      for (final n in neighbors(id).toList()..sort())
        if (closure.containsKey(n)) {'from': id, 'to': n},
  ],
};
