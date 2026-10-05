/// Stable diagnostic codes. Documented in `docs/error-codes.md`.
///
/// Codes are part of the public contract: never renumber or reuse them.
enum DiagnosticCode {
  /// No SDK, platform or required SDK file was found.
  sdkNotFound('E001', 'SDK_NOT_FOUND'),

  /// A type or construct cannot be represented in the target language.
  unsupportedType('E002', 'UNSUPPORTED_TYPE'),

  /// A generic construct was erased or cannot be represented exactly.
  unsupportedGeneric('E003', 'UNSUPPORTED_GENERIC'),

  /// A callback type cannot be implemented from the target language.
  unsupportedCallback('E004', 'UNSUPPORTED_CALLBACK'),

  /// Apple private API.
  privateApi('E005', 'PRIVATE_API'),

  /// Android hidden / non-SDK API.
  nonSdkApi('E006', 'NON_SDK_API'),

  /// Licensing could not be classified confidently.
  licenseReviewRequired('E007', 'LICENSE_REVIEW_REQUIRED'),

  /// Malformed input (class file, signature, XML, IR JSON, header).
  invalidAst('E008', 'INVALID_AST'),

  /// The emitter could not produce valid code for a symbol.
  generationFailure('E009', 'GENERATION_FAILURE'),

  /// The runtime could not bind to a native symbol.
  runtimeBindingFailure('E010', 'RUNTIME_BINDING_FAILURE'),

  /// Native ABI / type-width mismatch.
  abiMismatch('E011', 'ABI_MISMATCH'),

  /// API is newer than the minimum supported platform version.
  availabilityMismatch('E012', 'AVAILABILITY_MISMATCH'),

  /// API carries a thread-confinement requirement.
  threadingConstraint('E013', 'THREADING_CONSTRAINT'),

  /// No documentation reference could be derived.
  documentationUnavailable('E014', 'DOCUMENTATION_UNAVAILABLE'),

  /// Requested target or platform is not implemented in this version.
  notImplemented('E015', 'NOT_IMPLEMENTED'),

  /// Referenced type is outside the generation closure (mapped opaquely).
  outsideClosure('E016', 'OUTSIDE_CLOSURE'),

  /// A write would escape the output directory.
  unsafePath('E017', 'UNSAFE_PATH'),

  /// Configuration is invalid.
  configInvalid('E018', 'CONFIG_INVALID');

  const DiagnosticCode(this.code, this.label);

  /// Short stable code such as `E006`.
  final String code;

  /// Stable upper-case label such as `NON_SDK_API`.
  final String label;

  /// Looks up a code by its short form (`E006`) or label (`NON_SDK_API`).
  static DiagnosticCode? tryParse(String value) {
    for (final c in values) {
      if (c.code == value || c.label == value) return c;
    }
    return null;
  }

  @override
  String toString() => '$code $label';
}

/// Severity of a [Diagnostic].
enum Severity {
  /// Informational; nothing was lost.
  info,

  /// Something was approximated or skipped.
  warning,

  /// An operation failed.
  error,
}

/// A structured diagnostic attached to a symbol, a module or a run.
final class Diagnostic implements Comparable<Diagnostic> {
  /// Creates a diagnostic.
  const Diagnostic(
    this.code,
    this.message, {
    this.severity = Severity.warning,
    this.symbolId,
  });

  /// Decodes from JSON produced by [toJson].
  factory Diagnostic.fromJson(Map<String, Object?> json) {
    final codeText = json['code'];
    final code = codeText is String ? DiagnosticCode.tryParse(codeText) : null;
    if (code == null) {
      throw FormatException('Unknown diagnostic code: $codeText');
    }
    final severityText = json['severity'];
    final severity = Severity.values.firstWhere(
      (s) => s.name == severityText,
      orElse: () => throw FormatException('Unknown severity: $severityText'),
    );
    final message = json['message'];
    if (message is! String) {
      throw const FormatException('Diagnostic.message must be a string');
    }
    final symbolId = json['symbolId'];
    if (symbolId != null && symbolId is! String) {
      throw const FormatException('Diagnostic.symbolId must be a string');
    }
    return Diagnostic(
      code,
      message,
      severity: severity,
      symbolId: symbolId as String?,
    );
  }

  /// Stable code.
  final DiagnosticCode code;

  /// Human-readable message. Must be deterministic (no paths, no times).
  final String message;

  /// Severity.
  final Severity severity;

  /// Stable symbol ID the diagnostic refers to, if any.
  final String? symbolId;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'code': code.code,
    'label': code.label,
    'severity': severity.name,
    'message': message,
    if (symbolId != null) 'symbolId': symbolId,
  };

  @override
  int compareTo(Diagnostic other) {
    final a = (symbolId ?? '').compareTo(other.symbolId ?? '');
    if (a != 0) return a;
    final b = code.code.compareTo(other.code.code);
    if (b != 0) return b;
    return message.compareTo(other.message);
  }

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.code == code &&
      other.message == message &&
      other.severity == severity &&
      other.symbolId == symbolId;

  @override
  int get hashCode => Object.hash(code, message, severity, symbolId);

  @override
  String toString() =>
      '${severity.name.toUpperCase()} ${code.code} ${code.label}'
      '${symbolId == null ? '' : ' [$symbolId]'}: $message';
}
