import 'dart:convert';
import 'dart:typed_data';

/// Thrown for malformed binary input. Mapped to diagnostic `E008`.
final class MalformedInputException implements Exception {
  /// Creates the exception.
  MalformedInputException(this.message);

  /// Explanation.
  final String message;

  @override
  String toString() => 'Malformed input: $message';
}

/// Big-endian, bounds-checked reader over a byte buffer.
final class ByteReader {
  /// Creates a reader over [bytes].
  ByteReader(this.bytes) : _data = ByteData.sublistView(bytes);

  /// Underlying bytes.
  final Uint8List bytes;
  final ByteData _data;

  /// Current offset.
  int offset = 0;

  /// Remaining bytes.
  int get remaining => bytes.length - offset;

  void _need(int n) {
    if (n < 0 || offset + n > bytes.length) {
      throw MalformedInputException(
        'unexpected end of data at offset $offset (need $n bytes)',
      );
    }
  }

  /// Unsigned 8-bit.
  int u1() {
    _need(1);
    return bytes[offset++];
  }

  /// Unsigned 16-bit.
  int u2() {
    _need(2);
    final v = _data.getUint16(offset);
    offset += 2;
    return v;
  }

  /// Unsigned 32-bit.
  int u4() {
    _need(4);
    final v = _data.getUint32(offset);
    offset += 4;
    return v;
  }

  /// Unsigned 16-bit little-endian (ZIP structures).
  int u2le() {
    _need(2);
    final v = _data.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  /// Unsigned 32-bit little-endian (ZIP structures).
  int u4le() {
    _need(4);
    final v = _data.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  /// Signed 32-bit.
  int s4() {
    _need(4);
    final v = _data.getInt32(offset);
    offset += 4;
    return v;
  }

  /// Signed 64-bit.
  int s8() {
    _need(8);
    final v = _data.getInt64(offset);
    offset += 8;
    return v;
  }

  /// IEEE 754 float.
  double f4() {
    _need(4);
    final v = _data.getFloat32(offset);
    offset += 4;
    return v;
  }

  /// IEEE 754 double.
  double f8() {
    _need(8);
    final v = _data.getFloat64(offset);
    offset += 8;
    return v;
  }

  /// [n] raw bytes (a view, not a copy).
  Uint8List take(int n) {
    _need(n);
    final v = Uint8List.sublistView(bytes, offset, offset + n);
    offset += n;
    return v;
  }

  /// Skips [n] bytes.
  void skip(int n) {
    _need(n);
    offset += n;
  }
}

/// Decodes JVM "modified UTF-8" (JVMS §4.4.7).
String decodeModifiedUtf8(Uint8List b) {
  // Fast path: plain ASCII.
  var ascii = true;
  for (final c in b) {
    if (c == 0 || c >= 0x80) {
      ascii = false;
      break;
    }
  }
  if (ascii) return latin1.decode(b);
  final units = <int>[];
  var i = 0;
  while (i < b.length) {
    final x = b[i];
    if (x == 0) throw MalformedInputException('NUL byte in modified UTF-8');
    if (x < 0x80) {
      units.add(x);
      i += 1;
    } else if ((x & 0xE0) == 0xC0) {
      if (i + 1 >= b.length) throw MalformedInputException('truncated UTF-8');
      units.add(((x & 0x1F) << 6) | (b[i + 1] & 0x3F));
      i += 2;
    } else if ((x & 0xF0) == 0xE0) {
      if (i + 2 >= b.length) throw MalformedInputException('truncated UTF-8');
      units.add(
        ((x & 0x0F) << 12) | ((b[i + 1] & 0x3F) << 6) | (b[i + 2] & 0x3F),
      );
      i += 3;
    } else {
      throw MalformedInputException('invalid modified UTF-8 lead byte');
    }
  }
  return String.fromCharCodes(units);
}
