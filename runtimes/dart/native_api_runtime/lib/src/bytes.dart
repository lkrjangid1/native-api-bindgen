import 'dart:typed_data';

import 'package:jni/jni.dart';

/// Copies a Java `byte[]` into a new [Uint8List] (one JNI region copy).
Uint8List bytesOf(JByteArray array) {
  final n = array.length;
  if (n == 0) return Uint8List(0);
  final signed = array.getRange(0, n);
  return signed.buffer.asUint8List(signed.offsetInBytes, n);
}

/// Copies [bytes] into a new Java `byte[]` (one JNI region copy).
JByteArray byteArrayOf(Uint8List bytes) {
  final array = JByteArray(bytes.length);
  if (bytes.isNotEmpty) {
    array.setRange(0, bytes.length, Int8List.sublistView(bytes));
  }
  return array;
}

/// A direct `java.nio.ByteBuffer` holding a copy of [bytes]; Java and Dart
/// then share its memory without further copies (see
/// `JByteBuffer.asUint8List`).
JByteBuffer directBufferOf(Uint8List bytes) {
  final buffer = JByteBuffer.allocateDirect(bytes.length);
  buffer.asUint8List().setAll(0, bytes);
  return buffer;
}
