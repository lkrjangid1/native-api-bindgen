import 'dart:convert';
import 'dart:typed_data';

import 'classfile/byte_reader.dart';

/// Limits for decoding `kotlin.Metadata` (untrusted input).
abstract final class KotlinMetadataLimits {
  /// Max decoded `d1` bytes.
  static const maxBytes = 8 << 20;

  /// Max message nesting.
  static const maxDepth = 64;

  /// Max repeated elements per message.
  static const maxRepeated = 1 << 16;
}

/// A Kotlin type as recorded in metadata: class name (JVM internal form,
/// `kotlin/String`, nested `a/B.C`) or type parameter, nullability and
/// arguments. [className] is null for type parameters.
final class KotlinType {
  /// Creates a type.
  const KotlinType(this.className, this.nullable, this.arguments);

  /// Qualified class name, or null (type parameter / unknown).
  final String? className;

  /// Whether the type is marked nullable (`T?`).
  final bool nullable;

  /// Type arguments (null entries are star projections).
  final List<KotlinType?> arguments;

  @override
  String toString() =>
      '${className ?? '?'}${arguments.isEmpty ? '' : '<${arguments.map((a) => a ?? '*').join(', ')}>'}${nullable ? '?' : ''}';
}

/// A value parameter.
final class KotlinParameter {
  /// Creates a parameter.
  const KotlinParameter(this.name, this.type, {required this.hasDefault});

  /// Kotlin name.
  final String name;

  /// Type.
  final KotlinType type;

  /// Whether the parameter declares a default value.
  final bool hasDefault;
}

/// A function or constructor with its JVM signature.
final class KotlinFunction {
  /// Creates a function.
  const KotlinFunction({
    required this.name,
    required this.jvmName,
    required this.jvmDescriptor,
    required this.returnType,
    required this.parameters,
    required this.isSuspend,
    this.hasReceiver = false,
  });

  /// Kotlin name (`<init>` for constructors).
  final String name;

  /// JVM method name.
  final String jvmName;

  /// JVM descriptor, or null when it could not be derived.
  final String? jvmDescriptor;

  /// Return type (null for constructors).
  final KotlinType? returnType;

  /// Value parameters (no receiver, no continuation).
  final List<KotlinParameter> parameters;

  /// Whether the function is `suspend`.
  final bool isSuspend;

  /// Whether the function is an extension (JVM receiver parameter first).
  final bool hasReceiver;

  /// `name + descriptor` key.
  String? get key => jvmDescriptor == null ? null : '$jvmName$jvmDescriptor';
}

/// A property with its JVM accessors.
final class KotlinProperty {
  /// Creates a property.
  const KotlinProperty(
    this.name,
    this.type, {
    this.getter,
    this.setter,
    this.isVar = false,
  });

  /// Kotlin name.
  final String name;

  /// Type.
  final KotlinType type;

  /// `name + descriptor` of the getter, if any.
  final String? getter;

  /// `name + descriptor` of the setter, if any.
  final String? setter;

  /// `var` (mutable).
  final bool isVar;
}

/// Decoded `kotlin.Metadata` of a class or file facade (kinds 1 and 2).
final class KotlinMetadata {
  KotlinMetadata._(this.kind, this.functions, this.properties);

  /// Metadata kind: 1 class, 2 file facade, 3 synthetic class, 4 multi-file
  /// facade, 5 multi-file part.
  final int kind;

  /// Functions and constructors.
  final List<KotlinFunction> functions;

  /// Properties.
  final List<KotlinProperty> properties;

  /// Functions by `jvmName + descriptor`.
  late final Map<String, KotlinFunction> byJvmSignature = {
    for (final f in functions)
      if (f.key != null) f.key!: f,
  };

  /// Decodes the annotation values `k`, `d1`, `d2`. Returns null for kinds
  /// without declarations. Throws [MalformedInputException] on bad input.
  static KotlinMetadata? decode({
    required int kind,
    required List<String> d1,
    required List<String> d2,
  }) {
    if (kind != 1 && kind != 2 && kind != 5) return null;
    final bytes = _decodeBytes(d1);
    final r = _Proto(bytes);
    final tableLen = r.varint();
    final table = _StringTable.parse(_Proto(r.bytes(tableLen)), d2);
    final body = _Proto(r.bytes(r.remaining));
    return kind == 1
        ? _Decoder(table).classBody(body)
        : _Decoder(table).packageBody(body);
  }
}

