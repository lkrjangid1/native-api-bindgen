import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('guard'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('writes inside root', () {
    final g = OutputGuard(p.join(tmp.path, 'out'));
    final f = g.writeString('android/content.dart', 'x');
    expect(File(f).readAsStringSync(), 'x');
  });

  test('rejects traversal, absolute, empty segments, NUL', () {
    final g = OutputGuard(tmp.path);
    for (final bad in [
      '../x',
      'a/../../x',
      '/etc/passwd',
      r'C:\x',
      r'a\..\..\x',
      'a//b',
      '',
      'a\u0000b',
      '~/x',
    ]) {
      expect(
        () => g.resolve(bad),
        throwsA(isA<UnsafePathException>()),
        reason: bad,
      );
    }
  });

  test('rejects symlink escapes', () {
    final outside = Directory(p.join(tmp.path, 'outside'))..createSync();
    final root = Directory(p.join(tmp.path, 'root'))..createSync();
    Link(p.join(root.path, 'evil')).createSync(outside.path);
    final g = OutputGuard(root.path);
    expect(
      () => g.writeString('evil/x.dart', 'x'),
      throwsA(isA<UnsafePathException>()),
    );
    expect(File(p.join(outside.path, 'x.dart')).existsSync(), isFalse);
  });
}
