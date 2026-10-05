import 'package:native_api_ir/native_api_ir.dart';

import 'kotlin.dart';

/// Boxed primitives: suspend-function results the Dart target unboxes.
const _boxedPrimitives = {
  'java.lang.Integer',
  'java.lang.Long',
  'java.lang.Short',
  'java.lang.Byte',
  'java.lang.Character',
  'java.lang.Boolean',
  'java.lang.Double',
  'java.lang.Float',
};

/// Target-capability analysis for JVM-backed targets (Dart over
/// `package:jni`, TypeScript over JSI + JNI). Both targets call Java through
/// JNI and share the same constraints.
///
/// Returns a copy of [module] in which every symbol this target cannot (or
/// can only approximately) emit carries a support status and a reason
/// diagnostic. The emitter only emits generatable symbols; coverage and
/// `why-skipped` read the same annotated module, so they can never disagree.
///
/// [suspend] says whether the target can call Kotlin `suspend` functions
/// (Dart can, through `package:jni` continuations); otherwise they are
/// unsupported (`E004`).
ApiModule planJvmTarget(
  ApiModule module, {
  bool callbacks = true,
  bool suspend = false,
}) {
  final generated = {
    for (final t in module.types)
      if (t.isGeneratable && t.kind != TypeKind.annotationType) t.id,
  };

  Diagnostic d(
    DiagnosticCode c,
    String id,
    String msg, [
    Severity s = Severity.info,
  ]) => Diagnostic(c, msg, symbolId: id, severity: s);

  List<Diagnostic> outside(String id, Iterable<TypeRef> refs) {
    final missing = <String>{
      for (final r in refs)
        for (final n in r.referencedTypes)
          if (!generated.contains(n) &&
              n != 'java.lang.String' &&
              n != 'kotlin.Unit' &&
              !(suspend && _boxedPrimitives.contains(n)))
            n,
    }.toList()..sort();
    if (missing.isEmpty) return const [];
    return [
      d(
        DiagnosticCode.outsideClosure,
        id,
        'Outside the generation closure, exposed as JObject: ${missing.join(', ')}',
      ),
    ];
  }

  bool usesTypeVariables(Iterable<TypeRef> refs) {
    bool walk(TypeRef t) => switch (t) {
      TypeVariableRef() => true,
      DeclaredTypeRef(:final typeArguments) => typeArguments.any(walk),
      ArrayTypeRef(:final component) => walk(component),
      WildcardTypeRef(:final bound) => bound != null && walk(bound),
      PrimitiveTypeRef() || PointerTypeRef() || BlockTypeRef() => false,
    };
    return refs.any(walk);
  }

  (SupportStatus, List<Diagnostic>) decide(
    ApiNode n,
    List<Diagnostic> extra, {
    Diagnostic? unsupported,
  }) {
    if (!n.isGeneratable) return (n.support, n.diagnostics);
    if (unsupported != null) {
      return (SupportStatus.unsupported, [...n.diagnostics, unsupported]);
    }
    if (extra.isEmpty) return (n.support, n.diagnostics);
    return (SupportStatus.partial, [...n.diagnostics, ...extra]);
  }

  final types = <ApiType>[];
  for (final t in module.types) {
    if (!t.isGeneratable) {
      types.add(t);
      continue;
    }
    if (t.kind == TypeKind.annotationType) {
      types.add(
        t.copyWith(
          support: SupportStatus.unsupported,
          diagnostics: [
            ...t.diagnostics,
            d(
              DiagnosticCode.unsupportedType,
              t.id,
              'Annotation interfaces are metadata, not callable APIs; not bound',
              Severity.warning,
            ),
          ],
        ),
      );
      continue;
    }
    final typeDiags = <Diagnostic>[];
    if (t.typeParameters.isNotEmpty) {
      typeDiags.add(
        d(
          DiagnosticCode.unsupportedGeneric,
          t.id,
          'Type parameters ${t.typeParameters.map((p) => p.name).join(', ')} are erased to their bounds',
        ),
      );
    }
    if (t.isInterface && !callbacks) {
      typeDiags.add(
        d(
          DiagnosticCode.unsupportedCallback,
          t.id,
          'Callback generation disabled by configuration (generation.callbacks: false)',
        ),
      );
    }

    final fields = <ApiField>[];
    for (final f in t.fields) {
      final (support, diags) = decide(
        f,
        [
          ...outside(f.id, [f.type]),
        ],
        unsupported: f.modifiers.contains(Modifier.protected)
            ? d(
                DiagnosticCode.unsupportedType,
                f.id,
                'Protected member: accessible only to subclasses; generated bindings do not subclass Java classes',
                Severity.warning,
              )
            : null,
      );
      fields.add(
        ApiField(
          id: f.id,
          name: f.name,
          type: f.type,
          constantValue: f.constantValue,
          nativeDescriptor: f.nativeDescriptor,
          modifiers: f.modifiers,
          annotations: f.annotations,
          availability: f.availability,
          visibility: f.visibility,
          support: support,
          documentation: f.documentation,
          diagnostics: diags,
        ),
      );
    }

    final methods = <ApiMethod>[];
    for (final m in t.methods) {
      Diagnostic? blocked;
      if (m.modifiers.contains(Modifier.protected)) {
        blocked = d(
          DiagnosticCode.unsupportedType,
          m.id,
          'Protected member: accessible only to subclasses; generated bindings do not subclass Java classes',
          Severity.warning,
        );
      } else if (m.isConstructor && (t.isAbstract || t.isInterface)) {
        blocked = d(
          DiagnosticCode.unsupportedType,
          m.id,
          'Constructor of an abstract type cannot be invoked from bindings',
          Severity.warning,
        );
      } else if (m.isConstructor && t.kind == TypeKind.enumType) {
        blocked = d(
          DiagnosticCode.unsupportedType,
          m.id,
          'Enum constructors are not callable',
          Severity.warning,
        );
      }
      if (isSuspend(m) && !suspend && blocked == null) {
        blocked = d(
          DiagnosticCode.unsupportedCallback,
          m.id,
          'Kotlin suspend functions are not supported by this target yet',
          Severity.warning,
        );
      }
      final refs = isSuspend(m)
          ? [suspendResult(m), for (final p in suspendParameters(m)) p.type]
          : [m.returnType, for (final p in m.parameters) p.type];
      final extra = <Diagnostic>[
        if (m.typeParameters.isNotEmpty || usesTypeVariables(refs))
          d(
            DiagnosticCode.unsupportedGeneric,
            m.id,
            'Generic types are erased to their bounds in this version',
          ),
        ...outside(m.id, refs),
      ];
      final (support, diags) = decide(m, extra, unsupported: blocked);
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
          diagnostics: diags,
        ),
      );
    }
    types.add(
      t.copyWith(
        fields: fields,
        methods: methods,
        support: typeDiags.isEmpty ? t.support : SupportStatus.partial,
        diagnostics: [...t.diagnostics, ...typeDiags],
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