// ---------------------------------------------------------------- encoding

/// `BitEncoding.decodeBytes`: UTF-8 mode (marker `\u0000`) maps each char to
/// one byte; the legacy mode packs 7-bit groups.
Uint8List _decodeBytes(List<String> data) {
  if (data.isNotEmpty && data.first.isNotEmpty && data.first[0] == '\u0000') {
    var n = 0;
    for (final s in data) {
      n += s.length;
    }
    if (n > KotlinMetadataLimits.maxBytes) {
      throw MalformedInputException('kotlin.Metadata d1 too large');
    }
    final out = Uint8List(n - 1);
    var i = 0;
    var first = true;
    for (final s in data) {
      for (var j = first ? 1 : 0; j < s.length; j++) {
        out[i++] = s.codeUnitAt(j) & 0xFF;
      }
      first = false;
    }
    return out;
  }
  // Legacy 8-to-7 encoding.
  final raw = <int>[];
  for (final s in data) {
    for (final c in s.codeUnits) {
      raw.add((c + 0x7F) & 0x7F); // addModuloByte(0x7F)
      if (raw.length > KotlinMetadataLimits.maxBytes) {
        throw MalformedInputException('kotlin.Metadata d1 too large');
      }
    }
  }
  final out = Uint8List(raw.length * 7 ~/ 8);
  var bit = 0;
  var idx = 0;
  for (var i = 0; i < out.length; i++) {
    final lo = (raw[idx] & 0xFF) >> bit;
    idx++;
    final hi = (raw[idx] & ((1 << (bit + 1)) - 1)) << (7 - bit);
    out[i] = (lo + hi) & 0xFF;
    if (bit == 6) {
      bit = 0;
      idx++;
    } else {
      bit++;
    }
  }
  return out;
}

/// Minimal protobuf wire reader (varint, length-delimited, skip).
final class _Proto {
  _Proto(this._b);

  final Uint8List _b;
  int _o = 0;

  bool get atEnd => _o >= _b.length;
  int get remaining => _b.length - _o;

  int varint() {
    var result = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (_o >= _b.length) throw MalformedInputException('truncated varint');
      final b = _b[_o++];
      result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return result;
    }
    throw MalformedInputException('varint too long');
  }

  Uint8List bytes(int n) {
    if (n < 0 || n > remaining) {
      throw MalformedInputException('length out of range');
    }
    final v = Uint8List.sublistView(_b, _o, _o + n);
    _o += n;
    return v;
  }

  /// Next tag as (field, wireType), or null at end.
  (int, int)? tag() {
    if (atEnd) return null;
    final t = varint();
    return (t >> 3, t & 7);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        bytes(8);
      case 2:
        bytes(varint());
      case 5:
        bytes(4);
      default:
        throw MalformedInputException('unsupported wire type $wire');
    }
  }

  _Proto message() => _Proto(bytes(varint()));

  /// Packed or single int32 values for a repeated field.
  List<int> ints(int wire) {
    if (wire == 0) return [varint()];
    final p = message();
    return [for (; !p.atEnd;) p.varint()];
  }
}

/// `JvmProtoBuf.StringTableTypes` applied to `d2`.
final class _StringTable {
  _StringTable(this._strings);

  final List<String> _strings;

  static _StringTable parse(_Proto p, List<String> d2) {
    final records = <_Record>[];
    final out = <String>[];
    // Record i (expanded by `range`) describes string i; its text is the
    // record's own string, a predefined string, or d2[i].
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (field, wire) = t;
      if (field == 1 && wire == 2) {
        records.add(_Record.parse(p.message()));
      } else {
        p.skip(wire);
      }
    }
    var i = 0;
    for (final r in records) {
      for (var k = 0; k < r.range; k++) {
        out.add(r.apply(i < d2.length ? d2[i] : null));
        i++;
        if (i > KotlinMetadataLimits.maxRepeated) {
          throw MalformedInputException('string table too large');
        }
      }
    }
    while (i < d2.length) {
      out.add(d2[i++]);
    }
    return _StringTable(out);
  }

  String get(int i) {
    if (i < 0 || i >= _strings.length) {
      throw MalformedInputException('string index $i out of range');
    }
    return _strings[i];
  }
}

