import 'dart:math';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_android/testing.dart';
import 'package:test/test.dart';

void main() {
  final jar = kotlinFixtureJar();
  if (jar == null) {
    test('kotlin.Metadata', () {}, skip: 'Kotlin fixture jar not built');
    return;
  }
  final src = JarClassSource.open(jar);
  final cf = ClassFile.parse(src.read('com.example.kfixtures.Greeter')!);
  final raw = cf.visibleAnnotations.firstWhere(
    (a) => a.typeName == 'kotlin.Metadata',
  );
  final d1 = raw.stringArrays['d1']!;
  final d2 = raw.stringArrays['d2']!;
  final meta = KotlinMetadata.decode(kind: 1, d1: d1, d2: d2)!;
  KotlinFunction fn(String name) =>
      meta.functions.firstWhere((f) => f.name == name);

  test('every decoded signature is a method of the class file', () {
    final methods = {for (final m in cf.methods) '${m.name}${m.descriptor}'};
    for (final f in meta.functions) {
      expect(methods, contains(f.key), reason: f.name);
    }
  });

  test('suspend functions and result nullability', () {
    expect(fn('greetLater').isSuspend, isTrue);
    expect(fn('greetLater').returnType!.nullable, isFalse);
    expect(fn('maybe').returnType!.nullable, isTrue);
    expect(fn('greet').isSuspend, isFalse);
  });

  test('default arguments', () {
    expect(
      [for (final p in fn('repeat').parameters) '${p.name}:${p.hasDefault}'],
      ['text:false', 'times:true', 'separator:true'],
    );
  });

  test('type arguments keep nullability', () {
    expect(
      fn('words').returnType.toString(),
      'kotlinx/coroutines/flow/Flow<kotlin/String?>',
    );
    expect(
      fn('countTo').returnType.toString(),
      'kotlinx/coroutines/flow/Flow<kotlin/Int>',
    );
  });

  test('properties with JVM accessors', () {
    final props = {for (final p in meta.properties) p.name: p};
    expect(props['nickname']!.type.nullable, isTrue);
    expect(props['nickname']!.isVar, isTrue);
    expect(props['nickname']!.getter, 'getNickname()Ljava/lang/String;');
    expect(props['nickname']!.setter, 'setNickname(Ljava/lang/String;)V');
    expect(props['nameLength']!.isVar, isFalse);
    expect(props['nameLength']!.getter, 'getNameLength()I');
    expect(props['isLoud']!.getter, 'isLoud()Z');
  });

  test('extraction applies the metadata', () {
    final module = extractKotlinFixtures(jar);
    final t = module.types.firstWhere(
      (t) => t.id == 'com.example.kfixtures.Greeter',
    );
    final maybe = t.methods.firstWhere((m) => m.name == 'maybe');
    final later = t.methods.firstWhere((m) => m.name == 'greetLater');
    expect(maybe.parameters.last.type.display, contains('java.lang.String'));
    expect(later.parameters.last.type.toJson().toString(), contains('nonnull'));
    expect(
      maybe.parameters.last.type.toJson().toString(),
      contains('nullable'),
    );
    final repeat = t.methods.firstWhere((m) => m.name == 'repeat');
    expect(repeat.diagnostics.single.message, contains('`times`, `separator`'));
    expect(
      t.annotations.firstWhere((a) => a.type == 'kotlin.Metadata').values.keys,
      isNot(contains('d1')),
    );
  });

  test('mutated metadata fails only with MalformedInputException', () {
    final rnd = Random(7);
    var decoded = 0, rejected = 0;
    for (var i = 0; i < 2000; i++) {
      final chars = d1.join().codeUnits.toList();
      for (var k = 0; k < 1 + rnd.nextInt(6); k++) {
        final at = 1 + rnd.nextInt(chars.length - 1);
        chars[at] = rnd.nextInt(256);
      }
      if (rnd.nextBool()) chars.length = 1 + rnd.nextInt(chars.length);
      try {
        KotlinMetadata.decode(
          kind: 1,
          d1: [String.fromCharCodes(chars)],
          d2: d2,
        );
        decoded++;
      } on MalformedInputException {
        rejected++;
      }
    }
    expect(decoded + rejected, 2000);
  });
}
