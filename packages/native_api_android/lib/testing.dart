/// Test support for native-api-bindgen packages: compiles the synthetic Java
/// fixtures and builds an extractor over them. Not for production use.
library;

import 'dart:io';

import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

import 'src/annotations_index.dart';
import 'src/api_versions.dart';
import 'src/classfile/class_file.dart';
import 'src/extractor.dart';
import 'src/zip_reader.dart';

/// Repository root, located by walking up to the workspace pubspec.
String findRepoRoot([String? start]) {
  var dir = Directory(start ?? Directory.current.path).absolute;
  while (true) {
    if (File(
      p.join(dir.path, 'fixtures', 'java', 'basic', 'api-versions.xml'),
    ).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Repository root not found from ${start ?? Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Whether `javac` is available (fixture tests skip otherwise).
bool get javacAvailable {
  try {
    return Process.runSync('javac', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Compiles `fixtures/java/<name>/src` with `javac --release 17 -g` into a
/// fresh temporary directory and returns it.
Directory compileFixtures({String name = 'basic'}) {
  final src = p.join(findRepoRoot(), 'fixtures', 'java', name, 'src');
  final files = [
    for (final f in Directory(src).listSync(recursive: true))
      if (f is File && f.path.endsWith('.java')) f.path,
  ]..sort();
  final out = Directory.systemTemp.createTempSync('nab_fixtures_');
  // Compile-time stubs (kotlin.coroutines.Continuation) live outside the
  // fixture output so they never shadow the real classes at run time.
  final stubs = compileKotlinStubs();
  try {
    final r = Process.runSync('javac', [
      '--release',
      '17',
      '-g',
      '-encoding',
      'UTF-8',
      '-cp',
      stubs.path,
      '-d',
      out.path,
      ...files,
    ]);
    if (r.exitCode != 0) {
      throw StateError('javac failed:\n${r.stderr}');
    }
  } finally {
    stubs.deleteSync(recursive: true);
  }
  return out;
}

/// Compiles `fixtures/java/kotlin-stubs` into a fresh temporary directory.
Directory compileKotlinStubs() {
  final src = p.join(findRepoRoot(), 'fixtures', 'java', 'kotlin-stubs', 'src');
  final out = Directory.systemTemp.createTempSync('nab_kotlin_stubs_');
  final r = Process.runSync('javac', [
    '--release',
    '17',
    '-d',
    out.path,
    for (final f in Directory(src).listSync(recursive: true))
      if (f is File && f.path.endsWith('.java')) f.path,
  ]);
  if (r.exitCode != 0) {
    throw StateError('javac failed (stubs):\n${r.stderr}');
  }
  return out;
}

/// Classes excluded from the synthetic API list (simulated non-SDK API) and
/// annotation stubs that are not part of the fixture API surface.
const fixtureNonSdkClasses = {'com.example.fixtures.HiddenClass'};

/// Builds a complete synthetic `api-versions.xml` for [classes]: every public
/// class and member is listed at `since="1"`, except [fixtureNonSdkClasses];
/// classes present in the hand-written `fixtures/java/basic/api-versions.xml`
/// are taken verbatim from it (so availability tests control them exactly).
String fixtureApiVersionsXml(DirectoryClassSource classes) {
  final overridesText = File(
    p.join(findRepoRoot(), 'fixtures', 'java', 'basic', 'api-versions.xml'),
  ).readAsStringSync();
  final overrides = ApiVersionsIndex.parse(overridesText);
  final body = StringBuffer();
  final start = overridesText.indexOf('<class ');
  final end = overridesText.lastIndexOf('</api>');
  body.writeln(overridesText.substring(start, end).trimRight());
  for (final name in classes.classNames) {
    if (overrides.classes.containsKey(name) ||
        fixtureNonSdkClasses.contains(name)) {
      continue;
    }
    final cf = ClassFile.parse(classes.read(name)!);
    final internal = name.replaceAll('.', '/');
    body.writeln('\t<class name="$internal" since="1">');
    if (cf.superName != null) {
      body.writeln('\t\t<extends name="${cf.superName}"/>');
    }
    for (final i in cf.interfaces) {
      body.writeln('\t\t<implements name="$i"/>');
    }
    for (final m in cf.methods) {
      if (m.has(AccessFlags.public | AccessFlags.protected) &&
          !m.has(AccessFlags.synthetic)) {
        body.writeln(
          '\t\t<method name="${m.name.replaceAll('<', '&lt;')}${m.descriptor}"/>',
        );
      }
    }
    for (final f in cf.fields) {
      if (f.has(AccessFlags.public | AccessFlags.protected)) {
        body.writeln('\t\t<field name="${f.name}"/>');
      }
    }
    body.writeln('\t</class>');
  }
  return '<?xml version="1.0" encoding="utf-8"?>\n<api version="3">\n$body</api>\n';
}

/// An extractor over freshly compiled fixtures with the synthetic API list.
/// Documentation links are disabled (fixtures have no official pages).
({AndroidApiExtractor extractor, Directory classesDir}) fixtureExtractor() {
  final dir = compileFixtures();
  final source = DirectoryClassSource(dir.path);
  final versions = ApiVersionsIndex.parse(fixtureApiVersionsXml(source));
  late final AndroidApiExtractor extractor;
  final zip = fixtureAnnotationsZip(dir);
  extractor = AndroidApiExtractor(
    classes: source,
    sdkVersion: 'fixture',
    sourceKind: 'fixture',
    apiVersions: versions,
    annotations: zip == null
        ? null
        : AnnotationsIndex(
            ZipReader.open(zip),
            (n) => extractor.resolveClassName(n),
          ),
    linkOfficialDocs: false,
  );
  return (extractor: extractor, classesDir: dir);
}

/// All fixture API classes (excluding annotation stubs).
const fixturePackages = ['com.example.fixtures'];

/// Packs `fixtures/java/basic/annotations` (external annotations in the
/// `annotations.zip` layout) into `<dir>/annotations.zip` with the JDK's
/// `jar` tool. Returns null when `jar` is unavailable.
String? fixtureAnnotationsZip(Directory dir) {
  final src = p.join(
    findRepoRoot(),
    'fixtures',
    'java',
    'basic',
    'annotations',
  );
  final out = p.join(dir.path, 'annotations.zip');
  try {
    final r = Process.runSync('jar', [
      '--create',
      '--no-manifest',
      '--file',
      out,
      '-C',
      src,
      '.',
    ]);
    return r.exitCode == 0 ? out : null;
  } on ProcessException {
    return null;
  }
}

/// Convenience: extract the whole fixture package.
ApiModule extractFixtures(AndroidApiExtractor extractor) => extractor
    .extract(const ExtractionRequest(packages: fixturePackages, depth: 0))
    .module;

/// `fixtures/kotlin/basic/build/libs/kfixtures.jar` if it was built (with
/// Gradle, see `fixtures/kotlin/basic/build.gradle.kts`), else null.
String? kotlinFixtureJar() {
  final jar = p.join(
    findRepoRoot(),
    'fixtures',
    'kotlin',
    'basic',
    'build',
    'libs',
    'kfixtures.jar',
  );
  return File(jar).existsSync() ? jar : null;
}

/// Extracts the Kotlin fixture classes from [jar] as library APIs.
ApiModule extractKotlinFixtures(String jar) {
  final source = JarClassSource.open(jar);
  final extractor = AndroidApiExtractor(
    classes: source,
    sdkVersion: 'fixture',
    sourceKind: 'fixture',
    linkOfficialDocs: false,
    libraryClasses: source.classNames.toSet(),
  );
  return extractor
      .extract(
        const ExtractionRequest(
          classes: ['com.example.kfixtures.Greeter'],
          depth: 0,
        ),
      )
      .module;
}
