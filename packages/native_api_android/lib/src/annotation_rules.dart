import 'package:native_api_ir/native_api_ir.dart';

const _nonNull = {
  'android.annotation.NonNull',
  'androidx.annotation.NonNull',
  'androidx.annotation.RecentlyNonNull',
  'org.jetbrains.annotations.NotNull',
  'javax.annotation.Nonnull',
  'org.jspecify.annotations.NonNull',
};

const _nullable = {
  'android.annotation.Nullable',
  'androidx.annotation.Nullable',
  'androidx.annotation.RecentlyNullable',
  'org.jetbrains.annotations.Nullable',
  'javax.annotation.Nullable',
  'org.jspecify.annotations.Nullable',
};

const _threading = {
  'MainThread': Threading.mainThread,
  'UiThread': Threading.uiThread,
  'WorkerThread': Threading.workerThread,
  'AnyThread': Threading.anyThread,
  'BinderThread': Threading.workerThread,
};

const _preservable = {
  'RequiresPermission',
  'RequiresPermission.Read',
  'RequiresPermission.Write',
  'IntDef',
  'LongDef',
  'StringDef',
  'IntRange',
  'FloatRange',
  'Size',
  'ColorInt',
  'ColorLong',
  'Px',
  'Dimension',
  'FlaggedApi',
  'RequiresFeature',
  'SuppressAutoDoc',
  'BroadcastBehavior',
};

const _compileTime = {
  'SuppressLint',
  'CallSuper',
  'CheckResult',
  'Keep',
  'TargetApi',
  'SuppressWarnings',
  'Discouraged',
  'ChecksSdkIntAtLeast',
};

const _documentationOnly = {
  'SdkConstant',
  'Widget',
  'SystemService',
  'CallbackExecutor',
};

/// Classifies an annotation by fully-qualified type (TRD §11). Resource
/// annotations (`*Res`) are preservable metadata.
AnnotationClassification classifyAnnotation(
  String type, {
  required bool runtimeVisible,
}) {
  final simple = _simpleAfterPackage(type);
  if (_nonNull.contains(type) || _nullable.contains(type)) {
    return AnnotationClassification.semantic;
  }
  if (type == 'java.lang.Deprecated' || simple == 'RequiresApi') {
    return AnnotationClassification.semantic;
  }
  if (_threading.containsKey(simple)) return AnnotationClassification.semantic;
  if (_preservable.contains(simple) || simple.endsWith('Res')) {
    return AnnotationClassification.preservable;
  }
  if (_compileTime.contains(simple)) {
    return AnnotationClassification.compileTime;
  }
  if (_documentationOnly.contains(simple)) {
    return AnnotationClassification.documentationOnly;
  }
  if (runtimeVisible) return AnnotationClassification.runtime;
  return AnnotationClassification.unsupported;
}

/// Name after the package, keeping nesting (`RequiresPermission.Read`).
String _simpleAfterPackage(String type) {
  final parts = type.split('.');
  final i = parts.indexWhere(
    (s) => s.isNotEmpty && s[0].toUpperCase() == s[0] && s[0] != '_',
  );
  return i < 0 ? type : parts.sublist(i).join('.');
}

/// Nullability implied by a set of annotation types.
Nullability nullabilityOf(Iterable<ApiAnnotation> annotations) {
  for (final a in annotations) {
    if (_nonNull.contains(a.type)) return Nullability.nonnull;
    if (_nullable.contains(a.type)) return Nullability.nullable;
  }
  return Nullability.unknown;
}

/// Threading implied by annotations, or null.
Threading? threadingOf(Iterable<ApiAnnotation> annotations) {
  for (final a in annotations) {
    final t = _threading[_simpleAfterPackage(a.type)];
    if (t != null) return t;
  }
  return null;
}

/// Permissions named by `RequiresPermission` annotations.
List<String> permissionsOf(Iterable<ApiAnnotation> annotations) {
  final out = <String>{};
  for (final a in annotations) {
    if (!_simpleAfterPackage(a.type).startsWith('RequiresPermission')) continue;
    for (final key in const ['value', 'anyOf', 'allOf']) {
      final v = a.values[key];
      if (v == null || v.isEmpty) continue;
      final items = v.startsWith('{')
          ? v.substring(1, v.length - 1).split(',')
          : [v];
      for (final i in items) {
        final t = i.trim();
        if (t.isNotEmpty) out.add(key == 'value' ? t : '$key:$t');
      }
    }
  }
  return out.toList()..sort();
}
