import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_core/native_api_core.dart';

void main(List<String> args) {
  final sw = Stopwatch()..start();
  final sdk = AndroidSdkLocator().locate()!;
  final plat = sdk.select(args.isEmpty ? 'auto' : args.first)!;
  final ex = openPlatform(plat);
  final r = ex.extract(
    ExtractionRequest(classes: ex.classes.classNames, depth: 0),
  );
  print(
    'platform ${plat.dirName}: ${sw.elapsedMilliseconds}ms types=${r.module.types.length}',
  );
  print(CoverageReport.of(r.module).toText());
  final codes = <String, int>{};
  for (final d in r.module.allDiagnostics) {
    codes['${d.code}'] = (codes['${d.code}'] ?? 0) + 1;
  }
  print(codes);
  print(
    r.module.allDiagnostics
        .where((d) => d.code.code == 'E006')
        .take(8)
        .join('\n'),
  );
  print(
    r.module.allDiagnostics
        .where((d) => d.code.code == 'E008')
        .take(8)
        .join('\n'),
  );
}
