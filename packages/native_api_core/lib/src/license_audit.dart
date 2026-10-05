import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'project_info.dart';

/// Audit outcome, ordered by severity.
enum AuditStatus {
  /// No issue.
  pass('PASS'),

  /// Allowed but noteworthy.
  warn('WARN'),

  /// Cannot be classified confidently; a human must review.
  reviewRequired('REVIEW_REQUIRED'),

  /// Must not be committed / published.
  block('BLOCK');

  const AuditStatus(this.label);

  /// Upper-case label used in output.
  final String label;
}

/// One audit result.
final class AuditFinding implements Comparable<AuditFinding> {
  /// Creates a finding.
  const AuditFinding(this.subject, this.status, this.rule, this.message);

  /// Repository-relative path or `package@version`.
  final String subject;

  /// Status.
  final AuditStatus status;

  /// Stable rule ID.
  final String rule;

  /// Explanation.
  final String message;

  @override
  int compareTo(AuditFinding o) {
    final s = o.status.index.compareTo(status.index);
    if (s != 0) return s;
    final a = subject.compareTo(o.subject);
    return a != 0 ? a : rule.compareTo(o.rule);
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'subject': subject,
    'status': status.label,
    'rule': rule,
    'message': message,
  };
}

/// Dependency license record (TRD §26).
final class DependencyLicense implements Comparable<DependencyLicense> {
  /// Creates a record.
  const DependencyLicense({
    required this.name,
    required this.version,
    required this.source,
    required this.license,
    required this.status,
    this.licenseReference,
  });

  /// Package name.
  final String name;

  /// Version.
  final String version;

  /// `hosted`, `sdk`, `path`, `git`.
  final String source;

  /// SPDX identifier or `UNKNOWN`.
  final String license;

  /// Where the license text was read from (relative to the pub cache).
  final String? licenseReference;

  /// Status.
  final AuditStatus status;

  /// Whether redistribution is permitted under a recognised permissive license.
  bool get redistributionAllowed => status == AuditStatus.pass;

  /// Whether the license requires attribution (all recognised licenses do).
  bool get attributionRequired => license != 'UNKNOWN';

  @override
  int compareTo(DependencyLicense o) {
    final c = name.compareTo(o.name);
    return c != 0 ? c : version.compareTo(o.version);
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    'source': source,
    'license': license,
    if (licenseReference != null) 'licenseReference': licenseReference,
    'redistributionAllowed': redistributionAllowed,
    'attributionRequired': attributionRequired,
    'generatedArtifact': false,
    'documentationCopied': false,
    'status': status.label,
  };
}

/// Aggregated audit result.
final class AuditReport {
  /// Creates a report.
  AuditReport(List<AuditFinding> findings, List<DependencyLicense> deps)
    : findings = List.unmodifiable(findings.toList()..sort()),
      dependencies = List.unmodifiable(deps.toList()..sort());

  /// File findings (non-PASS only).
  final List<AuditFinding> findings;

  /// Dependency records.
  final List<DependencyLicense> dependencies;

  /// Number of files scanned.
  int filesScanned = 0;

  /// Worst status across findings and dependencies.
  AuditStatus get status {
    var s = AuditStatus.pass;
    for (final f in findings) {
      if (f.status.index > s.index) s = f.status;
    }
    for (final d in dependencies) {
      if (d.status.index > s.index) s = d.status;
    }
    return s;
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'status': status.label,
    'filesScanned': filesScanned,
    'findings': [for (final f in findings) f.toJson()],
    'dependencies': [for (final d in dependencies) d.toJson()],
    'disclaimer':
        'Engineering compliance check only; not a substitute for legal advice.',
  };

