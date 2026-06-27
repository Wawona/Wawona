#!/usr/bin/env python3
"""Profile-oriented Wayland manifest smoke checks + flake build matrix."""

from __future__ import annotations

from pathlib import Path
import argparse
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

# Host-scoped flake outputs for Phase 5A (eval always; --build compiles on matching hosts).
DARWIN_FLAKE_OUTPUTS = [
    "wawona-macos-backend",
    "wawona-ios-backend",
    "wawona-ios-sim-backend",
    "wawona-ipados-sim-backend",
    "wawona-tvos-sim-backend",
    "wawona-visionos-sim-backend",
    "wawona-watchos-sim-backend",
    "weston-ios",
    "weston-compositor-ios",
    "weston-compositor-ios-drm",
    "weston-compositor-ios-drm-sim",
    "weston-ios-gl",
    "weston-ios-gl-sim",
    "angle-ios",
    "angle-ios-sim",
    "iland-ios",
    "iland-ios-sim",
    "iland-gl-clients-ios",
    "iland-gl-clients-ios-device",
    "iland-gl-clients",
]

LINUX_FLAKE_OUTPUTS = [
    "wawona-android",
    "weston-android",
    "weston-compositor-android",
    "angle-android",
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


def current_system() -> str:
    proc = subprocess.run(
        ["nix", "eval", "--raw", "--impure", "--expr", "builtins.currentSystem"],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


def required_outputs_for_system(system: str) -> list[str]:
    if system.startswith("aarch64-darwin") or system.startswith("x86_64-darwin"):
        return DARWIN_FLAKE_OUTPUTS
    return LINUX_FLAKE_OUTPUTS


def verify_flake_outputs(system: str, build: bool) -> list[str]:
    """Return missing or failed flake output names."""
    missing = []
    for name in required_outputs_for_system(system):
        attr = f"{ROOT}#packages.{system}.{name}"
        if build:
            proc = subprocess.run(
                ["nix", "build", attr, "--no-link"],
                capture_output=True,
                text=True,
            )
        else:
            proc = subprocess.run(
                ["nix", "eval", attr, "--apply", "x: x.name or true"],
                capture_output=True,
                text=True,
            )
        if proc.returncode != 0:
            missing.append(name)
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--build",
        action="store_true",
        help="Run nix build --no-link for host-scoped Phase 5A outputs (slower, compile-verified)",
    )
    args = parser.parse_args()

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

    missing_profiles = sorted([p for p, count in profile_counts.items() if count == 0])
    if missing_profiles:
        print(f"manifest has no protocol rows for profiles: {missing_profiles}", file=sys.stderr)
        return 1

    system = current_system()
    required = required_outputs_for_system(system)
    flake_missing = verify_flake_outputs(system, build=args.build)
    if flake_missing:
        mode = "build" if args.build else "eval"
        print(
            f"flake build matrix ({mode}, {system}): missing/failed outputs: "
            + ", ".join(sorted(flake_missing)),
            file=sys.stderr,
        )
        return 1

    mode = "build" if args.build else "eval"
    print(
        "wayland profile smoke checks passed: "
        + ", ".join(f"{p}={profile_counts[p]}" for p in sorted(PROFILES))
        + f"; flake_outputs={len(required)} ({mode}, {system})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
