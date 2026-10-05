import 'dart:convert';

import 'diagnostics.dart';
import 'metadata.dart';
import 'nodes.dart';
import 'symbol_id.dart';

/// Checks IR invariants. Returns diagnostics; never throws for bad content.
///
/// Invariants:
/// * symbol IDs are unique, and member IDs are prefixed by their owner ID;
/// * non-public symbols are never marked [SupportStatus.supported];
/// * every unsupported symbol carries at least one diagnostic (no silent drop);
/// * referenced nested types exist.
List<Diagnostic> validateModule(ApiModule module) {
  final out = <Diagnostic>[];
  final seen = <String>{};
  void unique(String id) {
    if (!seen.add(id)) {
      out.add(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'Duplicate symbol ID',
          severity: Severity.error,
          symbolId: id,
        ),
      );
    }
  }

  void checkNode(ApiNode n) {
    if (n.visibility != ApiVisibility.public &&
        n.support == SupportStatus.supported) {
      out.add(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'Non-public symbol must not be marked supported',
          severity: Severity.error,
          symbolId: n.id,
        ),
      );
    }
    if (n.support == SupportStatus.unsupported && n.diagnostics.isEmpty) {
      out.add(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'Unsupported symbol has no reason diagnostic',
          severity: Severity.error,
          symbolId: n.id,
        ),
      );
    }
  }

  for (final t in module.types) {
    unique(t.id);
    checkNode(t);
    for (final m in [...t.methods, ...t.fields]) {
      unique(m.id);
      checkNode(m);
      if (SymbolIds.ownerOf(m.id) != t.id) {
        out.add(
          Diagnostic(
            DiagnosticCode.invalidAst,
            'Member ID is not prefixed by owner ${t.id}',
            severity: Severity.error,
            symbolId: m.id,
          ),
        );
      }
    }
    for (final n in t.nestedTypes) {
      if (module.typeById(n) == null) {
        out.add(
          Diagnostic(
            DiagnosticCode.outsideClosure,
            'Nested type $n is not part of this module',
            severity: Severity.info,
            symbolId: t.id,
          ),
        );
      }
    }
  }
  return out..sort();
}

/// Parses IR JSON text safely. Malformed input yields an [IrDecodeResult]
/// with an `E008` diagnostic instead of an exception.
IrDecodeResult decodeModule(String text) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) {
      throw const FormatException('IR root must be an object');
    }
    return IrDecodeResult(ApiModule.fromJson(json), const []);
  } on FormatException catch (e) {
    return IrDecodeResult(null, [
      Diagnostic(
        DiagnosticCode.invalidAst,
        'Invalid IR JSON: ${e.message}',
        severity: Severity.error,
      ),
    ]);
  } on Error catch (e) {
    // Type errors from unexpected shapes and stack overflows from adversarial
    // nesting are converted to diagnostics as well.
    return IrDecodeResult(null, [
      Diagnostic(
        DiagnosticCode.invalidAst,
        'Invalid IR JSON: ${e.runtimeType}',
        severity: Severity.error,
      ),
    ]);
  }
}

/// Result of [decodeModule].
final class IrDecodeResult {
  /// Creates a result.
  const IrDecodeResult(this.module, this.diagnostics);

  /// Decoded module, or null on failure.
  final ApiModule? module;

  /// Diagnostics.
  final List<Diagnostic> diagnostics;
}