  /// Text form.
  String toText() {
    final b = StringBuffer()
      ..writeln('License / source audit: ${status.label}')
      ..writeln('Files scanned: $filesScanned');
    if (findings.isNotEmpty) b.writeln();
    for (final f in findings) {
      b.writeln(
        '${f.status.label.padRight(15)} ${f.rule.padRight(28)} ${f.subject}',
      );
      b.writeln('${''.padRight(16)}${f.message}');
    }
    if (dependencies.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Dependencies:');
      for (final d in dependencies) {
        b.writeln(
          '  ${d.status.label.padRight(15)} ${'${d.name} ${d.version}'.padRight(34)} ${d.license} (${d.source})',
        );
      }
    }
    b
      ..writeln()
      ..write(
        'Note: engineering compliance check only; not a substitute for legal advice.',
      );
    return b.toString();
  }
}

const _skipDirs = {
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  '.gradle',
  'Pods',
  '.idea',
};

const _sourceExts = {
  '.dart',
  '.java',
  '.kt',
  '.kts',
  '.swift',
  '.m',
  '.mm',
  '.h',
  '.hpp',
  '.c',
  '.cc',
  '.cpp',
  '.ts',
  '.tsx',
  '.js',
};

const _headerExts = {
  '.h',
  '.hh',
  '.hpp',
  '.m',
  '.mm',
  '.modulemap',
  '.swiftinterface',
};

const _ownLicenseFiles = {
  'LICENSE',
  'NOTICE',
  'THIRD_PARTY_NOTICES.md',
  'LEGAL_RELEASE_REPORT.md',
};

/// Content- and signature-based scanner for restricted artifacts (TRD §86).
final class LicenseAuditor {
  /// Creates an auditor. [pubCache] defaults to `$PUB_CACHE` or `~/.pub-cache`.
  LicenseAuditor({String? pubCache})
    : pubCache = pubCache ?? _defaultPubCache();

  /// Pub cache root used to read dependency licenses (offline).
  final String pubCache;

  /// Max bytes read per file for content checks.
  static const maxReadBytes = 2 * 1024 * 1024;

  /// Audits [root]. Uses `git ls-files` when [root] is a Git work tree so that
  /// ignored local output is not reported; otherwise walks the directory.
  AuditReport audit(String root, {bool dependencies = true}) {
    final files = _listFiles(root);
    final allow = _loadAllowlist(root);
    final findings = <AuditFinding>[];
    final lockfiles = <String>[];
    for (final rel in files) {
      var fileFindings = scanFile(root, rel);
      final entry = allow[rel];
      if (entry != null && fileFindings.isNotEmpty) {
        fileFindings = _applyAllowlist(root, rel, entry, fileFindings);
      }
      findings.addAll(fileFindings);
      if (p.basename(rel) == 'pubspec.lock') lockfiles.add(rel);
    }
    final deps = dependencies
        ? _auditLockfiles(root, lockfiles)
        : <DependencyLicense>[];
    return AuditReport(findings, deps)..filesScanned = files.length;
  }

  /// SHA-256 (hex) of [f].
  static String sha256Of(File f) =>
      sha256.convert(f.readAsBytesSync()).toString();

  /// File name of the reviewed-exceptions list at the audit root.
  static const allowlistFile = 'license-audit-allowlist.yaml';

  /// Reads `license-audit-allowlist.yaml`: entries pinned by SHA-256 that a
  /// human reviewed. Missing file = no exceptions.
  Map<String, Map<Object?, Object?>> _loadAllowlist(String root) {
    final f = File(p.join(root, allowlistFile));
    if (!f.existsSync()) return const {};
    final doc = loadYaml(f.readAsStringSync());
    final entries = doc is Map ? doc['entries'] : null;
    if (entries is! List) return const {};
    return {
      for (final e in entries)
        if (e is Map && e['path'] is String) e['path'] as String: e,
    };
  }

