@TestOn('vm')
library;

import 'dart:io';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_android/testing.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  if (!javacAvailable) {
    test('fixture extraction', () {}, skip: 'javac not available');
    return;
  }
  late ApiModule module;
  late Directory classesDir;
  setUpAll(() {
    final f = fixtureExtractor();
    classesDir = f.classesDir;
    module = extractFixtures(f.extractor);
  });
  tearDownAll(() => classesDir.deleteSync(recursive: true));

  ApiType type(String simple) =>
      module.typeById('com.example.fixtures.$simple')!;
  ApiMethod method(String simple, String sig) =>
      module.nodeById('com.example.fixtures.$simple#$sig')! as ApiMethod;
  ApiField field(String simple, String name) =>
      module.nodeById('com.example.fixtures.$simple#$name')! as ApiField;

  test('IR is valid and matches the committed snapshot', () {
    expect(
      validateModule(module).where((d) => d.severity == Severity.error),
      isEmpty,
    );
    final golden = File(
      p.join(findRepoRoot(), 'tests', 'golden', 'ir', 'fixtures_basic.json'),
    );
    final text = module.toCanonicalJson();
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      golden
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    expect(
      text,
      golden.readAsStringSync(),
      reason: 'run with UPDATE_GOLDENS=1 to accept changes',
    );
  });

  test('nullability from annotations', () {
    final m = method(
      'NullableClass',
      'describe(java.lang.String,java.lang.Object,java.lang.String)',
    );
    expect(m.returnType.nullability, Nullability.nonnull);
    expect(m.parameters.map((x) => x.type.nullability), [
      Nullability.nullable,
      Nullability.nonnull,
      Nullability.unknown,
    ]);
    expect(
      field('NullableClass', 'maybe').type.nullability,
      Nullability.nullable,
    );
    expect(
      field('NullableClass', 'definitely').type.nullability,
      Nullability.nonnull,
    );
  });

  test('parameter names from LocalVariableTable, synthesized for abstract', () {
    final m = method(
      'NullableClass',
      'describe(java.lang.String,java.lang.Object,java.lang.String)',
    );
    expect(m.parameters.map((x) => x.name), ['prefix', 'value', 'unannotated']);
    expect(m.parameters.first.nameSource, 'LocalVariableTable');
    final add = method('OverloadedClass', 'add(long,long)');
    expect(add.parameters.map((x) => x.name), ['a', 'b']);
    final cb = method('CallbackInterface', 'onEvent(java.lang.String,int)');
    expect(cb.parameters.map((x) => x.nameSource), everyElement('synthesized'));
  });

  test('overloads have distinct stable IDs', () {
    final ids = type('OverloadedClass').methods.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(
      ids,
      contains(
        'com.example.fixtures.OverloadedClass#put(java.lang.String,int[])',
      ),
    );
    expect(ids, contains('com.example.fixtures.OverloadedClass#<init>(int)'));
    final join = method(
      'OverloadedClass',
      'join(java.lang.String,java.lang.String[])',
    );
    expect(join.modifiers, containsAll([Modifier.static_, Modifier.varargs]));
  });

  test('constants preserve exact values', () {
    String lit(String n) => field('AnnotatedClass', n).constantValue!.literal;
    expect(lit('MODE_B'), '2');
    expect(lit('BIG'), '9223372036854775807');
    expect(lit('HALF'), '0.5');
    expect(lit('TINY'), '1e-300');
    expect(lit('LETTER'), '${'x'.codeUnitAt(0)}');
    expect(lit('ENABLED'), 'true');
    expect(lit('ACTION'), r'com.example.ACTION "quoted" $dollar \slash');
    expect(lit('UNICODE'), 'café ☃');
    expect(field('AnnotatedClass', 'counter').constantValue, isNull);
  });

  test('annotations: classification, threading, permissions', () {
    final capture = method('AnnotatedClass', 'capture(int)');
    expect(capture.threading, Threading.workerThread);
    expect(capture.permissions, [
      'anyOf:android.permission.CAMERA',
      'anyOf:android.permission.RECORD_AUDIO',
    ]);
    expect(
      capture.annotations.map((a) => a.classification),
      contains(AnnotationClassification.preservable),
    );
    expect(
      method('AnnotatedClass', 'render()').threading,
      Threading.mainThread,
    );
    expect(method('AnnotatedClass', 'old()').isDeprecated, isTrue);
    expect(type('DeprecatedClass').isDeprecated, isTrue);
  });

  test('availability from api-versions, including minor versions', () {
    expect(
      method('ApiLevelClass', 'since30()').availability.introduced,
      const ApiVersion(30),
    );
    expect(
      method('ApiLevelClass', 'since30()').availability.deprecated,
      const ApiVersion(35),
    );
    expect(
      method('ApiLevelClass', 'since36minor()').availability.introduced,
      const ApiVersion(36, 1),
    );
    expect(
      method('ApiLevelClass', 'since1()').availability.introduced,
      const ApiVersion(5),
      reason: 'raised to class since',
    );
    final unlisted = method('ApiLevelClass', 'unlisted()');
    expect(unlisted.support, SupportStatus.partial);
    expect(
      unlisted.diagnostics.single.code,
      DiagnosticCode.availabilityMismatch,
    );
  });

  test('non-SDK classes are never supported', () {
    final h = type('HiddenClass');
    expect(h.visibility, ApiVisibility.hiddenOrNonSdk);
    expect(h.support, SupportStatus.unsupported);
    expect(h.diagnostics.single.code, DiagnosticCode.nonSdkApi);
    expect(h.isGeneratable, isFalse);
  });

  test('kinds, nesting, generics, throws, interface defaults', () {
    expect(type('EnumClass').kind, TypeKind.enumType);
    expect(type('CallbackInterface').kind, TypeKind.interfaceType);
    expect(
      method('CallbackInterface', 'label()').modifiers,
      contains(Modifier.default_),
    );
    expect(type('NestedClass').nestedTypes, [
      r'com.example.fixtures.NestedClass$Builder',
      r'com.example.fixtures.NestedClass$Inner',
      r'com.example.fixtures.NestedClass$Listener',
    ]);
    expect(module.typeById(r'com.example.fixtures.NestedClass$Hidden'), isNull);
    expect(
      type(r'NestedClass$Builder').enclosingType,
      'com.example.fixtures.NestedClass',
    );
    expect(type(r'NestedClass$Builder').name, 'Builder');
    expect(
      method(
        r'NestedClass$Inner',
        '<init>(com.example.fixtures.NestedClass)',
      ).parameters,
      hasLength(1),
    );
    final g = type('GenericClass');
    expect(
      g.typeParameters.single.bounds.single.display,
      'java.lang.CharSequence',
    );
    expect(method('GenericClass', 'get()').returnType, isA<TypeVariableRef>());
    expect(
      method(
        'GenericClass',
        'set(java.lang.CharSequence)',
      ).parameters.single.type.display,
      'T',
    );
    expect(
      method('ThrowsClass', 'read()').throws.single.display,
      'java.io.IOException',
    );
  });

  test('provenance has no absolute paths', () {
    final t = type('NullableClass');
    expect(t.provenance.localArtifact, 'fixtures');
    expect(
      t.provenance.artifactEntry,
      'com/example/fixtures/NullableClass.class',
    );
    expect(module.toCanonicalJson(), isNot(contains(classesDir.path)));
  });

  test('dependency-aware extraction follows referenced types', () {
    final f = fixtureExtractor();
    addTearDown(() => f.classesDir.deleteSync(recursive: true));
    final r = f.extractor.extract(
      const ExtractionRequest(
        entries: ['com.example.fixtures.AsyncClass'],
        depth: 1,
      ),
    );
    expect(r.module.types.map((t) => t.id), [
      'com.example.fixtures.AsyncClass',
      'com.example.fixtures.CallbackInterface',
    ]);
    final r0 = f.extractor.extract(
      const ExtractionRequest(
        classes: ['com.example.fixtures.NestedClass.Builder'],
      ),
    );
    expect(r0.module.types.map((t) => t.id), [
      r'com.example.fixtures.NestedClass$Builder',
    ]);
  });
}
