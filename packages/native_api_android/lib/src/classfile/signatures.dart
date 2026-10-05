import 'package:native_api_ir/native_api_ir.dart';

import 'byte_reader.dart';

/// Max nesting of generic type arguments accepted.
const int maxSignatureDepth = 32;

/// Converts an internal name (`android/os/Handler$Callback`) to a binary
/// name with dots (`android.os.Handler$Callback`).
String binaryName(String internalName) => internalName.replaceAll('/', '.');

/// A parsed method signature.
final class MethodSignature {
  /// Creates a method signature.
  const MethodSignature(
    this.typeParameters,
    this.parameters,
    this.returnType,
    this.throws,
  );

  /// Method type parameters.
  final List<TypeParameter> typeParameters;

  /// Parameter types.
  final List<TypeRef> parameters;

  /// Return type.
  final TypeRef returnType;

  /// `^`-declared throws.
  final List<TypeRef> throws;
}

/// A parsed class signature.
final class ClassSignature {
  /// Creates a class signature.
  const ClassSignature(this.typeParameters, this.superClass, this.interfaces);

  /// Class type parameters.
  final List<TypeParameter> typeParameters;

  /// Superclass.
  final TypeRef superClass;

  /// Interfaces.
  final List<TypeRef> interfaces;
}

/// Parser for JVM descriptors and generic signatures (JVMS §4.3, §4.7.9.1).
final class SignatureParser {
  SignatureParser._(this._s);

  final String _s;
  int _i = 0;

  /// Parses a field descriptor or field signature.
  static TypeRef fieldType(String s) {
    final p = SignatureParser._(s);
    final t = p._referenceOrBase(0);
    p._end();
    return t;
  }

  /// Parses a method descriptor or method signature.
  static MethodSignature method(String s) {
    final p = SignatureParser._(s);
    final tps = p._typeParametersOpt();
    p._expect('(');
    final params = <TypeRef>[];
    while (p._peek != ')') {
      params.add(p._referenceOrBase(0));
    }
    p._expect(')');
    final ret = p._peek == 'V'
        ? (() {
            p._i++;
            return const PrimitiveTypeRef(PrimitiveKind.void_);
          })()
        : p._referenceOrBase(0);
    final throws = <TypeRef>[];
    while (p._i < s.length && p._peek == '^') {
      p._i++;
      throws.add(p._referenceOrBase(0));
    }
    p._end();
    return MethodSignature(tps, params, ret, throws);
  }

  /// Parses a class signature.
  static ClassSignature classSignature(String s) {
    final p = SignatureParser._(s);
    final tps = p._typeParametersOpt();
    final sup = p._classType(0);
    final ifaces = <TypeRef>[];
    while (p._i < s.length) {
      ifaces.add(p._classType(0));
    }
    return ClassSignature(tps, sup, ifaces);
  }

  String get _peek {
    if (_i >= _s.length) {
      throw MalformedInputException('unexpected end of signature "$_s"');
    }
    return _s[_i];
  }

  void _expect(String c) {
    if (_peek != c) {
      throw MalformedInputException('expected "$c" at $_i in "$_s"');
    }
    _i++;
  }

  void _end() {
    if (_i != _s.length) {
      throw MalformedInputException('trailing characters in "$_s"');
    }
  }

  List<TypeParameter> _typeParametersOpt() {
    if (_i >= _s.length || _peek != '<') return const [];
    _i++;
    final out = <TypeParameter>[];
    while (_peek != '>') {
      final name = _identifier(':');
      final bounds = <TypeRef>[];
      // Class bound (may be empty) followed by interface bounds.
      _expect(':');
      if (_peek != ':' && _peek != '>' && !_startsIdentifierBound()) {
        bounds.add(_referenceOrBase(1));
      }
      while (_i < _s.length && _peek == ':') {
        _i++;
        bounds.add(_referenceOrBase(1));
      }
      out.add(TypeParameter(name, bounds: bounds));
    }
    _i++;
    return out;
  }

  // After `Name:` an empty class bound is followed directly by `:` or by the
  // next parameter name; a bound starts with L, T or [.
  bool _startsIdentifierBound() {
    final c = _peek;
    return c != 'L' && c != 'T' && c != '[';
  }

  String _identifier(String stop) {
    final start = _i;
    while (_i < _s.length && !'$stop;<>.:/'.contains(_s[_i])) {
      _i++;
    }
    if (_i == start) throw MalformedInputException('empty identifier in "$_s"');
    return _s.substring(start, _i);
  }

  TypeRef _referenceOrBase(int depth) {
    if (depth > maxSignatureDepth) {
      throw MalformedInputException('signature nesting too deep');
    }
    final c = _peek;
    final prim = PrimitiveKind.byDescriptor(c);
    if (prim != null && prim != PrimitiveKind.void_) {
      _i++;
      return PrimitiveTypeRef(prim);
    }
    switch (c) {
      case 'L':
        return _classType(depth);
      case 'T':
        _i++;
        final name = _identifier(';');
        _expect(';');
        return TypeVariableRef(name);
      case '[':
        _i++;
        return ArrayTypeRef(_referenceOrBase(depth + 1));
      default:
        throw MalformedInputException('unexpected "$c" at $_i in "$_s"');
    }
  }

  TypeRef _classType(int depth) {
    _expect('L');
    final start = _i;
    while (!';<.'.contains(_peek)) {
      _i++;
    }
    var name = _s.substring(start, _i);
    if (name.isEmpty) throw MalformedInputException('empty class name');
    var args = _typeArgumentsOpt(depth);
    while (_peek == '.') {
      _i++;
      final inner = _identifier('');
      name = '$name\$$inner';
      args = _typeArgumentsOpt(depth);
    }
    _expect(';');
    return DeclaredTypeRef(binaryName(name), typeArguments: args);
  }

  List<TypeRef> _typeArgumentsOpt(int depth) {
    if (_peek != '<') return const [];
    _i++;
    final out = <TypeRef>[];
    while (_peek != '>') {
      switch (_peek) {
        case '*':
          _i++;
          out.add(const WildcardTypeRef(null));
        case '+':
          _i++;
          out.add(WildcardTypeRef(_referenceOrBase(depth + 1)));
        case '-':
          _i++;
          out.add(WildcardTypeRef(_referenceOrBase(depth + 1), isSuper: true));
        default:
          out.add(_referenceOrBase(depth + 1));
      }
    }
    _i++;
    return out;
  }
}