  /// Waives WARN / REVIEW_REQUIRED findings for an allowlisted file whose
  /// checksum matches. BLOCK findings are never waived; a checksum mismatch
  /// is itself a BLOCK.
  List<AuditFinding> _applyAllowlist(
    String root,
    String rel,
    Map<Object?, Object?> entry,
    List<AuditFinding> found,
  ) {
    final digest = sha256
        .convert(File(p.join(root, rel)).readAsBytesSync())
        .toString();
    final pinned = '${entry['sha256'] ?? ''}'.toLowerCase();
    final complete =
        entry['license'] is String && entry['justification'] is String;
    if (pinned != digest || !complete) {
      return [
        ...found,
        AuditFinding(
          rel,
          AuditStatus.block,
          'allowlist-mismatch',
          'Allowlisted file changed or entry incomplete (sha256 $digest); re-review it.',
        ),
      ];
    }
    return [
      for (final f in found)
        if (f.status == AuditStatus.block) f,
    ];
  }

  /// Scans one file. Returns non-PASS findings.
  List<AuditFinding> scanFile(String root, String rel) {
    final out = <AuditFinding>[];
    void add(AuditStatus s, String rule, String msg) =>
        out.add(AuditFinding(rel, s, rule, msg));

    final segments = p.split(rel);
    if (segments.any(
      (s) => s.endsWith('.framework') || s.endsWith('.xcframework'),
    )) {
      add(
        AuditStatus.block,
        'apple-framework-bundle',
        'Framework bundles must never be committed (docs/legal/apple.md).',
      );
    }
    final file = File(p.join(root, rel));
    if (!file.existsSync()) return out;
    final length = file.lengthSync();
    final bytes = _readHead(file, maxReadBytes);
    final base = p.basename(rel);
    final ext = p.extension(rel).toLowerCase();

    // Binary signatures.
    if (bytes.length >= 8) {
      final magic = _u32(bytes, 0);
      if (const {
        0xFEEDFACE,
        0xFEEDFACF,
        0xCEFAEDFE,
        0xCFFAEDFE,
      }.contains(magic)) {
        add(
          AuditStatus.block,
          'mach-o-binary',
          'Mach-O binary detected by signature.',
        );
      } else if (magic == 0xCAFEBABE) {
        if (_u32(bytes, 4) < 45) {
          add(
            AuditStatus.block,
            'mach-o-binary',
            'Universal (fat) Mach-O binary detected by signature.',
          );
        } else {
          add(
            AuditStatus.block,
            'jvm-class-file',
            'Compiled JVM class file; SDK classes must not be committed.',
          );
        }
      } else if (magic == 0x504B0304 && (ext == '.jar' || ext == '.aar')) {
        final text = latin1.decode(bytes);
        if (base == 'android.jar' ||
            text.contains('android/app/Activity.class')) {
          add(
            AuditStatus.block,
            'android-sdk-jar',
            'Android SDK platform jar detected.',
          );
        } else {
          add(
            AuditStatus.reviewRequired,
            'binary-archive',
            'Binary archive; license cannot be classified automatically.',
          );
        }
      }
    }
    if (_isBinary(bytes)) return out;
    final text = utf8.decode(bytes, allowMalformed: true);

    if (ext == '.tbd' && text.contains('--- !tapi-tbd')) {
      add(
        AuditStatus.block,
        'apple-sdk-stub',
        'Apple text-based dylib stub (.tbd) from an SDK.',
      );
    }
    if (_headerExts.contains(ext) && _appleBanner.hasMatch(text)) {
      add(
        AuditStatus.block,
        'apple-sdk-header',
        'Header carries an Apple copyright banner typical of SDK headers.',
      );
    }
    if (text.contains(_xcodePlatforms) && text.contains('.sdk/')) {
      add(
        AuditStatus.warn,
        'xcode-sdk-path',
        'Contains an absolute Xcode SDK path; generated output must not embed machine paths.',
      );
    }
    if ((ext == '.html' || ext == '.htm' || ext == '.md' || ext == '.txt') &&
        (text.contains(_androidDocsFooter) ||
            _appleDocsFooter.hasMatch(text))) {
      add(
        AuditStatus.block,
        'copied-platform-docs',
        'Looks like copied platform documentation; link to it instead.',
      );
    } else if ((ext == '.html' || ext == '.htm') && length > 512 * 1024) {
      add(
        AuditStatus.warn,
        'large-doc-dump',
        'Large HTML document; verify it is project-authored.',
      );
    }
    if (_sourceExts.contains(ext) && !_ownLicenseFiles.contains(base)) {
      final head = text.length > 4096 ? text.substring(0, 4096) : text;
      final spdx = _spdx.firstMatch(head)?.group(1);
      if (spdx != null && spdx != 'Apache-2.0') {
        add(
          AuditStatus.reviewRequired,
          'foreign-spdx',
          'SPDX license $spdx differs from the project license.',
        );
      } else if (_copyright.hasMatch(head)) {
        add(
          AuditStatus.reviewRequired,
          'third-party-license-header',
          'Copyright header from a third party; record it in THIRD_PARTY_NOTICES.md.',
        );
      }
    }
    if (text.startsWith('// ${ProjectInfo.generatedMarker}') &&
        (text.contains('// Source SDK: Android API') ||
            (text.contains('// Source SDK: Apple SDK') &&
                !text.contains('// Source SDK: Apple SDK fixture')))) {
      add(
        AuditStatus.warn,
        'generated-sdk-binding',
        'Generated binding derived from a locally installed platform SDK (LEGAL_REVIEW_REQUIRED before redistribution).',
      );
    }
    // Clang AST dumps / precompiled headers embed SDK header contents.
    if (ext == '.pch' ||
        ext == '.pcm' ||
        ext == '.ast' ||
        (ext == '.json' && text.contains(_clangAstMarker))) {
      add(
        AuditStatus.block,
        'clang-ast-dump',
        'Clang AST dump or precompiled header derived from SDK headers; never commit it.',
      );
    }
    final top = segments.first;
    if ((top == 'third_party' || top == 'vendor') &&
        !File(
          p.join(root, top, segments.length > 1 ? segments[1] : '', 'LICENSE'),
        ).existsSync()) {
      add(
        AuditStatus.reviewRequired,
        'unknown-third-party',
        'Vendored file without an accompanying LICENSE.',
      );
    }
    return out;
  }

