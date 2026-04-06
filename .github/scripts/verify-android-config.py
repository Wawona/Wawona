#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SDK_CONFIG = ROOT / "dependencies/android/sdk-config.nix"
GRADLE_APP = ROOT / "android/app/build.gradle.kts"
GRADLE_DEPS = ROOT / "dependencies/gradle-deps.nix"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def nix_string(src: str, key: str) -> str:
    m = re.search(rf"{re.escape(key)}\s*=\s*\"([^\"]+)\";", src)
    if not m:
        raise ValueError(f"Missing string key `{key}` in {SDK_CONFIG}")
    return m.group(1)


def nix_int(src: str, key: str) -> int:
    m = re.search(rf"{re.escape(key)}\s*=\s*([0-9]+);", src)
    if not m:
        raise ValueError(f"Missing int key `{key}` in {SDK_CONFIG}")
    return int(m.group(1))


def gradle_number(src: str, key: str) -> int:
    m = re.search(rf"{re.escape(key)}\s*=\s*([0-9]+)", src)
    if not m:
        raise ValueError(f"Missing gradle key `{key}` in {GRADLE_APP}")
    return int(m.group(1))


def gradle_string(src: str, key: str) -> str:
    m = re.search(rf"{re.escape(key)}\s*=\s*\"([^\"]+)\"", src)
    if not m:
        raise ValueError(f"Missing gradle key `{key}` in {GRADLE_APP}")
    return m.group(1)


def main() -> int:
    sdk = read(SDK_CONFIG)
    gradle = read(GRADLE_APP)
    gradle_deps = read(GRADLE_DEPS)

    expected = {
        "compileSdk": nix_int(sdk, "compileSdk"),
        "targetSdk": nix_int(sdk, "targetSdk"),
        "buildToolsVersion": nix_string(sdk, "buildToolsVersion"),
        "ndkVersion": nix_string(sdk, "ndkVersion"),
    }

    actual = {
        "compileSdk": gradle_number(gradle, "compileSdk"),
        "targetSdk": gradle_number(gradle, "targetSdk"),
        "buildToolsVersion": gradle_string(gradle, "buildToolsVersion"),
        "ndkVersion": gradle_string(gradle, "ndkVersion"),
    }

    errors = []
    for k in expected:
        if expected[k] != actual[k]:
            errors.append(f"{k} mismatch: sdk-config={expected[k]!r}, gradle={actual[k]!r}")

    # Ensure gradle-deps consumes sdk-config values for build tools + compile sdk.
    if "androidConfig.buildToolsVersion" not in gradle_deps:
        errors.append("gradle-deps.nix must reference androidConfig.buildToolsVersion")
    if "androidConfig.compileSdk" not in gradle_deps:
        errors.append("gradle-deps.nix must reference androidConfig.compileSdk")
    if "androidConfig.ndkVersion" not in gradle_deps:
        errors.append("gradle-deps.nix must reference androidConfig.ndkVersion")

    if errors:
        print("Android config consistency check FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("Android config consistency check OK:")
    print(json.dumps({"expected": expected, "actual": actual}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
