import 'dart:io';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sdk;
  setUp(() {
    sdk = Directory.systemTemp.createTempSync('sdk');
    void platform(String dir, String props, {bool jar = true}) {
      final d = Directory(p.join(sdk.path, 'platforms', dir))
        ..createSync(recursive: true);
      File(p.join(d.path, 'source.properties')).writeAsStringSync(props);
      if (jar) File(p.join(d.path, 'android.jar')).writeAsStringSync('x');
    }

    platform('android-34', 'AndroidVersion.ApiLevel=34\nPkg.Revision=3\n');
    platform('android-36.1', 'AndroidVersion.ApiLevel=36.1\nPkg.Revision=1\n');
    platform(
      'android-Baklava',
      'AndroidVersion.ApiLevel=36\nAndroidVersion.CodeName=Baklava\n',
    );
    platform('android-37', 'AndroidVersion.ApiLevel=37\n', jar: false);
    Directory(
      p.join(sdk.path, 'build-tools', '36.0.0'),
    ).createSync(recursive: true);
    Directory(
      p.join(sdk.path, 'build-tools', '9.0.0'),
    ).createSync(recursive: true);
    Directory(p.join(sdk.path, 'ndk', '28.1.1')).createSync(recursive: true);
  });
  tearDown(() => sdk.deleteSync(recursive: true));

  test('ANDROID_HOME wins over ANDROID_SDK_ROOT and defaults', () {
    final loc = AndroidSdkLocator(
      environment: {'ANDROID_HOME': sdk.path, 'ANDROID_SDK_ROOT': '/nope'},
      homeDir: '/nohome',
    );
    final found = loc.locate()!;
    expect(found.source, 'ANDROID_HOME');
    expect(found.buildTools, ['9.0.0', '36.0.0']);
    expect(found.ndks, ['28.1.1']);
    expect(found.platforms.map((x) => '${x.apiLevel}'), [
      '34',
      '36',
      '36.1',
      '37',
    ]);
  });

  test('ANDROID_SDK_ROOT is honoured; missing SDK returns null', () {
    expect(
      AndroidSdkLocator(
        environment: {'ANDROID_SDK_ROOT': sdk.path},
        homeDir: '/nohome',
      ).locate()!.source,
      'ANDROID_SDK_ROOT',
    );
    expect(
      AndroidSdkLocator(environment: const {}, homeDir: '/nohome').locate(),
      isNull,
    );
  });

  test('auto selects highest stable platform with android.jar', () {
    final s = AndroidSdkLocator(
      environment: {'ANDROID_HOME': sdk.path},
    ).locate()!;
    expect(s.select('auto')!.dirName, 'android-36.1');
    expect(s.select('34')!.apiLevel, const ApiVersion(34));
    expect(s.select('37'), isNull, reason: 'no android.jar');
    expect(s.select('99'), isNull);
  });
}
