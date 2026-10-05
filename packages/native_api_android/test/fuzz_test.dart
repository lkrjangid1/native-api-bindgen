import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_android/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('mutated class files fail with MalformedInputException only', () {
    if (!javacAvailable) {
      markTestSkipped('javac not available');
      return;
    }
    final dir = compileFixtures();
    addTearDown(() => dir.deleteSync(recursive: true));
    final seeds = [
      for (final f in Directory(dir.path).listSync(recursive: true))
        if (f is File && f.path.endsWith('.class')) f.readAsBytesSync(),
    ];
    final rnd = Random(7);
    var parsed = 0, rejected = 0;
    for (var i = 0; i < 4000; i++) {
      final b = Uint8List.fromList(seeds[rnd.nextInt(seeds.length)]);
      final mode = rnd.nextInt(3);
      Uint8List input;
      if (mode == 0) {
        input = Uint8List.sublistView(b, 0, rnd.nextInt(b.length));
      } else {
        for (var k = 0; k < 1 + rnd.nextInt(8); k++) {
          b[rnd.nextInt(b.length)] = rnd.nextInt(256);
        }
        input = b;
      }
      try {
        ClassFile.parse(input);
        parsed++;
      } on MalformedInputException {
        rejected++;
      }
    }
    expect(parsed + rejected, 4000);
    expect(rejected, greaterThan(0));
  });

  test('malformed zip and XML are rejected cleanly', () {
    final rnd = Random(3);
    for (var i = 0; i < 300; i++) {
      final b = Uint8List.fromList(
        List.generate(rnd.nextInt(200), (_) => rnd.nextInt(256)),
      );
      if (i.isEven && b.length > 22) {
        b.setRange(b.length - 22, b.length - 18, [0x50, 0x4b, 5, 6]);
      }
      expect(
        () => ZipReader.fromBytes(b).names.toList(),
        anyOf(returnsNormally, throwsA(isA<MalformedInputException>())),
      );
    }
    expect(
      () => ApiVersionsIndex.parse('<api><class name="a/B" since="1"><method'),
      throwsA(isA<MalformedInputException>()),
    );
  });

  test('a corrupt class in the source yields E008, extraction continues', () {
    final tmp = Directory.systemTemp.createTempSync('corrupt');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'a', 'Bad.class'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 52, 0]);
    final ex = AndroidApiExtractor(
      classes: DirectoryClassSource(tmp.path),
      sdkVersion: 'x',
      linkOfficialDocs: false,
    );
    final r = ex.extract(const ExtractionRequest(classes: ['a.Bad']));
    expect(r.module.types, isEmpty);
    expect(r.diagnostics.single.code.code, 'E008');
  });
}