final class _Record {
  int range = 1;
  int operation = 0; // NONE, INTERNAL_TO_CLASS_ID, DESC_TO_CLASS_ID
  int? predefined;
  String? string;
  List<int> substring = const [];
  List<int> replaceChar = const [];

  static _Record parse(_Proto p) {
    final r = _Record();
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 1 when w == 0:
          r.range = p.varint();
          if (r.range < 0 || r.range > KotlinMetadataLimits.maxRepeated) {
            throw MalformedInputException('bad string range');
          }
        case 2 when w == 0:
          r.predefined = p.varint();
        case 3 when w == 0:
          r.operation = p.varint();
        case 4:
          r.substring = p.ints(w);
        case 5:
          r.replaceChar = p.ints(w);
        case 6 when w == 2:
          r.string = utf8.decode(p.bytes(p.varint()), allowMalformed: true);
        default:
          p.skip(w);
      }
    }
    return r;
  }

  String apply(String? raw) {
    final pre = predefined;
    var s =
        string ??
        (pre != null && pre >= 0 && pre < _predefinedStrings.length
            ? _predefinedStrings[pre]
            : raw) ??
        '';
    if (substring.length >= 2) {
      final a = substring[0], b = substring[1];
      if (a >= 0 && a <= b && b <= s.length) s = s.substring(a, b);
    }
    if (replaceChar.length >= 2) {
      s = s.replaceAll(
        String.fromCharCode(replaceChar[0]),
        String.fromCharCode(replaceChar[1]),
      );
    }
    switch (operation) {
      case 1: // INTERNAL_TO_CLASS_ID
        s = s.replaceAll(r'$', '.');
      case 2: // DESC_TO_CLASS_ID
        if (s.length >= 2) s = s.substring(1, s.length - 1);
        s = s.replaceAll(r'$', '.');
    }
    return s;
  }
}

/// `JvmNameResolverBase.PREDEFINED_STRINGS`.
const _predefinedStrings = [
  'kotlin/Any',
  'kotlin/Nothing',
  'kotlin/Unit',
  'kotlin/Throwable',
  'kotlin/Number',
  'kotlin/Byte',
  'kotlin/Double',
  'kotlin/Float',
  'kotlin/Int',
  'kotlin/Long',
  'kotlin/Short',
  'kotlin/Boolean',
  'kotlin/Char',
  'kotlin/CharSequence',
  'kotlin/String',
  'kotlin/Comparable',
  'kotlin/Enum',
  'kotlin/Array',
  'kotlin/ByteArray',
  'kotlin/DoubleArray',
  'kotlin/FloatArray',
  'kotlin/IntArray',
  'kotlin/LongArray',
  'kotlin/ShortArray',
  'kotlin/BooleanArray',
  'kotlin/CharArray',
  'kotlin/Cloneable',
  'kotlin/Annotation',
  'kotlin/collections/Iterable',
  'kotlin/collections/MutableIterable',
  'kotlin/collections/Collection',
  'kotlin/collections/MutableCollection',
  'kotlin/collections/List',
  'kotlin/collections/MutableList',
  'kotlin/collections/Set',
  'kotlin/collections/MutableSet',
  'kotlin/collections/Map',
  'kotlin/collections/MutableMap',
  'kotlin/collections/Map.Entry',
  'kotlin/collections/MutableMap.MutableEntry',
  'kotlin/collections/Iterator',
  'kotlin/collections/MutableIterator',
  'kotlin/collections/ListIterator',
  'kotlin/collections/MutableListIterator',
];

// ------------------------------------------------------------------ decoder

final class _RawType {
  int? className;
  int? typeParameter;
  bool nullable = false;
  final args = <(int, _RawType?, int?)>[]; // (projection, type, typeId)
}

final class _Decoder {
  _Decoder(this.table);

