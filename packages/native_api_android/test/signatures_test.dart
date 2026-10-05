import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

void main() {
  test('field descriptors', () {
    expect(
      SignatureParser.fieldType('I'),
      const PrimitiveTypeRef(PrimitiveKind.int_),
    );
    expect(SignatureParser.fieldType('[[J').display, 'long[][]');
    expect(
      SignatureParser.fieldType(r'Landroid/os/Handler$Callback;').erasedId,
      r'android.os.Handler$Callback',
    );
  });

  test('method descriptors and generic signatures', () {
    final m = SignatureParser.method('(Ljava/lang/String;[IZ)V');
    expect(m.parameters.map((t) => t.display), [
      'java.lang.String',
      'int[]',
      'boolean',
    ]);
    expect(m.returnType, const PrimitiveTypeRef(PrimitiveKind.void_));

    final g = SignatureParser.method(
      '<K:Ljava/lang/Object;V::Ljava/lang/Comparable<TV;>;>(Ljava/util/List<+TK;>;Ljava/util/List<-TV;>;)Ljava/util/Map<TK;TV;>;^Ljava/io/IOException;^TX;',
    );
    expect(g.typeParameters.map((t) => t.name), ['K', 'V']);
    expect(
      g.typeParameters[1].bounds.single.display,
      'java.lang.Comparable<V>',
    );
    expect(g.parameters.map((t) => t.display), [
      'java.util.List<? extends K>',
      'java.util.List<? super V>',
    ]);
    expect(g.returnType.display, 'java.util.Map<K, V>');
    expect(g.throws.map((t) => t.display), ['java.io.IOException', 'X']);
  });

  test('inner class type arguments', () {
    final t =
        SignatureParser.fieldType('Ljava/util/Map<TK;TV;>.Entry<TK;TV;>;')
            as DeclaredTypeRef;
    expect(t.name, r'java.util.Map$Entry');
    expect(t.typeArguments, hasLength(2));
  });

  test('class signatures', () {
    final c = SignatureParser.classSignature(
      '<T:Ljava/lang/Object;>Ljava/lang/Object;Ljava/lang/Comparable<TT;>;',
    );
    expect(c.typeParameters.single.name, 'T');
    expect(c.interfaces.single.display, 'java.lang.Comparable<T>');
  });

  test('malformed signatures throw MalformedInputException only', () {
    for (final bad in [
      '',
      'L',
      'Ljava/lang/String',
      '(I',
      '(I)',
      '<T>()V',
      'Q',
      '[',
      '(Ljava/util/List<;)V',
      '()V^',
    ]) {
      expect(
        () => SignatureParser.method(bad),
        throwsA(isA<MalformedInputException>()),
        reason: bad,
      );
    }
    var deep = 'I';
    for (var i = 0; i < 200; i++) {
      deep = 'Ljava/util/List<$deep>;'.replaceFirst(
        '<I>',
        '<Ljava/lang/Integer;>',
      );
    }
    expect(
      () => SignatureParser.fieldType(deep),
      throwsA(isA<MalformedInputException>()),
    );
  });
}
