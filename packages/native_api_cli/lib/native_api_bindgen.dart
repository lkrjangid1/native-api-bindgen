/// Command-line interface of native-api-bindgen.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

import 'src/commands.dart';
import 'src/context.dart';

export 'src/context.dart' show ExitCodes;

/// Runs the CLI with [args]; returns the process exit code. [out]/[err] and
/// [environment] are injectable for tests.
Future<int> runCli(
  List<String> args, {
  IOSink? out,
  IOSink? err,
  Map<String, String>? environment,
  String? workingDirectory,
}) async {
  final runner = CommandRunner<int>(
    ProjectInfo.name,
    'Generate typed bindings for supported public platform SDK APIs from the SDKs installed on this machine.\n\n'
    '${ProjectInfo.disclaimer}',
  );
  runner.argParser
    ..addFlag(
      'json',
      negatable: false,
      help:
          'Machine-readable output (results on stdout, logs as JSON lines on stderr).',
    )
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Show debug logs.')
    ..addFlag(
      'quiet',
      abbr: 'q',
      negatable: false,
      help: 'Only warnings and errors.',
    )
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addOption(
      'project',
      help: 'Project directory (default: current directory).',
    )
    ..addOption(
      'config',
      help:
          'Configuration file (default: <project>/${ProjectInfo.configFileName}).',
    );

  final commands = <BindgenCommand>[
    InitCommand(),
    DetectCommand(),
    DetectCommand(doctor: true),
    InspectCommand(),
    GenerateCommand(),
    UpdateCommand(),
    DiffCommand(),
    CoverageCommand(),
    GraphCommand(),
    ExplainCommand(
      'explain',
      'Explain a symbol: signature, availability, annotations, provenance and support.',
    ),
    ExplainCommand(
      'why-generated',
      'Show how a symbol was generated: native symbol, SDK, parser, generator, output file, runtime adapter.',
    ),
    ExplainCommand(
      'why-skipped',
      'Show the reason codes for a symbol that was not generated.',
    ),
    DocsCommand(),
    AuditCommand(),
    VerifyReproducibleCommand(),
    CleanCommand(),
  ];
  commands.forEach(runner.addCommand);

  final ArgResults parsed;
  try {
    parsed = runner.parse(args);
  } on UsageException catch (e) {
    (err ?? stderr).writeln(e);
    return ExitCodes.usage;
  }
  final logger = Logger(
    json: parsed['json'] as bool,
    verbose: parsed['verbose'] as bool,
    quiet: parsed['quiet'] as bool,
    out: out,
    err: err,
  );
  if (parsed['version'] as bool) {
    logger.result('${ProjectInfo.name} ${ProjectInfo.generatorVersion}', {
      'version': ProjectInfo.generatorVersion,
    });
    return ExitCodes.ok;
  }
  final project = p.normalize(
    p.absolute(
      workingDirectory ?? Directory.current.path,
      (parsed['project'] as String?) ?? '.',
    ),
  );
  final ctx = CliContext(
    logger: logger,
    projectDir: project,
    configPath: p.normalize(
      p.absolute(
        project,
        (parsed['config'] as String?) ?? ProjectInfo.configFileName,
      ),
    ),
    environment: environment,
  );
  for (final c in commands) {
    c.ctx = ctx;
  }
  try {
    // Validate configuration up front so mistakes are never silently ignored
    // (except for `init`, which may be used to replace a broken file).
    if (parsed.command?.name != 'init') ctx.config;
    return await runner.runCommand(parsed) ?? ExitCodes.ok;
  } on UsageException catch (e) {
    (err ?? stderr).writeln(e);
    return ExitCodes.usage;
  } on CliFailure catch (f) {
    logger.diagnostic(f.diagnostic);
    logger.result('', {'status': 'error', 'diagnostic': f.diagnostic.toJson()});
    return f.exitCode;
  } on UnsafePathException catch (e) {
    logger.diagnostic(
      Diagnostic(
        DiagnosticCode.unsafePath,
        e.toString(),
        severity: Severity.error,
      ),
    );
    return ExitCodes.failure;
  }
}
