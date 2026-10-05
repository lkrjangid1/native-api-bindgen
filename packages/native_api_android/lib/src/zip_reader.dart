import 'dart:io';
import 'dart:typed_data';

import 'classfile/byte_reader.dart';

/// Minimal, bounds-checked ZIP reader for SDK archives (`android.jar`,
/// `annotations.zip`). Supports stored and deflated entries. Entries are
/// inflated lazily, one at a time, with a size cap.
final class ZipReader {
  ZipReader._(this._bytes, this._entries);

  /// Opens [path]. Throws [MalformedInputException] for invalid archives.
  factory ZipReader.open(String path, {int maxArchiveBytes = 1 << 30}) {
    final f = File(path);
    final len = f.lengthSync();
    if (len > maxArchiveBytes) {
      throw MalformedInputException('archive exceeds $maxArchiveBytes bytes');
    }
    return ZipReader.fromBytes(f.readAsBytesSync());
  }

  /// Parses an in-memory archive.
  factory ZipReader.fromBytes(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    final r = ByteReader(bytes)..offset = eocd + 10;
    final total = r.u2le();
    final cdSize = r.u4le();
    final cdOffset = r.u4le();
    if (cdOffset == 0xFFFFFFFF || total == 0xFFFF) {
      throw MalformedInputException('ZIP64 archives are not supported');
    }
    if (cdOffset + cdSize > bytes.length) {
      throw MalformedInputException('central directory out of range');
    }
    final entries = <String, ZipEntry>{};
    r.offset = cdOffset;
    for (var i = 0; i < total; i++) {
      if (r.u4le() != 0x02014b50) {
        throw MalformedInputException('bad central directory signature');
      }
      r.skip(6);
      final method = r.u2le();
      r.skip(8);
      final compressed = r.u4le();
      final size = r.u4le();
      final nameLen = r.u2le();
      final extraLen = r.u2le();
      final commentLen = r.u2le();
      r.skip(8);
      final localOffset = r.u4le();
      final name = String.fromCharCodes(r.take(nameLen));
      r.skip(extraLen + commentLen);
      entries[name] = ZipEntry._(name, method, compressed, size, localOffset);
    }
    return ZipReader._(bytes, entries);
  }

  final Uint8List _bytes;
  final Map<String, ZipEntry> _entries;

  /// Entry names.
  Iterable<String> get names => _entries.keys;

  /// Whether [name] exists.
  bool contains(String name) => _entries.containsKey(name);

  /// Inflates [name], or returns null if absent.
  Uint8List? read(String name, {int maxBytes = 64 << 20}) {
    final e = _entries[name];
    if (e == null) return null;
    if (e.size > maxBytes || e.compressedSize > maxBytes) {
      throw MalformedInputException('entry $name exceeds $maxBytes bytes');
    }
    final r = ByteReader(_bytes)..offset = e._localOffset;
    if (r.u4le() != 0x04034b50) {
      throw MalformedInputException('bad local header for $name');
    }
    r.skip(22);
    final nameLen = r.u2le();
    final extraLen = r.u2le();
    r.skip(nameLen + extraLen);
    final data = r.take(e.compressedSize);
    switch (e.method) {
      case 0:
        return Uint8List.fromList(data);
      case 8:
        final out = ZLibDecoder(raw: true).convert(data);
        if (out.length != e.size) {
          throw MalformedInputException('size mismatch for $name');
        }
        return out is Uint8List ? out : Uint8List.fromList(out);
      default:
        throw MalformedInputException(
          'unsupported compression ${e.method} for $name',
        );
    }
  }

  static int _findEocd(Uint8List b) {
    final min = b.length - 22 - 0xFFFF;
    for (var i = b.length - 22; i >= 0 && i >= min; i--) {
      if (b[i] == 0x50 &&
          b[i + 1] == 0x4b &&
          b[i + 2] == 0x05 &&
          b[i + 3] == 0x06) {
        return i;
      }
    }
    throw MalformedInputException(
      'not a ZIP archive (no end of central directory)',
    );
  }
}

/// A ZIP entry.
final class ZipEntry {
  ZipEntry._(
    this.name,
    this.method,
    this.compressedSize,
    this.size,
    this._localOffset,
  );

  /// Entry name.
  final String name;

  /// Compression method.
  final int method;

  /// Compressed size.
  final int compressedSize;

  /// Uncompressed size.
  final int size;

  final int _localOffset;
}
