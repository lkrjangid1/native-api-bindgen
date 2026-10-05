#!/usr/bin/env python3
"""Android cold-start time with and without generated bindings (TRD §34).

Builds two release APKs (baseline and one-api-slice, as in
measure_size.py), installs them on ONE device and reports the median
`am start -W` TotalTime over N cold starts. Only emulators are accepted
unless --allow-physical is given (physical devices need explicit consent).

Usage: ANDROID_SERIAL=emulator-5554 tools/measure_startup.py [--runs 10]
"""
import argparse
import importlib.util
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("measure_size", os.path.join(ROOT, "tools", "measure_size.py"))
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)

ADB = os.path.join(os.environ.get("ANDROID_HOME") or os.path.expanduser("~/Library/Android/sdk"),
                   "platform-tools", "adb")
PKG = "com.example.sizeapp"


def adb(*args):
    return subprocess.run([ADB, *args], text=True, capture_output=True, check=True).stdout


def cold_starts(apk, runs):
    adb("install", "-r", apk)
    times = []
    for _ in range(runs + 1):
        adb("shell", "am", "force-stop", PKG)
        out = adb("shell", "am", "start", "-W", "-n", f"{PKG}/.MainActivity")
        total = [l for l in out.splitlines() if l.startswith("TotalTime:")]
        if total:
            times.append(int(total[0].split(":")[1]))
    adb("uninstall", PKG)
    return times[1:]  # first start includes dex/AOT setup


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--platform", default="36")
    ap.add_argument("--allow-physical", action="store_true")
    a = ap.parse_args()
    serial = os.environ.get("ANDROID_SERIAL", "")
    if not serial.startswith("emulator-") and not a.allow_physical:
        raise SystemExit("set ANDROID_SERIAL=emulator-NNNN (physical devices need --allow-physical)")
    work = tempfile.mkdtemp(prefix="nab_startup_")
    results = {}
    try:
        template = os.path.join(work, "template")
        ms.run(["flutter", "create", "--platforms=android", "--project-name", "sizeapp", template])
        for name, bindings, main_src in [("baseline", False, ms.BASELINE_MAIN),
                                         ("one-api-slice", True, ms.ONE_API_MAIN)]:
            d = os.path.join(work, name)
            shutil.copytree(template, d, ignore=shutil.ignore_patterns("build", ".dart_tool"))
            open(os.path.join(d, "pubspec.yaml"), "w").write(ms.pubspec("sizeapp", bindings))
            open(os.path.join(d, "lib", "main.dart"), "w").write(main_src)
            shutil.rmtree(os.path.join(d, "test"), ignore_errors=True)
            if bindings:
                ms.generate(d, a.platform, entries=ms.SLICE_ENTRIES)
            ms.run(["flutter", "pub", "get"], cwd=d)
            ms.run(["flutter", "build", "apk", "--release", "--target-platform", "android-arm64"], cwd=d)
            apk = os.path.join(d, "build", "app", "outputs", "flutter-apk", "app-release.apk")
            print(f"measuring {name} ...", file=sys.stderr)
            t = cold_starts(apk, a.runs)
            results[name] = {"runs": t, "median_ms": statistics.median(t)}
    finally:
        shutil.rmtree(work, ignore_errors=True)
    results["device"] = serial
    print(json.dumps(results, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
