/// Android SDK discovery and API extraction for native-api-bindgen.
///
/// Reads only the locally installed SDK Platform package (`android.jar`,
/// `data/api-versions.xml`, `data/annotations.zip`). Never downloads.
library;

export 'src/annotation_rules.dart';
export 'src/annotations_index.dart';
export 'src/api_versions.dart';
export 'src/classfile/byte_reader.dart' show MalformedInputException;
export 'src/classfile/class_file.dart';
export 'src/classfile/signatures.dart';
export 'src/extractor.dart';
export 'src/kotlin_metadata.dart';
export 'src/platform_inputs.dart';
export 'src/sdk_locator.dart';
export 'src/zip_reader.dart';
