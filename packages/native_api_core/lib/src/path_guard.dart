import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when a write would escape the output root (diagnostic `E017`).
final class UnsafePathException implements Exception {
  /// Creates the exception.
  UnsafePathException(this.path, this.reason);

  /// Offending relative path.
  final String path;

  /// Explanation.
  final String reason;

  @override
  String toString() => 'E017 UNSAFE_PATH: $path ($reason)';
}

/// Confines all generated writes to [root].
///
/// Rejects absolute paths, `..` segments, empty segments, NUL bytes and
/// symlinks (existing directories inside [root] that resolve outside it).
final class OutputGuard {
  /// Creates a guard rooted at [root] (created if missing).
  OutputGuard(String root) : root = p.normalize(p.absolute(root));

  /// Absolute, normalized root.
  final String root;

  /// Resolves a relative path inside [root] or throws [UnsafePathException].
  String resolve(String relative) {
    if (relative.isEmpty) throw UnsafePathException(relative, 'empty path');
    if (relative.contains('\u0000')) {
      throw UnsafePathException(relative, 'NUL byte');
    }
    final posix = relative.replaceAll(r'\', '/');
    if (p.posix.isAbsolute(posix) ||
        p.windows.isAbsolute(relative) ||
        posix.startsWith('~')) {
      throw UnsafePathException(relative, 'absolute path');
    }
    final segments = posix.split('/');
    if (segments.any((s) => s == '..' || s.isEmpty)) {
      throw UnsafePathException(relative, 'parent or empty segment');
    }
    final full = p.normalize(p.join(root, p.joinAll(segments)));
    if (!p.isWithin(root, full)) {
      throw UnsafePathException(relative, 'outside output root');
    }
    _checkSymlinks(relative, full);
    return full;
  }

  void _checkSymlinks(String relative, String full) {
    final realRoot = Directory(root).existsSync()
        ? Directory(root).resolveSymbolicLinksSync()
        : root;
    var dir = p.dirname(full);
    while (p.isWithin(root, dir) || p.equals(root, dir)) {
      if (Directory(dir).existsSync()) {
        final real = Directory(dir).resolveSymbolicLinksSync();
        if (!(p.isWithin(realRoot, real) || p.equals(realRoot, real))) {
          throw UnsafePathException(relative, 'symlink escapes output root');
        }
        break;
      }
      dir = p.dirname(dir);
    }
    final link = Link(full);
    if (link.existsSync()) {
      throw UnsafePathException(relative, 'target is a symlink');
    }
  }

  /// Writes [contents] to [relative] inside [root]. Returns the absolute path.
  String writeString(String relative, String contents) {
    final full = resolve(relative);
    Directory(p.dirname(full)).createSync(recursive: true);
    File(full).writeAsStringSync(contents);
    return full;
  }

  /// Writes the text produced by [write] to [relative] in chunks (UTF-8),
  /// so large documents are never held in memory whole. Returns the
  /// absolute path.
  String writeStreaming(String relative, void Function(StringSink out) write) {
    final full = resolve(relative);
    Directory(p.dirname(full)).createSync(recursive: true);
    final file = File(full).openSync(mode: FileMode.write);
    try {
      final sink = _ChunkedSink(file);
      write(sink);
      sink.flush();
    } finally {
      file.closeSync();
    }
    return full;
  }
}

/// StringSink that flushes UTF-8 to [file] every ~1 MB.
final class _ChunkedSink implements StringSink {
  _ChunkedSink(this._file);

  final RandomAccessFile _file;
  final _buffer = StringBuffer();

  void _maybeFlush() {
    if (_buffer.length >= 1 << 20) flush();
  }

  void flush() {
    if (_buffer.isEmpty) return;
    _file.writeFromSync(utf8.encode(_buffer.toString()));
    _buffer.clear();
  }

  @override
  void write(Object? object) {
    _buffer.write(object);
    _maybeFlush();
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _buffer.writeAll(objects, separator);
    _maybeFlush();
  }

  @override
  void writeCharCode(int charCode) {
    _buffer.writeCharCode(charCode);
    _maybeFlush();
  }

  @override
  void writeln([Object? object = '']) {
    _buffer.writeln(object);
    _maybeFlush();
  }
}
