import 'dart:io';

import 'package:native_api_ios/native_api_ios.dart';

/// Dev tool: `dart run tool/swift_try.dart <swift source> <out dir>`.
void main(List<String> args) {
  final sdk = XcodeLocator().locate()!;
  final tc = SwiftToolchain(sdk);
  final mod = tc.emitModule('NABSwiftFixtures', [args[0]], '${args[1]}/mod');
  final sg = tc.extractSymbolGraph(
    'NABSwiftFixtures',
    '${args[1]}/sg',
    includeDirs: [File(mod).parent.path],
  );
  final out = SwiftAdapterGenerator(SwiftModuleGraph.read(sg)).generate();
  File(
    '${args[1]}/NABSwiftFixturesAdapters.swift',
  ).writeAsStringSync(out.swift);
  File('${args[1]}/NABSwiftFixturesAdapters.h').writeAsStringSync(out.header);
  for (final t in out.module.types) {
    stdout.writeln(
      '${t.id} ${t.support.name} ${t.diagnostics.map((d) => d.code.code).join(',')}',
    );
    for (final m in t.methods) {
      stdout.writeln(
        '  ${m.name} ${m.support.name} ${m.nativeDescriptor ?? ''} ${m.diagnostics.map((d) => '${d.code.code}: ${d.message}').join('; ')}',
      );
    }
  }
}
