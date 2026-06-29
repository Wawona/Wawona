#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GRADLE_APP = ROOT / "android/app/build.gradle.kts"
GRADLE_DEPS = ROOT / "dependencies/gradle-deps.nix"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def sdk_config_path() -> Path:
    result = subprocess.run(
        ["nix", "eval", ".#wwnSdkConfigPath", "--raw"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    path = Path(result.stdout.strip())
    if not path.is_file():
        raise FileNotFoundError(f"wwnSdkConfigPath does not exist: {path}")
    return path


def nix_string(src: str, key: str, config_path: Path) -> str:
    m = re.search(rf"{re.escape(key)}\s*=\s*\"([^\"]+)\";", src)
    if not m:
        raise ValueError(f"Missing string key `{key}` in {config_path}")
    return m.group(1)


def nix_int(src: str, key: str, config_path: Path) -> int:
    m = re.search(rf"{re.escape(key)}\s*=\s*([0-9]+);", src)
    if not m:
        raise ValueError(f"Missing int key `{key}` in {config_path}")
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
    config_path = sdk_config_path()
    sdk = read(config_path)
    gradle = read(GRADLE_APP)
    gradle_deps = read(GRADLE_DEPS)

    expected = {
        "compileSdk": nix_int(sdk, "compileSdk", config_path),
        "targetSdk": nix_int(sdk, "targetSdk", config_path),
        "buildToolsVersion": nix_string(sdk, "buildToolsVersion", config_path),
        "ndkVersion": nix_string(sdk, "ndkVersion", config_path),
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

    if "androidConfig.buildToolsVersion" not in gradle_deps:
        errors.append("gradle-deps.nix must reference androidConfig.buildToolsVersion")
    if "androidConfig.compileSdk" not in gradle_deps:
        errors.append("gradle-deps.nix must reference androidConfig.compileSdk")
    if "androidConfig.ndkVersion" not in gradle_deps:
        errors.append("gradle-deps.nix must reference androidConfig.ndkVersion")
    if "androidConfigNix" not in gradle_deps:
        errors.append("gradle-deps.nix must import androidConfigNix from wwn-toolchain")

    if errors:
        print("Android config consistency check FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("Android config consistency check OK:")
    print(json.dumps({"sdkConfig": str(config_path), "expected": expected, "actual": actual}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
