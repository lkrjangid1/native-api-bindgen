#!/usr/bin/env python3
"""Release-APK size benchmark for React Native bindings (TRD §34).

Variants (arm64-v8a release APKs, Hermes):
  rn-baseline          fresh `@react-native-community/cli init` app
  rn-one-api-slice     example app, slice bindings (24 types), one API used
  rn-one-api-fullsdk   example app, bindings for EVERY android.jar package,
                       the same single API used

Every number is measured from built artifacts. Metro does not tree-shake, so
unused generated TypeScript is included in the bundle; this script measures
that cost instead of assuming it away.

Usage: tools/measure_rn_size.py [--platform 36] [--keep]
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
EXAMPLE = os.path.join(ROOT, "examples", "react-native", "slice")
ONE_API_APP = """import React from 'react';
import {Text} from 'react-native';
import {applicationContext} from './native-api-bindings';

export default function App(): React.JSX.Element {
  return <Text>{applicationContext().getPackageName()}</Text>;
}
"""


def run(cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, env=env)
    if r.returncode != 0:
        sys.stderr.write(r.stdout[-4000:] + r.stderr[-4000:])
        raise SystemExit(f"command failed: {' '.join(cmd)}")
    return r.stdout


def android_env():
    env = dict(os.environ)
    if not env.get("ANDROID_HOME"):
        env["ANDROID_HOME"] = os.path.expanduser("~/Library/Android/sdk")
    return env


def build(app):
    run(["./gradlew", "assembleRelease", "--console=plain", "-q", "-PreactNativeArchitectures=arm64-v8a"],
        cwd=os.path.join(app, "android"), env=android_env())
    apk = os.path.join(app, "android", "app", "build", "outputs", "apk", "release", "app-release.apk")
    z = zipfile.ZipFile(apk)
    sizes = {i.filename: i.file_size for i in z.infolist()}

    def pick(suffix):
        return sum(v for k, v in sizes.items() if k.endswith(suffix))

    return {
        "apk_bytes": os.path.getsize(apk),
        "js_bundle_bytes": pick("index.android.bundle"),
        "libappmodules_so_bytes": pick("libappmodules.so"),
        "dex_bytes": sum(v for k, v in sizes.items() if k.endswith(".dex")),
    }


def copy_example(dst):
    shutil.copytree(EXAMPLE, dst, symlinks=True, ignore=shutil.ignore_patterns(
        "node_modules", "build", ".gradle", ".cxx", "native-api-bindings", ".native_api_bindgen"))
    # Metro does not resolve through a symlinked node_modules; clone it
    # (copy-on-write on APFS via `cp -c`, plain copy elsewhere).
    src = os.path.join(EXAMPLE, "node_modules")
    flags = ["-cR"] if sys.platform == "darwin" else ["-R"]
    run(["cp", *flags, src, os.path.join(dst, "node_modules")])
    open(os.path.join(dst, "App.tsx"), "w").write(ONE_API_APP)


def all_packages(platform):
    jar = os.path.join(android_env()["ANDROID_HOME"], "platforms", f"android-{platform}", "android.jar")
    names = zipfile.ZipFile(jar).namelist()
    return sorted({n.rsplit("/", 1)[0].replace("/", ".") for n in names
                   if n.endswith(".class") and "/" in n and not n.startswith("META-INF")})


def generate(app, platform, packages=None):
    args = ["dart", "run", "native_api_bindgen", "--quiet", "--project", app, "generate", "react-native",
            "--platform", str(platform)]
    if packages:
        args += ["--depth", "0"]
        for p in packages:
            args += ["--package", p]
    run(args, cwd=ROOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", default="36")
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix="nab_rn_size_")
    results = {}
    try:
        base = os.path.join(work, "baseline")
        run(["npx", "--yes", "@react-native-community/cli@latest", "init", "SizeBase", "--directory", base,
             "--skip-git-init", "--pm", "npm", "--install-pods", "false"])
        print("building rn-baseline ...", file=sys.stderr)
        results["rn-baseline"] = build(base)

        slice_app = os.path.join(work, "slice")
        copy_example(slice_app)
        generate(slice_app, a.platform)
        print("building rn-one-api-slice ...", file=sys.stderr)
        results["rn-one-api-slice"] = build(slice_app)

        full_app = os.path.join(work, "full")
        copy_example(full_app)
        generate(full_app, a.platform, packages=all_packages(a.platform))
        print("building rn-one-api-fullsdk ...", file=sys.stderr)
        results["rn-one-api-fullsdk"] = build(full_app)
    finally:
        if not a.keep:
            shutil.rmtree(work, ignore_errors=True)
    print(json.dumps(results, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