  List<DependencyLicense> _auditLockfiles(String root, List<String> lockfiles) {
    final byKey = SplayTreeMap<String, DependencyLicense>();
    for (final rel in lockfiles) {
      final Object? doc;
      try {
        doc = loadYaml(File(p.join(root, rel)).readAsStringSync());
      } on YamlException {
        continue;
      }
      if (doc is! Map || doc['packages'] is! Map) continue;
      final pkgs = doc['packages'] as Map;
      for (final e in pkgs.entries) {
        final name = '${e.key}';
        final info = e.value;
        if (info is! Map) continue;
        final version = '${info['version']}';
        final source = '${info['source']}';
        byKey.putIfAbsent(
          '$name@$version',
          () => _classifyDependency(name, version, source),
        );
      }
    }
    return byKey.values.toList();
  }

  DependencyLicense _classifyDependency(
    String name,
    String version,
    String source,
  ) {
    if (source == 'sdk') {
      return DependencyLicense(
        name: name,
        version: version,
        source: source,
        license: 'SDK (BSD-3-Clause)',
        status: AuditStatus.pass,
      );
    }
    if (source == 'path') {
      return DependencyLicense(
        name: name,
        version: version,
        source: source,
        license: 'project',
        status: AuditStatus.pass,
      );
    }
    if (source != 'hosted') {
      return DependencyLicense(
        name: name,
        version: version,
        source: source,
        license: 'UNKNOWN',
        status: AuditStatus.reviewRequired,
      );
    }
    final dir = p.join(pubCache, 'hosted', 'pub.dev', '$name-$version');
    for (final f in const ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING']) {
      final file = File(p.join(dir, f));
      if (file.existsSync()) {
        final id = classifyLicenseText(file.readAsStringSync());
        return DependencyLicense(
          name: name,
          version: version,
          source: source,
          license: id,
          licenseReference: 'pub.dev/$name-$version/$f',
          status: _permissive.contains(id)
              ? AuditStatus.pass
              : id == 'UNKNOWN'
              ? AuditStatus.reviewRequired
              : AuditStatus.warn,
        );
      }
    }
    return DependencyLicense(
      name: name,
      version: version,
      source: source,
      license: 'UNKNOWN',
      status: AuditStatus.reviewRequired,
    );
  }
}

