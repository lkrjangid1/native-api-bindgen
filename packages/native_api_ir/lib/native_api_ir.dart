/// Canonical Native IR for native-api-bindgen.
///
/// The IR is the single source of truth between platform parsers and target
/// generators. It is platform-neutral, JSON-serializable and deterministic.
library;

export 'src/diagnostics.dart';
export 'src/json_util.dart' show canonicalJson, maxJsonDepth;
export 'src/metadata.dart';
export 'src/nodes.dart';
export 'src/symbol_id.dart';
export 'src/types.dart';
export 'src/validate.dart';
