#!/usr/bin/env python3
"""Release-APK size benchmark for generated bindings (TRD §34).

Builds several minimal Flutter apps into a temporary directory and reports
APK and per-component sizes. Every number printed is measured from the
built artifacts; nothing is estimated.

Variants:
  baseline         `flutter create` app, no native-api-bindgen
  imported-unused  slice bindings + runtime imported, no API called
  one-api-slice    Context.getPackageName() via slice bindings (24 types)
  one-api-fullsdk  same call, but bindings generated for EVERY android.jar
                   package (proves unused generated APIs are tree-shaken)
  slice-example    examples/flutter/android_slice (all demos)

With --aab, builds release app bundles (`flutter build appbundle`) instead
and reports the .aab size and arm64 libapp.so inside it (baseline,
one-api-slice and one-api-fullsdk only).

Usage: tools/measure_size.py [--platform 36] [--keep] [--aab]
Requires Flutter, an Android SDK with the platform installed, and a JDK.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(ROOT, "runtimes", "dart", "native_api_runtime")
SLICE_ENTRIES = [
    "android.content.Intent", "android.net.Uri", "android.os.Bundle",
    "android.content.Context", "android.app.Activity", "android.os.Handler",
    "android.os.Looper", "java.lang.Runnable", "android.os.Handler.Callback",
    "android.os.Message",
]

ONE_API_MAIN = """
import 'package:flutter/material.dart';
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart' as jf;
import 'src/generated/bindings.dart' as android;

void main() {
  final ctx = jf.androidApplicationContext.as(android.Context.type);
  final name = ctx.getPackageName()!.toDartString(releaseOriginal: true);
  runApp(MaterialApp(home: Text(name)));
}
"""

BASELINE_MAIN = """
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: Text('baseline')));
"""

UNUSED_MAIN = """
import 'package:flutter/material.dart';
// ignore: unused_import
import 'src/generated/bindings.dart' as android;

void main() => runApp(const MaterialApp(home: Text('unused')));
"""


def run(cmd, cwd=None, quiet=True):
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit(f"command failed: {' '.join(cmd)}")
    return r.stdout


def pubspec(name, with_bindings):
    deps = ""
    if with_bindings:
        deps = f"""  jni: ^1.0.3
  jni_flutter: ^1.0.3
  native_api_runtime:
    path: {RUNTIME}
"""
    return f"""name: {name}
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
{deps}
flutter:
  uses-material-design: true
"""


def all_packages(platform):
    sdk = os.environ.get("ANDROID_HOME") or os.path.expanduser("~/Library/Android/sdk")
    jar = os.path.join(sdk, "platforms", f"android-{platform}", "android.jar")
    names = zipfile.ZipFile(jar).namelist()
    return sorted({n.rsplit("/", 1)[0].replace("/", ".") for n in names
                   if n.endswith(".class") and "/" in n and not n.startswith("META-INF")})


def generate(project, platform, entries=None, packages=None):
    args = ["dart", "run", "native_api_bindgen", "--quiet", "--project", project,
            "generate", "flutter", "--platform", str(platform), "--depth", "0"]
    for e in entries or []:
        args += ["--entry", e]
    for p in packages or []:
        args += ["--package", p]
    run(args, cwd=ROOT)


def build_aab(project):
    run(["flutter", "pub", "get"], cwd=project)
    run(["flutter", "build", "appbundle", "--release"], cwd=project)
    aab = os.path.join(project, "build", "app", "outputs", "bundle", "release", "app-release.aab")
    z = zipfile.ZipFile(aab)
    sizes = {i.filename: i.file_size for i in z.infolist()}
    return {
        "aab_bytes": os.path.getsize(aab),
        "libapp_so_arm64_bytes": sizes.get("base/lib/arm64-v8a/libapp.so", 0),
        "libdartjni_so_arm64_bytes": sizes.get("base/lib/arm64-v8a/libdartjni.so", 0),
        "dex_bytes": sum(v for k, v in sizes.items() if k.endswith(".dex")),
    }


def build(project):
    run(["flutter", "pub", "get"], cwd=project)
    run(["flutter", "build", "apk", "--release", "--target-platform", "android-arm64"], cwd=project)
    apk = os.path.join(project, "build", "app", "outputs", "flutter-apk", "app-release.apk")
    z = zipfile.ZipFile(apk)
    sizes = {i.filename: (i.file_size, i.compress_size) for i in z.infolist()}

    def pick(suffix):
        return sum(v[0] for k, v in sizes.items() if k.endswith(suffix))

    return {
        "apk_bytes": os.path.getsize(apk),
        "libapp_so_bytes": pick("libapp.so"),
        "libflutter_so_bytes": pick("libflutter.so"),
        "libdartjni_so_bytes": pick("libdartjni.so"),
        "dex_bytes": sum(v[0] for k, v in sizes.items() if k.endswith(".dex")),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", default="36")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--aab", action="store_true")
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix="nab_size_")
    results = {}
    try:
        template = os.path.join(work, "template")
        run(["flutter", "create", "--platforms=android", "--project-name", "sizeapp", template])

        def variant(name, with_bindings, main_src, entries=None, packages=None):
            d = os.path.join(work, name)
            shutil.copytree(template, d, ignore=shutil.ignore_patterns("build", ".dart_tool"))
            open(os.path.join(d, "pubspec.yaml"), "w").write(pubspec("sizeapp", with_bindings))
            if main_src is not None:
                open(os.path.join(d, "lib", "main.dart"), "w").write(main_src)
            shutil.rmtree(os.path.join(d, "test"), ignore_errors=True)
            if entries or packages:
                generate(d, a.platform, entries, packages)
            print(f"building {name} ...", file=sys.stderr)
            results[name] = build_aab(d) if a.aab else build(d)

        variant("baseline", False, BASELINE_MAIN)
        variant("imported-unused", True, UNUSED_MAIN, entries=SLICE_ENTRIES)
        variant("one-api-slice", True, ONE_API_MAIN, entries=SLICE_ENTRIES)
        variant("one-api-fullsdk", True, ONE_API_MAIN, packages=all_packages(a.platform))
        if a.aab:
            print(json.dumps(results, indent=2, sort_keys=True))
            return
        ex = os.path.join(ROOT, "examples", "flutter", "android_slice")
        generate(ex, a.platform, entries=SLICE_ENTRIES)
        print("building slice-example ...", file=sys.stderr)
        results["slice-example"] = build(ex)
    finally:
        if not a.keep:
            shutil.rmtree(work, ignore_errors=True)
    print(json.dumps(results, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
