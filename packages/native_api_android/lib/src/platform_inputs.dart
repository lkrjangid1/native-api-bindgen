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
///
/// [libraries] (jars, AARs or class directories, e.g. compiled Kotlin
/// libraries) are added after the platform; their classes are extracted as
/// library APIs (see [AndroidApiExtractor.libraryClasses]).
AndroidApiExtractor openPlatform(
  AndroidPlatform platform, {
  List<String> libraries = const [],
}) {
  final platformJar = JarClassSource.open(platform.androidJar);
  final libs = [for (final l in libraries) openLibrary(l)];
  final ClassSource jar = libs.isEmpty
      ? platformJar
      : CompositeClassSource([platformJar, ...libs]);
  final sdkNames = platformJar.classNames.toSet();
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
    libraryClasses: {
      for (final l in libs)
        for (final c in l.classNames)
          if (!sdkNames.contains(c)) c,
    },
  );
  return extractor;
}
