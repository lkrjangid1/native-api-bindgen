import 'package:native_api_ir/native_api_ir.dart';

/// Centralized project identity. Rename the project here only.
abstract final class ProjectInfo {
  /// Display / CLI name.
  static const name = 'native-api-bindgen';

  /// Human-readable product name.
  static const displayName = 'Native API Bindgen';

  /// Published Dart package name of the CLI.
  static const cliPackage = 'native_api_bindgen';

  /// Generator version (SemVer). Keep in sync with package pubspecs.
  static const generatorVersion = '0.1.0-dev.1';

  /// Version of the runtime contract generated code expects.
  static const runtimeVersion = '0.1.0-dev.1';

  /// IR schema version.
  static const irSchema = irSchemaVersion;

  /// Default configuration file name.
  static const configFileName = 'native_api_bindgen.yaml';

  /// Default directory for intermediate artifacts (IR, coverage, maps).
  static const stateDirName = '.native_api_bindgen';

  /// Marker on the first line of every generated file.
  static const generatedMarker = 'GENERATED CODE - DO NOT MODIFY BY HAND.';

  /// Non-affiliation statement.
  static const disclaimer =
      '$displayName is an independent open-source project. It is not '
      'affiliated with or endorsed by Google, Apple, Meta, or the Dart/Flutter '
      'project.';
}
