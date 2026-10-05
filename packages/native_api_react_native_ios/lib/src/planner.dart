import 'package:native_api_ir/native_api_ir.dart';

/// Whether [t] is a Cocoa `NSError **` out-parameter (hidden from
/// TypeScript and turned into a thrown `NativeObjCError`).
bool isErrorOut(TypeRef t) =>
    t is PointerTypeRef &&
    t.pointee is DeclaredTypeRef &&
    (t.pointee as DeclaredTypeRef).name == 'Foundation.NSError';

/// Whether a block value type converts to and from JavaScript: primitives,
/// enums and objects (no structs, pointers, selectors or classes).
bool _blockValueOk(TypeRef t, Map<String, ApiType> byId) => switch (t) {
  PrimitiveTypeRef() => true,
  DeclaredTypeRef(:final name) =>
    name != 'objc.unsupported' &&
        name != 'objc.Class' &&
        name != 'objc.SEL' &&
        byId[name]?.kind != TypeKind.struct,
  _ => false,
};

/// Why block parameter [p] of [m] cannot be bound from JavaScript, or null.
/// `void` blocks are always delivered (synchronously on the JS thread,
/// otherwise posted to it, arguments retained); blocks returning a value
/// need a synchronous JS-thread call: `NS_NOESCAPE` on a member that is not
/// dispatched to the main thread.
String? blockUnsupported(
  ApiMethod m,
  ApiParameter p,
  Map<String, ApiType> byId,
) {
  final b = p.type;
  if (b is! BlockTypeRef) return null;
  if (![b.returnType, ...b.parameters].every((t) => _blockValueOk(t, byId))) {
    return 'Block `${p.name}` (${b.display}) has values that cannot be converted to JavaScript';
  }
  final isVoid =
      b.returnType is PrimitiveTypeRef &&
      (b.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
  if (isVoid) return null;
  final noescape = p.annotations.any((a) => a.type == 'objc.noescape');
  if (noescape && m.threading != Threading.mainThread) return null;
  return 'Block `${p.name}` (${b.display}) returns a value but may be invoked off the JS thread';
}

/// Target-capability analysis for TypeScript over the JSI/Objective-C
/// runtime: values must be convertible to JS (no raw pointers, blocks,
/// selectors or classes; structs only with numeric/boolean/struct fields).
ApiModule planTsObjC(ApiModule module) {
  final byId = {for (final t in module.types) t.id: t};
  final generated = {
    for (final t in module.types)
      if (t.isGeneratable) t.id,
  };

  final structOk = <String, bool>{};
  bool representableStruct(String id, [Set<String>? visiting]) {
    final cached = structOk[id];
    if (cached != null) return cached;
    final t = byId[id];
    if (t == null || t.kind != TypeKind.struct || !t.isGeneratable) {
      return structOk[id] = false;
    }
    final seen = visiting ?? <String>{};
    if (!seen.add(id)) return false;
    var ok = t.fields.isNotEmpty;
    for (final f in t.fields) {
      final ft = f.type;
      if (ft is PrimitiveTypeRef && ft.kind != PrimitiveKind.void_) continue;
      if (ft is DeclaredTypeRef) {
        final k = byId[ft.name]?.kind;
        if (k == TypeKind.enumType) continue;
        if (k == TypeKind.struct && representableStruct(ft.name, seen)) {
          continue;
        }
      }
      ok = false;
    }
    return structOk[id] = ok;
  }

  Diagnostic d(
    DiagnosticCode c,
    String id,
    String msg, [
    Severity s = Severity.warning,
  ]) => Diagnostic(c, msg, symbolId: id, severity: s);

  // Unsupported reason for a value type, or null.
  (DiagnosticCode, String)? unsupported(TypeRef t) {
    switch (t) {
      case BlockTypeRef():
        return (
          DiagnosticCode.unsupportedCallback,
          'Objective-C blocks are not supported by the React Native iOS target yet',
        );
      case ArrayTypeRef() || PointerTypeRef():
        return (
          DiagnosticCode.unsupportedType,
          'Raw C value ${t.display} cannot be passed to or from JavaScript',
        );
      case DeclaredTypeRef(:final name)
          when name == 'objc.unsupported' ||
              name == 'objc.Class' ||
              name == 'objc.SEL':
        return (
          DiagnosticCode.unsupportedType,
          'Unsupported type ${t.display}',
        );
      case DeclaredTypeRef(:final name)
          when byId[name]?.kind == TypeKind.struct &&
              !representableStruct(name):
        return (
          DiagnosticCode.unsupportedType,
          'Struct ${t.display} has fields that cannot be represented in JavaScript',
        );
      default:
        return null;
    }
  }

  final types = <ApiType>[];
  for (final t in module.types) {
    if (!t.isGeneratable) {
      types.add(t);
      continue;
    }
    final methods = <ApiMethod>[];
    for (final m in t.methods) {
      if (!m.isGeneratable) {
        methods.add(m);
        continue;
      }
      final extra = <Diagnostic>[];
      Diagnostic? blocked;
      if (m.isStatic && t.kind == TypeKind.protocol) {
        blocked = d(
          DiagnosticCode.unsupportedType,
          m.id,
          'Class members of protocols need a concrete class; call them on a conforming class',
        );
      }
      final params = [
        for (var i = 0; i < m.parameters.length; i++)
          if (!(i == m.parameters.length - 1 &&
              isErrorOut(m.parameters[i].type)))
            m.parameters[i].type,
      ];
      for (final p in m.parameters) {
        final why = blockUnsupported(m, p, byId);
        if (why != null) {
          blocked ??= d(DiagnosticCode.unsupportedCallback, m.id, why);
        }
      }
      for (final ty in [
        m.returnType,
        ...params.where((t) => t is! BlockTypeRef),
      ]) {
        final r = unsupported(ty);
        if (r != null) blocked ??= d(r.$1, m.id, r.$2);
        for (final n in ty.referencedTypes) {
          if (!n.startsWith('objc.') &&
              n != 'Foundation.NSString' &&
              !generated.contains(n)) {
            extra.add(
              d(
                DiagnosticCode.outsideClosure,
                m.id,
                'Outside the generation closure, exposed as ObjCObject: $n',
                Severity.info,
              ),
            );
          }
        }
      }
      final support = blocked != null
          ? SupportStatus.unsupported
          : extra.isEmpty
          ? m.support
          : SupportStatus.partial;
      methods.add(
        ApiMethod(
          id: m.id,
          name: m.name,
          kind: m.kind,
          returnType: m.returnType,
          parameters: m.parameters,
          typeParameters: m.typeParameters,
          throws: m.throws,
          threading: m.threading,
          permissions: m.permissions,
          asyncKind: m.asyncKind,
          nativeDescriptor: m.nativeDescriptor,
          modifiers: m.modifiers,
          annotations: m.annotations,
          availability: m.availability,
          visibility: m.visibility,
          support: support,
          documentation: m.documentation,
          diagnostics: [...m.diagnostics, ?blocked, ...extra.toSet()],
        ),
      );
    }
    final typeDiags = <Diagnostic>[
      if (t.kind == TypeKind.struct && !representableStruct(t.id))
        d(
          DiagnosticCode.unsupportedType,
          t.id,
          'Struct fields cannot be represented in JavaScript',
        ),
    ];
    types.add(
      t.copyWith(
        methods: methods,
        diagnostics: [...t.diagnostics, ...typeDiags],
        support: t.kind == TypeKind.struct && !representableStruct(t.id)
            ? SupportStatus.unsupported
            : typeDiags.isEmpty
            ? t.support
            : SupportStatus.partial,
      ),
    );
  }
  return ApiModule(
    platform: module.platform,
    sdkVersion: module.sdkVersion,
    sourceRevision: module.sourceRevision,
    generatorVersion: module.generatorVersion,
    types: types,
    diagnostics: module.diagnostics,
  );
}