  final _StringTable table;
  List<_RawType> _typeTable = const [];

  KotlinMetadata classBody(_Proto p) {
    final fns = <_Proto>[];
    final ctors = <_Proto>[];
    final props = <_Proto>[];
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 8 when w == 2:
          ctors.add(p.message());
        case 9 when w == 2:
          fns.add(p.message());
        case 10 when w == 2:
          props.add(p.message());
        case 30 when w == 2:
          _typeTable = _parseTypeTable(p.message());
        default:
          p.skip(w);
      }
      if (fns.length + ctors.length + props.length >
          KotlinMetadataLimits.maxRepeated) {
        throw MalformedInputException('too many declarations');
      }
    }
    return KotlinMetadata._(
      1,
      [
        for (final c in ctors) _constructor(c),
        for (final f in fns) _function(f),
      ],
      [for (final x in props) _property(x)],
    );
  }

  KotlinMetadata packageBody(_Proto p) {
    final fns = <_Proto>[];
    final props = <_Proto>[];
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 3 when w == 2:
          fns.add(p.message());
        case 4 when w == 2:
          props.add(p.message());
        case 30 when w == 2:
          _typeTable = _parseTypeTable(p.message());
        default:
          p.skip(w);
      }
    }
    return KotlinMetadata._(
      2,
      [for (final f in fns) _function(f)],
      [for (final x in props) _property(x)],
    );
  }

  List<_RawType> _parseTypeTable(_Proto p) {
    final out = <_RawType>[];
    var firstNullable = -1;
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      if (f == 1 && w == 2) {
        out.add(_type(p.message(), 0));
      } else if (f == 2 && w == 0) {
        firstNullable = p.varint();
      } else {
        p.skip(w);
      }
    }
    if (firstNullable >= 0) {
      for (var i = firstNullable; i < out.length; i++) {
        out[i].nullable = true;
      }
    }
    return out;
  }

  _RawType _type(_Proto p, int depth) {
    if (depth > KotlinMetadataLimits.maxDepth) {
      throw MalformedInputException('type nesting too deep');
    }
    final r = _RawType();
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 2 when w == 2:
          final a = p.message();
          var projection = 2; // INV
          _RawType? at;
          int? atId;
          while (true) {
            final u = a.tag();
            if (u == null) break;
            final (g, x) = u;
            switch (g) {
              case 1 when x == 0:
                projection = a.varint();
              case 2 when x == 2:
                at = _type(a.message(), depth + 1);
              case 3 when x == 0:
                atId = a.varint();
              default:
                a.skip(x);
            }
          }
          r.args.add((projection, at, atId));
        case 3 when w == 0:
          r.nullable = p.varint() != 0;
        case 6 when w == 0:
          r.className = p.varint();
        case 7 when w == 0:
          r.typeParameter = p.varint();
        default:
          p.skip(w);
      }
    }
    return r;
  }

  _RawType? _typeOf(_RawType? inline, int? id) {
    if (inline != null) return inline;
    if (id == null) return null;
    if (id < 0 || id >= _typeTable.length) {
      throw MalformedInputException('type id $id out of range');
    }
    return _typeTable[id];
  }

  KotlinType _resolve(_RawType t, [int depth = 0]) {
    if (depth > KotlinMetadataLimits.maxDepth) {
      throw MalformedInputException('type nesting too deep');
    }
    return KotlinType(
      t.className == null ? null : table.get(t.className!),
      t.nullable,
      [
        for (final (proj, at, id) in t.args)
          proj ==
                  3 // STAR
              ? null
              : switch (_typeOf(at, id)) {
                  final x? => _resolve(x, depth + 1),
                  null => null,
                },
      ],
    );
  }

  ({String? name, String? desc}) _jvmSig(_Proto p) {
    String? name, desc;
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      if (f == 1 && w == 0) {
        name = table.get(p.varint());
      } else if (f == 2 && w == 0) {
        desc = table.get(p.varint());
      } else {
        p.skip(w);
      }
    }
    return (name: name, desc: desc);
  }

  KotlinParameter _parameter(_Proto p) {
    var flags = 0;
    String name = '';
    _RawType? type;
    int? typeId;
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 1 when w == 0:
          flags = p.varint();
        case 2 when w == 0:
          name = table.get(p.varint());
        case 3 when w == 2:
          type = _type(p.message(), 0);
        case 5 when w == 0:
          typeId = p.varint();
        default:
          p.skip(w);
      }
    }
    final rt = _typeOf(type, typeId);
    return KotlinParameter(
      name,
      rt == null ? const KotlinType(null, true, []) : _resolve(rt),
      hasDefault: (flags >> 1) & 1 == 1,
    );
  }

  KotlinFunction _constructor(_Proto p) {
    final params = <KotlinParameter>[];
    ({String? name, String? desc})? sig;
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 2 when w == 2:
          params.add(_parameter(p.message()));
        case 100 when w == 2:
          sig = _jvmSig(p.message());
        default:
          p.skip(w);
      }
    }
    final desc =
        sig?.desc ??
        _defaultDesc([for (final x in params) x.type], null, isCtor: true);
    return KotlinFunction(
      name: '<init>',
      jvmName: '<init>',
      jvmDescriptor: desc,
      returnType: null,
      parameters: params,
      isSuspend: false,
    );
  }

  KotlinFunction _function(_Proto p) {
    var flags = 6;
    var name = '';
    _RawType? ret, recv;
    int? retId, recvId;
    final params = <KotlinParameter>[];
    ({String? name, String? desc})? sig;
    List<_RawType>? localTable;
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 9 when w == 0:
          flags = p.varint();
        case 2 when w == 0:
          name = table.get(p.varint());
        case 3 when w == 2:
          ret = _type(p.message(), 0);
        case 7 when w == 0:
          retId = p.varint();
        case 5 when w == 2:
          recv = _type(p.message(), 0);
        case 8 when w == 0:
          recvId = p.varint();
        case 6 when w == 2:
          params.add(_parameter(p.message()));
        case 30 when w == 2:
          localTable = _parseTypeTable(p.message());
        case 100 when w == 2:
          sig = _jvmSig(p.message());
        default:
          p.skip(w);
      }
    }
    if (localTable != null) _typeTable = localTable;
    final rt = _typeOf(ret, retId);
    final returnType = rt == null ? null : _resolve(rt);
    final rcv = _typeOf(recv, recvId);
    final receiver = rcv == null ? null : _resolve(rcv);
    final isSuspend = (flags >> 13) & 1 == 1;
    final desc =
        sig?.desc ??
        (isSuspend
            ? null
            : _defaultDesc([
                ?receiver,
                for (final x in params) x.type,
              ], returnType));
    return KotlinFunction(
      name: name,
      jvmName: sig?.name ?? name,
      jvmDescriptor: desc,
      returnType: returnType,
      parameters: params,
      isSuspend: isSuspend,
      hasReceiver: receiver != null,
    );
  }

  KotlinProperty _property(_Proto p) {
    var flags = 518;
    var name = '';
    _RawType? ret;
    int? retId;
    ({String? name, String? desc})? getter, setter;
    while (true) {
      final t = p.tag();
      if (t == null) break;
      final (f, w) = t;
      switch (f) {
        case 11 when w == 0:
          flags = p.varint();
        case 2 when w == 0:
          name = table.get(p.varint());
        case 3 when w == 2:
          ret = _type(p.message(), 0);
        case 9 when w == 0:
          retId = p.varint();
        case 100 when w == 2:
          final s = p.message();
          while (true) {
            final u = s.tag();
            if (u == null) break;
            final (g, x) = u;
            if (g == 3 && x == 2) {
              getter = _jvmSig(s.message());
            } else if (g == 4 && x == 2) {
              setter = _jvmSig(s.message());
            } else {
              s.skip(x);
            }
          }
        default:
          p.skip(w);
      }
    }
    final rt = _typeOf(ret, retId);
    final type = rt == null ? const KotlinType(null, true, []) : _resolve(rt);
    final isVar = (flags >> 8) & 1 == 1;
    final mapped = type.className == null ? null : _mapClass(type.className!);
    String? key(({String? name, String? desc})? s, String? defaultDesc) {
      final n = s?.name;
      final d = s?.desc ?? defaultDesc;
      return n == null || d == null ? null : '$n$d';
    }

    return KotlinProperty(
      name,
      type,
      getter: key(getter, mapped == null ? null : '()$mapped'),
      setter: key(setter, mapped == null ? null : '($mapped)V'),
      isVar: isVar,
    );
  }
}

