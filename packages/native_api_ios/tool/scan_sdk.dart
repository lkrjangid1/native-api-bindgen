import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ios/native_api_ios.dart';
import 'package:native_api_ir/native_api_ir.dart';

void main(List<String> args) {
  final sdk = XcodeLocator().locate()!;
  final fws = args.isEmpty ? ['Foundation', 'UIKit'] : args;
  final sw = Stopwatch()..start();
  final ex = ObjCExtractor(
    libclangPath: sdk.libclangPath,
    sysroot: sdk.path,
    target: 'arm64-apple-ios13.0-simulator',
    sdkVersion: sdk.version,
  );
  ex.parse([for (final f in fws) '$f/$f.h']);
  print('parse ${sw.elapsedMilliseconds} ms, indexed ${ex.typeIds.length}');
  final m = ex.extract(ObjCRequest(frameworks: fws, depth: 0));
  print('extract ${sw.elapsedMilliseconds} ms, types ${m.types.length}');
  print(CoverageReport.of(m).toText());
  final unsupported = <String, int>{};
  for (final t in m.types) {
    for (final n in [...t.methods, ...t.fields]) {
      for (final d in n.diagnostics) {
        unsupported['${d.code}'] = (unsupported['${d.code}'] ?? 0) + 1;
      }
    }
  }
  print(unsupported);
  final v = m.typeById('UIKit.UIView')!;
  print(
    'UIView super=${v.superClass} ifaces=${v.interfaces.length} methods=${v.methods.length} props=${v.properties.length}',
  );
  final init = v.methods.firstWhere((x) => x.name == 'initWithFrame:');
  print(canonicalJson(init.toJson()));
}
