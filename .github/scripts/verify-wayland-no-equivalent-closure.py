#!/usr/bin/env python3
"""Ensure every no-equivalent interface has a closed disposition."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

try:
    import tomllib  # py311+
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None
    try:
        import tomli as _tomli  # type: ignore
    except ModuleNotFoundError:
        _tomli = None

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "docs" / "compliance" / "wayland-protocol-manifest.toml"

TRUE_NO_PATH_MARKERS = (
    "no direct smithay",
    "no active smithay",
    "no smithay",
    "wawona-specific extension",
    "kde survivor protocol",
    "legacy fullscreen shell",
)

ARCH_BLOCKED_MARKER = "still registered through wawona custom create_global path"


def parse_manifest_text(raw: str) -> list[dict[str, str]]:
    protocol_entries: list[dict[str, str]] = []
    for chunk in raw.split("[[protocol]]"):
        chunk = chunk.strip()
        if not chunk:
            continue
        entry: dict[str, str] = {}
        for line in chunk.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                entry[key] = value.strip('"')
        if "interface" in entry:
            protocol_entries.append(entry)
    return protocol_entries


def load_protocols() -> list[dict[str, str]]:
    raw = MANIFEST.read_text(encoding="utf-8")
    if tomllib is not None:
        data = tomllib.loads(raw)
        return data.get("protocol", [])
    if _tomli is not None:
        data = _tomli.loads(raw)
        return data.get("protocol", [])
    return parse_manifest_text(raw)


def classify(note: str) -> str | None:
    lowered = note.lower()
    if ARCH_BLOCKED_MARKER in lowered:
        return "architecture-blocked"
    if any(marker in lowered for marker in TRUE_NO_PATH_MARKERS):
        return "true-no-path"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json-out",
        type=Path,
        default=None,
        help="optional path to write no-equivalent closure inventory",
    )
    parser.add_argument(
        "--expected-count",
        type=int,
        default=55,
        help="expected number of no-equivalent interfaces",
    )
    args = parser.parse_args()

    protocols = load_protocols()
    no_equivalent = [p for p in protocols if p.get("equivalent") == "no-equivalent"]
    if len(no_equivalent) != args.expected_count:
        print(
            f"no-equivalent count mismatch: expected={args.expected_count} actual={len(no_equivalent)}",
            file=sys.stderr,
        )
        return 1

    report = []
    unclassified = []
    for entry in sorted(no_equivalent, key=lambda p: p["interface"]):
        note = entry.get("notes", "").strip()
        disposition = classify(note) if note else None
        if disposition is None:
            unclassified.append(entry["interface"])
        report.append(
            {
                "interface": entry["interface"],
                "source_module": entry.get("source_module"),
                "notes": note,
                "disposition": disposition or "unclassified",
            }
        )

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2, sort_keys=True),
            encoding="utf-8",
        )

    if unclassified:
        print(
            "no-equivalent interfaces missing closed disposition markers: "
            + ", ".join(unclassified),
            file=sys.stderr,
        )
        return 1

    true_no_path = sum(1 for row in report if row["disposition"] == "true-no-path")
    architecture_blocked = sum(1 for row in report if row["disposition"] == "architecture-blocked")
    print(
        "no-equivalent closure validation passed: "
        f"total={len(report)} true_no_path={true_no_path} architecture_blocked={architecture_blocked}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
