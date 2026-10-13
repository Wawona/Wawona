#!/usr/bin/env python3
"""Fail closed unless every catalog client has a real machine screenshot."""

from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "Tests/appium/matrix.toml"
GALLERY = Path(
    os.environ.get(
        "WAWONA_APPIUM_ARTIFACTS",
        str(ROOT / ".agent-device/test-artifacts/appium"),
    )
) / "catalog-gallery"

# Import shared checks from the suite package.
sys.path.insert(0, str(ROOT / "Tests/appium"))
from wawona_appium.screenshot_evidence import (  # noqa: E402
    require_client_screenshot,
    write_gallery_index,
)


def main() -> int:
    with MATRIX.open("rb") as f:
        data = tomllib.load(f)
    clients: list[str] = []
    for kind in ("compositors", "applications"):
        clients.extend(sorted(data["catalog"][kind]))

    missing = []
    bad = []
    for client in clients:
        png = GALLERY / f"{client}.png"
        if not png.is_file():
            missing.append(client)
            continue
        try:
            require_client_screenshot(png, client)
        except AssertionError as exc:
            bad.append(f"{client}: {exc}")

    write_gallery_index(GALLERY.parent, clients)
    if missing or bad:
        print(f"FAIL catalog gallery at {GALLERY}")
        for c in missing:
            print(f"  MISSING {c}.png")
        for line in bad:
            print(f"  BAD {line}")
        print(
            "Catalog OK requires a non-blank machine screenshot per client. "
            "Run Appium catalog tests with Wawona + container/Colima guests; "
            "do not greenwash with DRY skips."
        )
        return 1
    print(f"OK catalog gallery ({len(clients)} screenshots) -> {GALLERY / 'index.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
