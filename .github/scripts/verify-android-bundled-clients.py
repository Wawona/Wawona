#!/usr/bin/env python3
"""Verify Android bundled Wayland client packaging parity."""

import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
# Bundled-client packaging was split out of android.nix into
# android-bundled-clients.nix to keep android.nix under its maintainability
# budget; scan both as one logical source.
ANDROID_NIX_FILES = (
    ROOT / "dependencies/wawona/android.nix",
    ROOT / "dependencies/wawona/android-bundled-clients.nix",
)
JNI_STUBS = ROOT / "android/app/src/main/cpp/wawona_client_stubs.c"
ANDROID_JNI = ROOT / "src/platform/android/android_jni.c"
JNI_LIBS = ROOT / "android/app/src/main/jniLibs/arm64-v8a"
REQUIRED_APK_LIBS = (
    "lib/arm64-v8a/libweston_simple_shm.so",
    "lib/arm64-v8a/libfoot.so",
    "lib/arm64-v8a/libfoot_bin.so",
    "lib/arm64-v8a/libwawona_wl_bin.so",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def verify_android_nix(src: str) -> list[str]:
    errors = []
    if "WARNING: Missing Android foot library" in src:
        errors.append("android.nix must fail (not warn) when libfoot.so is missing")
    if "libweston_simple_shm.so" not in src:
        errors.append("android.nix must build libweston_simple_shm.so")
    if "libfoot.so" not in src:
        errors.append("android.nix must bundle libfoot.so")
    if "libfoot_bin.so" not in src:
        errors.append("android.nix must bundle libfoot_bin.so")
    if "libwawona_wl_bin.so" not in src:
        errors.append("android.nix must bundle libwawona_wl_bin.so for fuzzel Exec")
    if not re.search(r"Missing required Android foot library", src):
        errors.append("android.nix must require libfoot.so copy")
    if not re.search(r"Missing required Android foot binary", src):
        errors.append("android.nix must require libfoot_bin.so copy")
    if "Verified bundled client libraries in APK" not in src:
        errors.append("android.nix must verify bundled client libs in APK")
    return errors


def verify_jni_stubs(src: str) -> list[str]:
    errors = []
    if 'run_client_main("libfoot.so", "foot_main"' not in src:
        errors.append("wawona_client_stubs.c must dlopen libfoot.so for foot_main")
    if 'run_client_main("libweston_simple_shm.so", "weston_simple_shm_main"' not in src:
        errors.append(
            "wawona_client_stubs.c must dlopen libweston_simple_shm.so for weston_simple_shm_main"
        )
    return errors


def verify_android_jni(src: str) -> list[str]:
    errors = []
    for client_id in ("foot", "weston-simple-egl", "kmscube"):
        if f'"{client_id}"' not in src:
            errors.append(f"android_jni.c must reference {client_id}")
    if "libfoot_bin.so" not in src:
        errors.append("android_jni.c must fork/exec libfoot_bin.so for foot")
    if "libwawona_wl_bin.so" not in src:
        errors.append("android_jni.c must PATH-link libwawona_wl_bin.so for weston Exec")
    if "wwn_launch_foot" not in src:
        errors.append("android_jni.c must provide wwn_launch_foot")
    if "kmscube_stub_main" not in src:
        errors.append("android_jni.c must provide kmscube_stub_main")
    if "simple_egl_stub_main" not in src:
        errors.append("android_jni.c must provide simple_egl_stub_main")
    return errors


def verify_jni_libs_tree() -> list[str]:
    errors = []
    for lib in ("libweston_simple_shm.so", "libfoot.so", "libfoot_bin.so"):
        path = JNI_LIBS / lib
        if not path.is_file():
            errors.append(f"missing workspace jniLibs artifact: {path.relative_to(ROOT)}")
    return errors


def verify_apk(path: Path) -> list[str]:
    errors = []
    if not path.is_file():
        errors.append(f"APK not found: {path}")
        return errors
    with zipfile.ZipFile(path) as apk:
        names = set(apk.namelist())
    for lib in REQUIRED_APK_LIBS:
        if lib not in names:
            errors.append(f"APK missing {lib}")
    return errors


def main() -> int:
    errors = []
    errors.extend(
        verify_android_nix("\n".join(read(path) for path in ANDROID_NIX_FILES))
    )
    errors.extend(verify_jni_stubs(read(JNI_STUBS)))
    errors.extend(verify_android_jni(read(ANDROID_JNI)))

    if len(sys.argv) > 1:
        errors.extend(verify_apk(Path(sys.argv[1])))
    elif JNI_LIBS.is_dir():
        errors.extend(verify_jni_libs_tree())

    if errors:
        print("Android bundled client check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Android bundled client check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
