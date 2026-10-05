import 'dart:typed_data';

import 'byte_reader.dart';

/// JVM access flags (JVMS §4.1, §4.5, §4.6, §4.7.6).
abstract final class AccessFlags {
  /// `ACC_PUBLIC`.
  static const public = 0x0001;

  /// `ACC_PRIVATE`.
  static const private = 0x0002;

  /// `ACC_PROTECTED`.
  static const protected = 0x0004;

  /// `ACC_STATIC`.
  static const static_ = 0x0008;

  /// `ACC_FINAL`.
  static const final_ = 0x0010;

  /// `ACC_SYNCHRONIZED` (methods).
  static const synchronized = 0x0020;

  /// `ACC_VOLATILE` (fields) / `ACC_BRIDGE` (methods).
  static const volatileOrBridge = 0x0040;

  /// `ACC_TRANSIENT` (fields) / `ACC_VARARGS` (methods).
  static const transientOrVarargs = 0x0080;

  /// `ACC_NATIVE`.
  static const native = 0x0100;

  /// `ACC_INTERFACE`.
  static const interface = 0x0200;

  /// `ACC_ABSTRACT`.
  static const abstract_ = 0x0400;

  /// `ACC_SYNTHETIC`.
  static const synthetic = 0x1000;

  /// `ACC_ANNOTATION`.
  static const annotation = 0x2000;

  /// `ACC_ENUM`.
  static const enum_ = 0x4000;
}

/// Limits that bound parser work on adversarial input.
abstract final class ClassFileLimits {
  /// Max class-file size.
  static const maxBytes = 64 << 20;

  /// Max annotation nesting.
  static const maxAnnotationDepth = 32;

  /// Max array elements in an annotation value.
  static const maxArrayValues = 4096;
}

/// A parsed annotation. Values are rendered to stable strings.
final class RawAnnotation {
  /// Creates an annotation.
  const RawAnnotation(this.descriptor, this.values);

  /// Type descriptor, e.g. `Landroid/annotation/NonNull;`.
  final String descriptor;

  /// Element name → rendered value.
  final Map<String, String> values;

  /// Binary name with dots, e.g. `android.annotation.NonNull`.
  String get typeName {
    if (descriptor.length > 2 &&
        descriptor.startsWith('L') &&
        descriptor.endsWith(';')) {
      return descriptor
          .substring(1, descriptor.length - 1)
          .replaceAll('/', '.')
          .replaceAll(r'$', '.');
    }
    return descriptor;
  }
}

/// A field or method.
final class MemberInfo {
  MemberInfo._(this.accessFlags, this.name, this.descriptor);

  /// Access flags.
  final int accessFlags;

  /// Name.
  final String name;

  /// Descriptor.
  final String descriptor;

  /// Generic signature attribute.
  String? signature;

  /// `Deprecated` attribute present.
  bool deprecated = false;

  /// Runtime-visible annotations.
  final visibleAnnotations = <RawAnnotation>[];

  /// Runtime-invisible (class-retention) annotations.
  final invisibleAnnotations = <RawAnnotation>[];

  /// Per-parameter annotations (visible + invisible merged), by index.
  final parameterAnnotations = <int, List<RawAnnotation>>{};

  /// Whether parameter annotations came from the invisible attribute.
  final parameterAnnotationsInvisible = <int, bool>{};

  /// Declared exceptions (internal names).
  final exceptions = <String>[];

  /// Constant value (fields): int, double, String; with [constantTag].
  Object? constantValue;

  /// Constant-pool tag of [constantValue].
  int? constantTag;

  /// Parameter names from `MethodParameters`.
  List<String?>? methodParameterNames;

  /// Local variable names by slot (from `LocalVariableTable`, start pc 0).
  final localVariableNames = <int, String>{};

  /// Whether the flag is set.
  bool has(int flag) => accessFlags & flag != 0;
}

/// An `InnerClasses` entry.
final class InnerClassEntry {
  /// Creates an entry.
  const InnerClassEntry(this.inner, this.outer, this.simpleName, this.flags);

  /// Inner class internal name.
  final String inner;

  /// Outer class internal name (null for local/anonymous).
  final String? outer;

  /// Simple name (null for anonymous).
  final String? simpleName;

  /// Inner class access flags (authoritative for nested visibility).
  final int flags;
}

/// A parsed class file. Contains only what API extraction needs.
final class ClassFile {
  ClassFile._();

  /// Parses [bytes]. Throws [MalformedInputException] on invalid input.
  factory ClassFile.parse(Uint8List bytes) {
    if (bytes.length > ClassFileLimits.maxBytes) {
      throw MalformedInputException('class file too large');
    }
    return _Parser(ByteReader(bytes)).parse();
  }

  /// Major version.
  late final int majorVersion;

  /// Access flags.
  late final int accessFlags;

  /// Internal name, e.g. `android/content/Intent`.
  late final String name;

  /// Superclass internal name (null for `java/lang/Object`, modules).
  String? superName;

  /// Interface internal names.
  final interfaces = <String>[];