const _permissive = {
  'Apache-2.0',
  'BSD-3-Clause',
  'BSD-2-Clause',
  'MIT',
  'Zlib',
  'ISC',
};

/// Classifies a license text into an SPDX ID or `UNKNOWN`. Conservative:
/// unrecognised text is never assumed permissive.
String classifyLicenseText(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ');
  if (t.contains('Apache License') && t.contains('Version 2.0')) {
    return 'Apache-2.0';
  }
  if (t.contains('GNU GENERAL PUBLIC LICENSE')) return 'GPL';
  if (t.contains('GNU LESSER GENERAL PUBLIC LICENSE')) return 'LGPL';
  if (t.contains('Mozilla Public License')) return 'MPL-2.0';
  if (t.contains('Redistribution and use in source and binary forms')) {
    return t.contains('Neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (t.contains('Permission is hereby granted, free of charge')) return 'MIT';
  if (t.contains(
    'Permission to use, copy, modify, and/or distribute this software',
  )) {
    return 'ISC';
  }
  if (t.contains('This software is provided \'as-is\'')) return 'Zlib';
  return 'UNKNOWN';
}

// `clang -ast-dump=json` root node.
final _clangAstMarker = RegExp(r'"kind"\s*:\s*"TranslationUnitDecl"');
final _appleBanner = RegExp(
  r'Copyright \(c\)[^\n]{0,40}Apple(,)? Inc',
  caseSensitive: false,
);
final _appleDocsFooter = RegExp(
  r'Copyright © \d{4} Apple Inc\. All rights reserved\.',
);
const _androidDocsFooter =
    'Content and code samples on this page are subject to the licenses described in the Content License';
// Split so this file does not match its own rules.
const _xcodePlatforms =
    '/Applications/Xcode.app/Contents/'
    'Developer/Platforms/';
final _spdx = RegExp(r'SPDX-License-Identifier:\s*([A-Za-z0-9.\-+]+)');
final _copyright = RegExp(r'^\s*(//|\*|#|/\*)\s*Copyright\b', multiLine: true);

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

bool _isBinary(Uint8List b) {
  final n = b.length < 8000 ? b.length : 8000;
  for (var i = 0; i < n; i++) {
    if (b[i] == 0) return true;
  }
  return false;
}

Uint8List _readHead(File f, int max) {
  final raf = f.openSync();
  try {
    return raf.readSync(max);
  } finally {
    raf.closeSync();
  }
}

List<String> _listFiles(String root) {
  try {
    final r = Process.runSync('git', [
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ], workingDirectory: root);
    if (r.exitCode == 0) {
      final out = r.stdout as String;
      final files =
          out.split('\u0000').where((s) => s.isNotEmpty).toSet().toList()
            ..sort();
      return files;
    }
  } on ProcessException {
    // Fall through to directory walk.
  }
  final out = <String>[];
  void walk(Directory d) {
    for (final e in d.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        if (!_skipDirs.contains(name)) {
          if (name.endsWith('.framework') || name.endsWith('.xcframework')) {
            out.add(p.relative(e.path, from: root));
          }
          walk(e);
        }
      } else if (e is File) {
        out.add(p.relative(e.path, from: root));
      }
    }
  }

  walk(Directory(root));
  return out..sort();
}

String _defaultPubCache() {
  final env = Platform.environment['PUB_CACHE'];
  if (env != null && env.isNotEmpty) return env;
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  return Platform.isWindows
      ? p.join(Platform.environment['LOCALAPPDATA'] ?? home, 'Pub', 'Cache')
      : p.join(home, '.pub-cache');
}
