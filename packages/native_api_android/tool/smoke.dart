import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_ir/native_api_ir.dart';

void main(List<String> args) {
  final sw = Stopwatch()..start();
  final sdk = AndroidSdkLocator().locate()!;
  final plat = sdk.select(args.isEmpty ? '36' : args.first)!;
  final ex = openPlatform(plat);
  print(
    'open: ${sw.elapsedMilliseconds}ms classes=${ex.classes.classNames.length}',
  );
  final r = ex.extract(
    const ExtractionRequest(
      entries: [
        'android.content.Intent',
        'android.net.Uri',
        'android.os.Bundle',
        'android.os.Handler',
        'android.os.Looper',
        'android.app.Activity',
      ],
      depth: 0,
    ),
  );
  print('extract: ${sw.elapsedMilliseconds}ms types=${r.module.types.length}');
  for (final t in r.module.types) {
    final hidden = [
      ...t.methods,
      ...t.fields,
    ].where((m) => m.visibility != ApiVisibility.public).length;
    print(
      '${t.id} ${t.kind.name} av=${t.availability.introduced} methods=${t.methods.length} fields=${t.fields.length} hidden=$hidden super=${t.superClass}',
    );
  }
  final intent = r.module.typeById('android.content.Intent')!;
  final m = intent.methods.firstWhere((m) => m.name == 'setData');
  print(canonicalJson(m.toJson()));
  print(r.diagnostics.take(10).join('\n'));
  final h = r.module.allDiagnostics
      .where((d) => d.code == DiagnosticCode.nonSdkApi)
      .take(10);
  print(h.join('\n'));
  final ctx = r.module.typeById('android.content.Context');
  print(
    ctx?.methods
        .firstWhere(
          (m) =>
              m.name == 'getSystemService' &&
              m.parameters.first.type.erasedId == 'java.lang.String',
        )
        .toJson(),
  );
}
