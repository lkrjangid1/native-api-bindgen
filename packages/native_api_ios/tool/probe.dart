import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:native_api_ios/src/libclang.dart';

void main(List<String> args) {
  final xc = Process.runSync('xcode-select', ['-p']).stdout.toString().trim();
  final lib = LibClang(
    '$xc/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib',
  );
  final sdk = Process.runSync('xcrun', [
    '--sdk',
    'iphonesimulator',
    '--show-sdk-path',
  ]).stdout.toString().trim();
  final idx = lib.createIndex(0, 0);
  final argv = [
    '-x',
    'objective-c',
    '-isysroot',
    sdk,
    '-target',
    'arm64-apple-ios13.0-simulator',
    '-fobjc-arc',
  ];
  final cargs = calloc<Pointer<Char>>(argv.length);
  for (var i = 0; i < argv.length; i++) {
    cargs[i] = argv[i].toNativeUtf8().cast();
  }
  final sw = Stopwatch()..start();
  final tu = lib.parseTranslationUnit(
    idx,
    args.first.toNativeUtf8().cast(),
    cargs,
    argv.length,
    nullptr,
    0,
    64 | 0x1000 | 0x2000,
  );
  print(
    'parse ${sw.elapsedMilliseconds}ms tu=$tu diags=${lib.getNumDiagnostics(tu)}',
  );
  final root = lib.getTranslationUnitCursor(tu);
  final top = lib.children(root);
  print('top-level cursors: ${top.length}');
  for (final c in top) {
    final kind = lib.getCursorKind(c);
    final name = lib.str(lib.getCursorSpelling(c));
    if (args.length > 1 ? name != args[1] : !name.startsWith('NAB')) continue;
    {
      final avail = calloc<CXPlatformAvailability>(8);
      final n = lib.platformAvailability(
        c,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        avail,
        8,
      );
      print(
        'CLASS AVAIL ${[for (var i = 0; i < n; i++) '${lib.str(avail[i].platform)}:${avail[i].introduced.major}.${avail[i].introduced.minor} dep:${avail[i].deprecated.major}.${avail[i].deprecated.minor} obs:${avail[i].obsoleted.major} unav:${avail[i].unavailable}'].join(' | ')}',
      );
    }
    print('$kind $name file=${lib.fileOf(c).split('/').last}');
    for (final m in lib.children(c)) {
      final mk = lib.getCursorKind(m);
      final mn = lib.str(lib.getCursorSpelling(m));
      final avail = calloc<CXPlatformAvailability>(8);
      final n = lib.platformAvailability(
        m,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        avail,
        8,
      );
      final av = [
        for (var i = 0; i < n; i++)
          '${lib.str(avail[i].platform)}:${avail[i].introduced.major}.${avail[i].introduced.minor} dep:${avail[i].deprecated.major}',
      ];
      calloc.free(avail);
      final t = mk == 16 || mk == 17
          ? lib.getCursorResultType(m)
          : lib.getCursorType(m);
      print(
        '   $mk $mn ${lib.str(lib.getTypeSpelling(t))} null=${lib.getNullability(t)} kind=${t.kind} $av',
      );
      if (mk == 16 || mk == 17) {
        for (var i = 0; i < lib.getNumArguments(m); i++) {
          final a = lib.getArgument(m, i);
          final at = lib.getCursorType(a);
          print(
            '       arg ${lib.str(lib.getCursorSpelling(a))} ${lib.str(lib.getTypeSpelling(at))} null=${lib.getNullability(at)} kind=${at.kind}',
          );
        }
      }
    }
  }
}
