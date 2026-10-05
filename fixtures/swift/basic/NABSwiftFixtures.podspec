# Synthetic Swift fixture module for native-api-bindgen (Apache-2.0).
Pod::Spec.new do |s|
  s.name = 'NABSwiftFixtures'
  s.version = '0.1.0'
  s.summary = 'Synthetic Swift-only APIs used by native-api-bindgen tests.'
  s.homepage = 'https://example.invalid/nab-swift-fixtures'
  s.license = {:type => 'Apache-2.0'}
  s.authors = 'native-api-bindgen'
  s.platforms = {:ios => '15.0'}
  s.source = {:path => '.'}
  s.source_files = 'NABSwiftFixtures.swift'
  s.swift_version = '5.0'
end