  /// Fields.
  final fields = <MemberInfo>[];

  /// Methods.
  final methods = <MemberInfo>[];

  /// Generic signature attribute.
  String? signature;

  /// `Deprecated` attribute present.
  bool deprecated = false;

  /// Runtime-visible annotations.
  final visibleAnnotations = <RawAnnotation>[];

  /// Runtime-invisible annotations.
  final invisibleAnnotations = <RawAnnotation>[];

  /// `InnerClasses` entries.
  final innerClasses = <InnerClassEntry>[];

  /// Whether a `Record` attribute is present.
  bool isRecord = false;

  /// Whether the flag is set.
  bool has(int flag) => accessFlags & flag != 0;

  /// The `InnerClasses` entry describing this class itself, if nested.
  InnerClassEntry? get selfInnerEntry {
    for (final e in innerClasses) {
      if (e.inner == name) return e;
    }
    return null;
  }

  /// Effective access flags (inner-class flags when nested).
  int get effectiveFlags => selfInnerEntry?.flags ?? accessFlags;
}

class _Parser {
  _Parser(this.r);

  final ByteReader r;
  late final List<Object?> _cp;
  late final List<int> _tags;
  final _cf = ClassFile._();

  ClassFile parse() {
    if (r.u4() != 0xCAFEBABE) throw MalformedInputException('bad magic');
    r.u2();
    _cf.majorVersion = r.u2();
    if (_cf.majorVersion < 45 || _cf.majorVersion > 80) {
      throw MalformedInputException(
        'unsupported class version ${_cf.majorVersion}',
      );
    }
    _readConstantPool();
    _cf.accessFlags = r.u2();
    _cf.name = _className(r.u2());
    final superIdx = r.u2();
    _cf.superName = superIdx == 0 ? null : _className(superIdx);
    final ic = r.u2();
    for (var i = 0; i < ic; i++) {
      _cf.interfaces.add(_className(r.u2()));
    }
    final fc = r.u2();
    for (var i = 0; i < fc; i++) {
      _cf.fields.add(_member(isMethod: false));
    }
    final mc = r.u2();
    for (var i = 0; i < mc; i++) {
      _cf.methods.add(_member(isMethod: true));
    }
    final ac = r.u2();
    for (var i = 0; i < ac; i++) {
      final attrName = _utf8(r.u2());
      final len = r.u4();
      final end = r.offset + len;
      if (end > r.bytes.length) {
        throw MalformedInputException('attribute overflow');
      }
      switch (attrName) {
        case 'Signature':
          _cf.signature = _utf8(r.u2());
        case 'Deprecated':
          _cf.deprecated = true;
        case 'RuntimeVisibleAnnotations':
          _cf.visibleAnnotations.addAll(_annotations());
        case 'RuntimeInvisibleAnnotations':
          _cf.invisibleAnnotations.addAll(_annotations());
        case 'InnerClasses':
          final n = r.u2();
          for (var j = 0; j < n; j++) {
            final inner = r.u2();
            final outer = r.u2();
            final simple = r.u2();
            final flags = r.u2();
            _cf.innerClasses.add(
              InnerClassEntry(
                _className(inner),
                outer == 0 ? null : _className(outer),
                simple == 0 ? null : _utf8(simple),
                flags,
              ),
            );
          }
        case 'Record':
          _cf.isRecord = true;
      }
      r.offset = end;
    }
    return _cf;
  }

  void _readConstantPool() {
    final count = r.u2();
    if (count == 0) throw MalformedInputException('empty constant pool');
    _cp = List<Object?>.filled(count, null);
    _tags = List<int>.filled(count, 0);
    for (var i = 1; i < count; i++) {
      final tag = r.u1();
      _tags[i] = tag;
      switch (tag) {
        case 1: // Utf8
          _cp[i] = decodeModifiedUtf8(r.take(r.u2()));
        case 3: // Integer
          _cp[i] = r.s4();
        case 4: // Float
          _cp[i] = r.f4();
        case 5: // Long
          _cp[i] = r.s8();
          i++;
        case 6: // Double
          _cp[i] = r.f8();
          i++;
        case 7 ||
            8 ||
            16 ||
            19 ||
            20: // Class, String, MethodType, Module, Package
          _cp[i] = r.u2();
        case 9 || 10 || 11 || 12 || 17 || 18: // refs, NameAndType, Dynamic
          r.skip(4);
        case 15: // MethodHandle
          r.skip(3);
        default:
          throw MalformedInputException('bad constant pool tag $tag at $i');
      }
    }
  }

  String _utf8(int i) {
    if (i <= 0 || i >= _cp.length || _tags[i] != 1) {
      throw MalformedInputException('expected Utf8 at #$i');
    }
    return _cp[i]! as String;
  }

  String _className(int i) {
    if (i <= 0 || i >= _cp.length || _tags[i] != 7) {
      throw MalformedInputException('expected Class at #$i');
    }
    return _utf8(_cp[i]! as int);
  }