/// `ClassMapperLite`: Kotlin class names to JVM descriptors, used when the
/// metadata omits a JVM descriptor (it is then derivable this way).
const _mapped = {
  'kotlin/Boolean': 'Z',
  'kotlin/Char': 'C',
  'kotlin/Byte': 'B',
  'kotlin/Short': 'S',
  'kotlin/Int': 'I',
  'kotlin/Float': 'F',
  'kotlin/Long': 'J',
  'kotlin/Double': 'D',
  'kotlin/BooleanArray': '[Z',
  'kotlin/CharArray': '[C',
  'kotlin/ByteArray': '[B',
  'kotlin/ShortArray': '[S',
  'kotlin/IntArray': '[I',
  'kotlin/FloatArray': '[F',
  'kotlin/LongArray': '[J',
  'kotlin/DoubleArray': '[D',
  'kotlin/Any': 'Ljava/lang/Object;',
  'kotlin/Nothing': 'Ljava/lang/Void;',
  'kotlin/Annotation': 'Ljava/lang/annotation/Annotation;',
  'kotlin/String': 'Ljava/lang/String;',
  'kotlin/CharSequence': 'Ljava/lang/CharSequence;',
  'kotlin/Throwable': 'Ljava/lang/Throwable;',
  'kotlin/Cloneable': 'Ljava/lang/Cloneable;',
  'kotlin/Number': 'Ljava/lang/Number;',
  'kotlin/Comparable': 'Ljava/lang/Comparable;',
  'kotlin/Enum': 'Ljava/lang/Enum;',
  'kotlin/collections/Iterator': 'Ljava/util/Iterator;',
  'kotlin/collections/MutableIterator': 'Ljava/util/Iterator;',
  'kotlin/collections/Iterable': 'Ljava/lang/Iterable;',
  'kotlin/collections/MutableIterable': 'Ljava/lang/Iterable;',
  'kotlin/collections/Collection': 'Ljava/util/Collection;',
  'kotlin/collections/MutableCollection': 'Ljava/util/Collection;',
  'kotlin/collections/List': 'Ljava/util/List;',
  'kotlin/collections/MutableList': 'Ljava/util/List;',
  'kotlin/collections/Set': 'Ljava/util/Set;',
  'kotlin/collections/MutableSet': 'Ljava/util/Set;',
  'kotlin/collections/Map': 'Ljava/util/Map;',
  'kotlin/collections/MutableMap': 'Ljava/util/Map;',
  'kotlin/collections/Map.Entry': 'Ljava/util/Map\$Entry;',
  'kotlin/collections/MutableMap.MutableEntry': 'Ljava/util/Map\$Entry;',
  'kotlin/collections/ListIterator': 'Ljava/util/ListIterator;',
  'kotlin/collections/MutableListIterator': 'Ljava/util/ListIterator;',
};

String? _mapClass(String name) {
  final m = _mapped[name];
  if (m != null) return m;
  if (RegExp(r'^kotlin/Function(\d+)$').hasMatch(name)) {
    return 'Lkotlin/jvm/functions/${name.substring(7)};';
  }
  if (name.startsWith('.')) return null; // local class
  return 'L${name.replaceAll('.', r'$')};';
}

String? _defaultDesc(
  List<KotlinType> params,
  KotlinType? ret, {
  bool isCtor = false,
}) {
  final b = StringBuffer('(');
  for (final p in params) {
    final c = p.className;
    if (c == null) return null;
    final d = _mapClass(c);
    if (d == null || d == 'V') return null;
    b.write(d);
  }
  b.write(')');
  if (isCtor) {
    b.write('V');
  } else {
    final c = ret?.className;
    if (c == null) return null;
    final d = c == 'kotlin/Unit' ? 'V' : _mapClass(c);
    if (d == null) return null;
    b.write(d);
  }
  return b.toString();
}
