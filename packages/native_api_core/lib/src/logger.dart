import 'dart:convert';
import 'dart:io';

import 'package:native_api_ir/native_api_ir.dart';

/// Log levels in increasing severity.
enum LogLevel {
  /// Verbose detail (`--verbose`).
  debug,

  /// Normal progress.
  info,

  /// Something was approximated or skipped.
  warn,

  /// Failure.
  error,
}

/// Structured logger. Text mode prints `LEVEL message`; JSON mode prints one
/// JSON object per line (`{"level":..,"event":..,"message":..,...}`) so the
/// output is machine-readable. Command results go through [result].
final class Logger {
  /// Creates a logger writing to [out] (results) and [err] (logs).
  Logger({
    this.json = false,
    this.verbose = false,
    this.quiet = false,
    IOSink? out,
    IOSink? err,
  }) : _out = out ?? stdout,
       _err = err ?? stderr;

  /// JSON mode.
  final bool json;

  /// Include debug logs.
  final bool verbose;

  /// Only warnings and errors.
  final bool quiet;

  final IOSink _out;
  final IOSink _err;

  /// Whether [level] would be emitted.
  bool enabled(LogLevel level) {
    if (level == LogLevel.debug) return verbose;
    if (quiet) return level.index >= LogLevel.warn.index;
    return true;
  }

  /// Emits a log record.
  void log(
    LogLevel level,
    String message, {
    String event = 'log',
    Map<String, Object?> data = const {},
  }) {
    if (!enabled(level)) return;
    if (json) {
      _err.writeln(
        jsonEncode({
          'level': level.name,
          'event': event,
          'message': message,
          if (data.isNotEmpty) 'data': data,
        }),
      );
    } else {
      _err.writeln('${level.name.toUpperCase().padRight(5)} $message');
    }
  }

  /// Debug log.
  void debug(String m, {String event = 'log'}) =>
      log(LogLevel.debug, m, event: event);

  /// Info log.
  void info(String m, {String event = 'log'}) =>
      log(LogLevel.info, m, event: event);

  /// Warning log.
  void warn(String m, {String event = 'log'}) =>
      log(LogLevel.warn, m, event: event);

  /// Error log.
  void error(String m, {String event = 'log'}) =>
      log(LogLevel.error, m, event: event);

  /// Logs a diagnostic at a level matching its severity.
  void diagnostic(Diagnostic d) => log(
    switch (d.severity) {
      Severity.info => LogLevel.debug,
      Severity.warning => LogLevel.warn,
      Severity.error => LogLevel.error,
    },
    d.toString(),
    event: 'diagnostic',
    data: d.toJson(),
  );

  /// Writes a command result: [text] in text mode, [data] in JSON mode.
  void result(String text, Map<String, Object?> data) {
    if (json) {
      _out.writeln(canonicalJson(data).trimRight());
    } else if (text.isNotEmpty) {
      _out.writeln(text);
    }
  }
}
