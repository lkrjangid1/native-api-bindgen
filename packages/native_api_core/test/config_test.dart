import 'package:native_api_core/native_api_core.dart';
import 'package:test/test.dart';

void main() {
  test('default YAML parses to safe defaults', () {
    final c = BindgenConfig.parse(BindgenConfig.defaultYaml());
    expect(c.android.minApi, 24);
    expect(c.android.entries, ['android.content.Intent']);
    expect(c.generatedArtifacts, GeneratedArtifactsPolicy.localOnly);
    expect(c.docs, DocumentationMode.linksOnly);
    expect(c.mode, GenerationMode.strictNative);
    expect(c.reactNative, isFalse);
  });

  test('empty file yields defaults', () {
    expect(BindgenConfig.parse('').outputDir, 'lib/src/generated');
  });

  test('rejects unknown keys, bad names and bad enums', () {
    expect(
      () => BindgenConfig.parse('platfrom: {}'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => BindgenConfig.parse('platform: {android: {include: ["a b"]}}'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => BindgenConfig.parse('generation: {mode: fast}'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => BindgenConfig.parse('platform: {android: {depth: 99}}'),
      throwsA(isA<ConfigException>()),
    );
    expect(() => BindgenConfig.parse('a: [}'), throwsA(isA<ConfigException>()));
  });

  test('fingerprint changes with output-affecting options', () {
    final a = BindgenConfig.parse('platform: {android: {minApi: 21}}');
    final b = BindgenConfig.parse('platform: {android: {minApi: 24}}');
    expect(a.fingerprint, isNot(b.fingerprint));
  });
}
