#!/usr/bin/env python3
"""Assert Global Settings stay in-app only (no OS Settings hosts).

Fails if Settings.bundle, Settings-Watch.bundle, PrefPane sources, or
System Settings / Settings.app openers remain as the settings entry.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FORBIDDEN_PATHS = [
    ROOT / "src" / "resources" / "Settings.bundle",
    ROOT / "src" / "resources" / "Settings-Watch.bundle",
    ROOT / "Sources" / "WawonaApple" / "Lifecycle" / "WawonaPrefPaneRootView.swift",
    ROOT / "Sources" / "WawonaApple" / "Lifecycle" / "WawonaSystemPreferencePane.swift",
    ROOT / "Sources" / "WawonaApple" / "Lifecycle" / "PrefPaneEnvironmentVariablesView.swift",
    ROOT / "Sources" / "WawonaApple" / "Lifecycle" / "WawonaPrefPaneStubs.swift",
    ROOT / "src" / "platform" / "macos" / "ui" / "Settings" / "PrefPane",
]

# Product entry points must not hand Global Settings to OS Settings.
SCAN_FILES = [
    ROOT / "Sources" / "WawonaUI" / "Settings" / "PlatformGlobalSettings.swift",
    ROOT / "Sources" / "WawonaUI" / "Settings" / "WawonaSystemSettings.swift",
    ROOT / "Sources" / "WawonaApple" / "Settings" / "WWNPreferences.swift",
    ROOT / "Sources" / "WawonaApple" / "Lifecycle" / "WawonaMenuBarController.swift",
    ROOT / "Sources" / "WawonaApple" / "Lifecycle" / "WawonaSystemSettingsBridge.swift",
    ROOT / "Darwin" / "Sources" / "Main.swift",
    ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
]

FORBIDDEN_SNIPPETS = [
    "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane",
    "UIApplication.openSettingsURLString",
    "ACTION_APPLICATION_PREFERENCES",
    "WWN_PREFPANE",
]


def main() -> int:
    errors: list[str] = []

    for path in FORBIDDEN_PATHS:
        if path.exists():
            errors.append(f"retired OS Settings host still present: {path.relative_to(ROOT)}")

    xcodegen = ROOT / "dependencies" / "generators" / "xcodegen.nix"
    xtext = xcodegen.read_text(encoding="utf-8")
    for needle in (
        "Wawona-PrefPane",
        "Settings.bundle",
        "Settings-Watch.bundle",
        "WWN_PREFPANE",
        "Bundle Preference Pane",
    ):
        if needle in xtext:
            errors.append(f"xcodegen.nix still references {needle!r}")

    for path in SCAN_FILES:
        if not path.is_file():
            errors.append(f"missing scan target {path.relative_to(ROOT)}")
            continue
        text = path.read_text(encoding="utf-8")
        for snippet in FORBIDDEN_SNIPPETS:
            if snippet in text:
                errors.append(f"{path.relative_to(ROOT)}: forbidden {snippet!r}")

    # Sidebar must host the full catalog, not the three-row About subset.
    main_window = (
        ROOT / "Sources" / "WawonaUI" / "WawonaMainWindowView.swift"
    ).read_text(encoding="utf-8")
    if "GlobalSettingsCatalog.visibleSections" not in main_window:
        errors.append(
            "WawonaMainWindowView.swift must use GlobalSettingsCatalog.visibleSections "
            "for in-app Global Settings"
        )
    if re.search(
        r"catalogSections:.*appSidebarSections",
        main_window,
        re.DOTALL,
    ):
        errors.append(
            "WawonaMainWindowView catalogSections must not use appSidebarSections"
        )

    watch = (
        ROOT / "Sources" / "WawonaWatch" / "WatchKitGlobalSettings.swift"
    ).read_text(encoding="utf-8")
    if "iPhone Watch app" in watch and "Toggle(" not in watch:
        errors.append(
            "WatchKitGlobalSettings.swift must host an in-app catalog, not a redirect"
        )

    if errors:
        print("verify-settings-bundle-keys: FAIL", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1
    print("verify-settings-bundle-keys: OK (in-app Global Settings only)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
