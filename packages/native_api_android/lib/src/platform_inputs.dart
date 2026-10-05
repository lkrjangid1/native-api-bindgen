import 'dart:io';

import 'annotations_index.dart';
import 'api_versions.dart';
import 'extractor.dart';
import 'sdk_locator.dart';
import 'zip_reader.dart';

/// Opens all official inputs of an installed platform and returns a ready
/// extractor. Missing optional inputs (annotations.zip) degrade gracefully;
/// a missing `api-versions.xml` disables hidden-API detection, which the
/// caller must surface as a warning.
AndroidApiExtractor openPlatform(AndroidPlatform platform) {
  final jar = JarClassSource.open(platform.androidJar);
  final versions = platform.hasApiVersions
      ? ApiVersionsIndex.parse(File(platform.apiVersionsXml).readAsStringSync())
      : null;
  late final AndroidApiExtractor extractor;
  final annotations = platform.hasAnnotations
      ? AnnotationsIndex(
          ZipReader.open(platform.annotationsZip),
          (n) => extractor.resolveClassName(n),
        )
      : AnnotationsIndex.empty();
  extractor = AndroidApiExtractor(
    classes: jar,
    sdkVersion: '${platform.apiLevel}',
    sourceRevision: platform.revision,
    apiVersions: versions,
    annotations: annotations,
  );
  return extractor;
}