  MemberInfo _member({required bool isMethod}) {
    final m = MemberInfo._(r.u2(), _utf8(r.u2()), _utf8(r.u2()));
    final ac = r.u2();
    for (var i = 0; i < ac; i++) {
      final attrName = _utf8(r.u2());
      final len = r.u4();
      final end = r.offset + len;
      if (end > r.bytes.length) {
        throw MalformedInputException('attribute overflow');
      }
      switch (attrName) {
        case 'Signature':
          m.signature = _utf8(r.u2());
        case 'Deprecated':
          m.deprecated = true;
        case 'ConstantValue' when !isMethod:
          final idx = r.u2();
          if (idx <= 0 || idx >= _cp.length) {
            throw MalformedInputException('bad ConstantValue index');
          }
          m.constantTag = _tags[idx];
          m.constantValue = _tags[idx] == 8
              ? _utf8(_cp[idx]! as int)
              : _cp[idx];
        case 'Exceptions' when isMethod:
          final n = r.u2();
          for (var j = 0; j < n; j++) {
            m.exceptions.add(_className(r.u2()));
          }
        case 'RuntimeVisibleAnnotations':
          m.visibleAnnotations.addAll(_annotations());
        case 'RuntimeInvisibleAnnotations':
          m.invisibleAnnotations.addAll(_annotations());
        case 'RuntimeVisibleParameterAnnotations' ||
            'RuntimeInvisibleParameterAnnotations':
          final invisible = attrName.contains('Invisible');
          final n = r.u1();
          for (var p = 0; p < n; p++) {
            final anns = _annotations();
            (m.parameterAnnotations[p] ??= []).addAll(anns);
            if (invisible) m.parameterAnnotationsInvisible[p] = true;
          }
        case 'MethodParameters' when isMethod:
          final n = r.u1();
          m.methodParameterNames = [
            for (var p = 0; p < n; p++) _optUtf8(r.u2(), r.u2()),
          ];
        case 'Code' when isMethod:
          _code(m);
      }
      r.offset = end;
    }
    return m;
  }

  String? _optUtf8(int idx, int _) => idx == 0 ? null : _utf8(idx);

  void _code(MemberInfo m) {
    r.skip(4);
    final codeLen = r.u4();
    r.skip(codeLen);
    final excLen = r.u2();
    r.skip(excLen * 8);
    final ac = r.u2();
    for (var i = 0; i < ac; i++) {
      final attrName = _utf8(r.u2());
      final len = r.u4();
      final end = r.offset + len;
      if (end > r.bytes.length) {
        throw MalformedInputException('attribute overflow');
      }
      if (attrName == 'LocalVariableTable') {
        final n = r.u2();
        for (var j = 0; j < n; j++) {
          final startPc = r.u2();
          r.u2();
          final name = _utf8(r.u2());
          r.u2();
          final slot = r.u2();
          if (startPc == 0) m.localVariableNames.putIfAbsent(slot, () => name);
        }
      }
      r.offset = end;
    }
  }

  List<RawAnnotation> _annotations() {
    final n = r.u2();
    return [for (var i = 0; i < n; i++) _annotation(0)];
  }

  RawAnnotation _annotation(int depth) {
    if (depth > ClassFileLimits.maxAnnotationDepth) {
      throw MalformedInputException('annotation nesting too deep');
    }
    final type = _utf8(r.u2());
    final pairs = r.u2();
    final values = <String, String>{};
    for (var i = 0; i < pairs; i++) {
      final name = _utf8(r.u2());
      values[name] = _elementValue(depth + 1);
    }
    return RawAnnotation(type, values);
  }

  String _elementValue(int depth) {
    if (depth > ClassFileLimits.maxAnnotationDepth) {
      throw MalformedInputException('annotation nesting too deep');
    }
    final tag = String.fromCharCode(r.u1());
    switch (tag) {
      case 'B' || 'C' || 'I' || 'S' || 'Z' || 'J' || 'F' || 'D':
        final idx = r.u2();
        if (idx <= 0 || idx >= _cp.length) {
          throw MalformedInputException('bad const');
        }
        final v = _cp[idx];
        if (tag == 'Z') return v == 1 ? 'true' : 'false';
        return '$v';
      case 's':
        return _utf8(r.u2());
      case 'e':
        final type = _utf8(r.u2());
        final c = _utf8(r.u2());
        return '${_descToName(type)}.$c';
      case 'c':
        return _descToName(_utf8(r.u2()));
      case '@':
        final a = _annotation(depth + 1);
        return '@${a.typeName}';
      case '[':
        final n = r.u2();
        if (n > ClassFileLimits.maxArrayValues) {
          throw MalformedInputException('annotation array too large');
        }
        return '{${[for (var i = 0; i < n; i++) _elementValue(depth + 1)].join(', ')}}';
      default:
        throw MalformedInputException('bad element_value tag $tag');
    }
  }

  static String _descToName(String d) => d.startsWith('L') && d.endsWith(';')
      ? d.substring(1, d.length - 1).replaceAll('/', '.')
      : d;
}
