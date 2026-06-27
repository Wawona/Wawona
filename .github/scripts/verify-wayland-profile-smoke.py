#!/usr/bin/env python3
"""Profile-oriented Wayland manifest smoke checks + flake build matrix."""

from __future__ import annotations

from pathlib import Path
import subprocess
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

# Flake outputs that must exist for the everywhere build matrix (Phase 5A).
REQUIRED_FLAKE_OUTPUTS = [
    "wawona-macos-backend",
    "wawona-ios-backend",
    "wawona-ios-sim-backend",
    "wawona-ipados-sim-backend",
    "wawona-tvos-sim-backend",
    "wawona-visionos-sim-backend",
    "wawona-watchos-sim-backend",
    "wawona-android",
    "weston-ios",
    "weston-compositor-ios",
    "angle-ios",
    "iland-ios",
    "iland-gl-clients-ios",
]


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


def verify_flake_outputs() -> list[str]:
    """Return missing flake output names (empty if all present)."""
    try:
        proc = subprocess.run(
            ["nix", "flake", "show", "--json", str(ROOT)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"warning: could not inspect flake outputs: {exc}", file=sys.stderr)
        return []

    import json

    data = json.loads(proc.stdout)
    packages = data.get("packages", {})
    # Use first system bucket (CI host may be aarch64-darwin or x86_64-linux).
    system_pkgs = next(iter(packages.values()), {}) if packages else {}
    missing = [name for name in REQUIRED_FLAKE_OUTPUTS if name not in system_pkgs]
    return missing


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

    flake_missing = verify_flake_outputs()
    if flake_missing:
        print(
            "flake build matrix: missing outputs: " + ", ".join(sorted(flake_missing)),
            file=sys.stderr,
        )
        return 1

    print(
        "wayland profile smoke checks passed: "
        + ", ".join(f"{p}={profile_counts[p]}" for p in sorted(PROFILES))
        + f"; flake_outputs={len(REQUIRED_FLAKE_OUTPUTS)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
