#!/usr/bin/env python3
"""Assert Settings.bundle Keys stay in Wawona namespaces (not Gemini toys).

Also asserts WawonaGlobalSettingsPanelView is tvOS/visionOS-only so macOS/iOS
do not ship a second Global Settings host beside PrefPane / Settings.bundle.
"""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "src" / "resources" / "Settings.bundle"
WATCH_BUNDLE = ROOT / "src" / "resources" / "Settings-Watch.bundle"

FORBIDDEN_PREFIXES = (
    "wawona_sync_",
    "wawona_dark_",
    "wawona_api_",
    "group.com.wawona",
)

# Legacy camelCase or dotted wawona.pref.* / wawona.*
KEY_RE = re.compile(r"^(?:[A-Za-z][A-Za-z0-9]*|wawona(?:\.[A-Za-z0-9_]+)+)$")


def collect_keys(plist_path: Path) -> list[str]:
    with plist_path.open("rb") as fh:
        data = plistlib.load(fh)
    keys: list[str] = []
    for spec in data.get("PreferenceSpecifiers", []):
        key = spec.get("Key")
        if key:
            keys.append(str(key))
        child = spec.get("File")
        if child:
            child_path = plist_path.parent / f"{child}.plist"
            if child_path.is_file():
                keys.extend(collect_keys(child_path))
    return keys


def key_ok(key: str) -> bool:
    if any(key.startswith(p) for p in FORBIDDEN_PREFIXES):
        return False
    return bool(KEY_RE.match(key))


def main() -> int:
    errors: list[str] = []
    for bundle in (BUNDLE, WATCH_BUNDLE):
        root = bundle / "Root.plist"
        if not root.is_file():
            if bundle == BUNDLE:
                errors.append(f"missing {root}")
            continue
        keys = collect_keys(root)
        if bundle == BUNDLE and not keys:
            errors.append(f"no Keys in {bundle}")
        for key in keys:
            if not key_ok(key):
                errors.append(f"{bundle.name}: unknown or forbidden Key {key!r}")

    panel = ROOT / "Sources" / "WawonaUI" / "Settings" / "WawonaGlobalSettingsPanelView.swift"
    text = panel.read_text(encoding="utf-8")
    if "#if !SWIFT_PACKAGE && (os(tvOS) || os(visionOS))" not in text:
        errors.append(
            "WawonaGlobalSettingsPanelView.swift must open with "
            "#if !SWIFT_PACKAGE && (os(tvOS) || os(visionOS))"
        )
    if "wawonaOpenInAppGlobalSettingsPanel" in (
        ROOT / "Sources" / "WawonaUI" / "Settings" / "WawonaSystemSettings.swift"
    ).read_text(encoding="utf-8"):
        errors.append(
            "WawonaSystemSettings.swift must not post in-app Global Settings fallback"
        )

    if errors:
        print("verify-settings-bundle-keys: FAIL", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1
    print(f"verify-settings-bundle-keys: OK ({len(collect_keys(BUNDLE / 'Root.plist'))} iOS keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
