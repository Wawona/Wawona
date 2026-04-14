#!/usr/bin/env python3
"""
Compare cross-platform UI snapshots for parity gates.

Example:
  python3 scripts/ui_parity_diff.py \
    --screenshots-dir artifacts/ui-parity \
    --threshold 0.12
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass

try:
    from PIL import Image  # type: ignore
except Exception as exc:  # pragma: no cover - runtime-only path
    print(
        "ERROR: Pillow is required for ui parity diff. "
        "Install with `python3 -m pip install pillow`.",
        file=sys.stderr,
    )
    print(f"DETAIL: {exc}", file=sys.stderr)
    sys.exit(2)


@dataclass(frozen=True)
class SnapshotPair:
    name: str
    left: str
    right: str


PAIRS: tuple[SnapshotPair, ...] = (
    SnapshotPair("phone-home-light", "ios_phone_home_light.png", "android_phone_home_light.png"),
    SnapshotPair("phone-home-dark", "ios_phone_home_dark.png", "android_phone_home_dark.png"),
    SnapshotPair("phone-settings-light", "ios_phone_settings_light.png", "android_phone_settings_light.png"),
    SnapshotPair("phone-settings-dark", "ios_phone_settings_dark.png", "android_phone_settings_dark.png"),
    SnapshotPair("wear-home-light", "watchos_wear_home_light.png", "wearos_wear_home_light.png"),
    SnapshotPair("wear-home-dark", "watchos_wear_home_dark.png", "wearos_wear_home_dark.png"),
)


def normalized_mae(left_path: str, right_path: str) -> float:
    with Image.open(left_path) as left_img, Image.open(right_path) as right_img:
        left = left_img.convert("RGB")
        right = right_img.convert("RGB")

        if left.size != right.size:
            right = right.resize(left.size)

        left_data = list(left.getdata())
        right_data = list(right.getdata())
        total = 0
        count = 0
        for (lr, lg, lb), (rr, rg, rb) in zip(left_data, right_data):
            total += abs(lr - rr) + abs(lg - rg) + abs(lb - rb)
            count += 3
        return (total / count) / 255.0


def must_exist(path: str) -> None:
    if not os.path.isfile(path):
        print(f"ERROR: missing snapshot: {path}", file=sys.stderr)
        sys.exit(1)


def main() -> int:
    parser = argparse.ArgumentParser(description="UI parity screenshot diff gate")
    parser.add_argument("--screenshots-dir", required=True, help="Directory containing snapshot PNG files")
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.12,
        help="Normalized MAE threshold (0.0-1.0). Lower is stricter.",
    )
    args = parser.parse_args()

    failures = []
    for pair in PAIRS:
        left = os.path.join(args.screenshots_dir, pair.left)
        right = os.path.join(args.screenshots_dir, pair.right)
        must_exist(left)
        must_exist(right)
        score = normalized_mae(left, right)
        print(f"{pair.name}: {score:.4f}")
        if score > args.threshold:
            failures.append((pair.name, score))

    if failures:
        print("\nParity gate FAILED:", file=sys.stderr)
        for name, score in failures:
            print(f"  - {name}: {score:.4f} > threshold {args.threshold:.4f}", file=sys.stderr)
        return 1

    print("\nParity gate PASSED.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
