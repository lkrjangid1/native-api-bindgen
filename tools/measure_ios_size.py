#!/usr/bin/env python3
"""Release iOS app size benchmark for generated bindings (TRD §34).

Builds minimal Flutter iOS apps (`flutter build ios --release --no-codesign`,
device arm64) and reports sizes measured from the built Runner.app. Nothing
is estimated.

Variants:
  baseline         `flutter create` app, no native-api-bindgen
  one-api-slice    UIDevice.currentDevice.systemName via bindings for the
                   example's classes
  one-api-full     same call, bindings for ALL of Foundation + UIKit
  slice-example    examples/flutter/ios_slice (all demos; Swift adapters)

Usage: tools/measure_ios_size.py [--keep]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ONE_API_MAIN = """
import 'package:flutter/material.dart';
import 'package:objective_c/objective_c.dart';
import 'src/generated/apple.dart' as ios;

void main() {
  final name = ios.UIDevice.currentDevice.systemName.toDartString();
  runApp(MaterialApp(home: Text(name)));
}
"""

BASELINE_MAIN = """
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: Text('baseline')));
"""

SLICE_CLASSES = ["UIKit.UIDevice", "UIKit.UIView", "UIKit.UIViewController", "UIKit.UIColor",
                 "Foundation.NSProcessInfo", "Foundation.NSFileManager"]


def run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout[-4000:] + r.stderr[-4000:])
        raise SystemExit(f"command failed: {' '.join(cmd)}")
    return r.stdout


def pubspec(with_bindings):
    deps = "  objective_c: 9.5.0\n  ffi: ^2.1.3\n" if with_bindings else ""
    return f"""name: sizeapp
publish_to: none
version: 1.0.0+1
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
{deps}
flutter:
  uses-material-design: true
"""


def dir_size(path):
    total = 0
    for r, _, files in os.walk(path):
        for f in files:
            p = os.path.join(r, f)
            if not os.path.islink(p):
                total += os.path.getsize(p)
    return total


def build(project):
    run(["flutter", "pub", "get"], cwd=project)
    run(["flutter", "build", "ios", "--release", "--no-codesign"], cwd=project)
    app = os.path.join(project, "build", "ios", "iphoneos", "Runner.app")
    fw = os.path.join(app, "Frameworks")

    def size(rel):
        p = os.path.join(app, rel)
        return os.path.getsize(p) if os.path.exists(p) else 0

    return {
        "runner_app_bytes": dir_size(app),
        "app_framework_binary_bytes": size("Frameworks/App.framework/App"),
        "flutter_framework_binary_bytes": size("Frameworks/Flutter.framework/Flutter"),
        "objective_c_framework_bytes": dir_size(os.path.join(fw, "objective_c.framework")),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix="nab_ios_size_")
    results = {}
    try:
        template = os.path.join(work, "template")
        run(["flutter", "create", "--platforms=ios", "--project-name", "sizeapp", template])
        # Current Xcode requires iOS 15+ (React Native and the examples use it too).
        for rel in ("ios/Runner.xcodeproj/project.pbxproj", "ios/Flutter/AppFrameworkInfo.plist"):
            path = os.path.join(template, rel)
            if os.path.exists(path):
                text = open(path).read()
                text = text.replace("IPHONEOS_DEPLOYMENT_TARGET = 13.0", "IPHONEOS_DEPLOYMENT_TARGET = 15.0")
                text = text.replace("<string>13.0</string>", "<string>15.0</string>")
                open(path, "w").write(text)

        def variant(name, main_src, classes=None, frameworks=None):
            d = os.path.join(work, name)
            shutil.copytree(template, d, ignore=shutil.ignore_patterns("build", ".dart_tool"))
            open(os.path.join(d, "pubspec.yaml"), "w").write(pubspec(classes is not None or frameworks is not None))
            open(os.path.join(d, "lib", "main.dart"), "w").write(main_src)
            shutil.rmtree(os.path.join(d, "test"), ignore_errors=True)
            if classes is not None or frameworks is not None:
                args = ["dart", "run", "native_api_bindgen", "--quiet", "--project", d,
                        "generate", "ios", "--output", "lib/src/generated"]
                for f in frameworks or ["Foundation", "UIKit"]:
                    args += ["--framework", f] if classes is None else []
                for c in classes or []:
                    args += ["--class", c]
                run(args, cwd=ROOT)
            print(f"building {name} ...", file=sys.stderr)
            results[name] = build(d)

        variant("baseline", BASELINE_MAIN)
        variant("one-api-slice", ONE_API_MAIN, classes=SLICE_CLASSES)
        variant("one-api-full", ONE_API_MAIN, frameworks=["Foundation", "UIKit"])
        ex = os.path.join(ROOT, "examples", "flutter", "ios_slice")
        print("building slice-example ...", file=sys.stderr)
        results["slice-example"] = build(ex)
    finally:
        if not a.keep:
            shutil.rmtree(work, ignore_errors=True)
    print(json.dumps(results, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
