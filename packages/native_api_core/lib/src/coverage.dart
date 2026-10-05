import 'dart:collection';

import 'package:native_api_ir/native_api_ir.dart';

/// Coverage statistics computed from an IR module. Every excluded symbol is
/// counted under the diagnostic code that explains it.
final class CoverageReport {
  CoverageReport._(this.module);

  /// Computes coverage for [module].
  factory CoverageReport.of(ApiModule module) =>
      CoverageReport._(module).._compute();

  /// The module.
  final ApiModule module;

  /// Discovered / generated counters by category.
  final discovered = SplayTreeMap<String, int>();

  /// Generated counters by category.
  final generated = SplayTreeMap<String, int>();

  /// Excluded symbol count by `CODE LABEL`.
  final excludedByReason = SplayTreeMap<String, int>();

  /// Partially supported symbols by reason.
  final partialByReason = SplayTreeMap<String, int>();

  void _inc(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;

  void _account(String category, ApiNode n) {
    _inc(discovered, category);
    if (n.isGeneratable) {
      _inc(generated, category);
      if (n.support == SupportStatus.partial) {
        for (final d in n.diagnostics) {
          _inc(partialByReason, d.code.toString());
        }
      }
    } else {
      final reasons = n.diagnostics.map((d) => d.code.toString()).toSet();
      if (reasons.isEmpty) {
        reasons.add(
          n.visibility == ApiVisibility.public
              ? DiagnosticCode.generationFailure.toString()
              : DiagnosticCode.nonSdkApi.toString(),
        );
      }
      for (final r in reasons) {
        _inc(excludedByReason, r);
      }
    }
  }

  void _compute() {
    for (final t in module.types) {
      _account(t.isInterface ? 'interfaces' : 'classes', t);
      final typeOk = t.isGeneratable;
      for (final m in t.methods) {
        if (!typeOk) continue;
        _account(m.isConstructor ? 'constructors' : 'methods', m);
      }
      for (final f in t.fields) {
        if (!typeOk) continue;
        _account(f.constantValue != null ? 'constants' : 'fields', f);
      }
      if (typeOk && t.isInterface) {
        _inc(discovered, 'callbacks');
        if (!t.diagnostics.any(
          (d) => d.code == DiagnosticCode.unsupportedCallback,
        )) {
          _inc(generated, 'callbacks');
        }
      }
      for (final n in [t, ...t.methods, ...t.fields]) {
        for (final a in n.annotations) {
          _inc(discovered, 'annotations');
          if (a.classification != AnnotationClassification.unsupported) {
            _inc(generated, 'annotations');
          }
        }
      }
    }
  }

  /// Percentage generated/discovered for [category], or null if none.
  double? percent(String category) {
    final d = discovered[category] ?? 0;
    if (d == 0) return null;
    return 100 * (generated[category] ?? 0) / d;
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'platform': module.platform.name,
    'sdkVersion': module.sdkVersion,
    'discovered': discovered,
    'generated': generated,
    'excludedByReason': excludedByReason,
    'partialByReason': partialByReason,
  };

  /// Text form.
  String toText() {
    final b = StringBuffer()
      ..writeln('${module.platform.name} SDK ${module.sdkVersion}')
      ..writeln();
    for (final k in discovered.keys) {
      b.writeln(
        '${'$k discovered:'.padRight(26)}${discovered[k]}   generated: ${generated[k] ?? 0}',
      );
    }
    b
      ..writeln()
      ..writeln('Coverage:');
    for (final k in discovered.keys) {
      final p = percent(k);
      if (p != null) b.writeln('  ${k.padRight(14)}${p.toStringAsFixed(1)}%');
    }
    if (excludedByReason.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Excluded (by reason):');
      excludedByReason.forEach((k, v) => b.writeln('  $k: $v'));
    }
    if (partialByReason.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Generated with approximation (by reason):');
      partialByReason.forEach((k, v) => b.writeln('  $k: $v'));
    }
    return b.toString().trimRight();
  }
}
