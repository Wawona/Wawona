#!/usr/bin/env python3
"""Profile-oriented Wayland manifest smoke checks."""

from __future__ import annotations

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

PROFILES = {"store-safe", "store-safe-remote", "desktop-host", "full-dev"}


def load_manifest() -> dict:
    raw = MANIFEST.read_text(encoding="utf-8")
    if tomllib is not None:
        return tomllib.loads(raw)
    if _tomli is not None:
        return _tomli.loads(raw)

    # Minimal text fallback.
    protocol_entries = []
    for chunk in raw.split("[[protocol]]"):
        chunk = chunk.strip()
        if not chunk:
            continue
        entry: dict[str, object] = {}
        for line in chunk.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                entry[key] = value.strip('"')
            elif value.startswith("[") and value.endswith("]"):
                entry[key] = [s.strip().strip('"') for s in value[1:-1].split(",") if s.strip()]
        if "interface" in entry:
            protocol_entries.append(entry)
    return {"protocol": protocol_entries}


def main() -> int:
    data = load_manifest()
    protocols = data.get("protocol", [])

    profile_counts = {p: 0 for p in PROFILES}
    for entry in protocols:
        iface = entry["interface"]
        exposure = entry["exposure"]
        equivalent = entry["equivalent"]
        profiles = set(entry.get("profiles", []))
        unknown_profiles = profiles - PROFILES
        if unknown_profiles:
            print(f"{iface}: unknown profiles {sorted(unknown_profiles)}", file=sys.stderr)
            return 1

        for p in profiles:
            profile_counts[p] += 1

        if exposure == "desktop-only" and not profiles.issubset({"desktop-host", "full-dev"}):
            print(f"{iface}: desktop-only exposure leaks into non-desktop profiles", file=sys.stderr)
            return 1

        if equivalent == "no-equivalent" and ("store-safe" in profiles or "store-safe-remote" in profiles):
            print(f"{iface}: no-equivalent protocol must not be in store-safe profiles", file=sys.stderr)
            return 1

    missing = sorted([p for p, count in profile_counts.items() if count == 0])
    if missing:
        print(f"manifest has no protocol rows for profiles: {missing}", file=sys.stderr)
        return 1

    print(
        "wayland profile smoke checks passed: "
        + ", ".join(f"{p}={profile_counts[p]}" for p in sorted(PROFILES))
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
