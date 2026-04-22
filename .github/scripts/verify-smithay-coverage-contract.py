#!/usr/bin/env python3
"""Cross-check Smithay coverage contract consistency."""

from __future__ import annotations

from pathlib import Path
import re
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
SURVIVORS = ROOT / "docs" / "compliance" / "non-smithay-survivors.md"
WAYLAND_MOD = ROOT / "src" / "core" / "wayland" / "mod.rs"
COMPOSITOR_RS = ROOT / "src" / "core" / "compositor.rs"
LEGACY_DISPLAY_RS = ROOT / "src" / "core" / "wayland" / "wayland" / "display.rs"

EXPECTED_COMPILE = {"all-targets", "desktop-feature-gated", "linux-desktop-only"}


def _extract_backtick_names(text: str) -> set[str]:
    return set(re.findall(r"`([^`]+)`", text))

def _parse_protocol_blocks_text(raw: str) -> list[dict[str, str]]:
    blocks = []
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
            blocks.append(entry)
    return blocks


def main() -> int:
    raw = MANIFEST.read_text(encoding="utf-8")
    if tomllib is not None:
        data = tomllib.loads(raw)
        protocols = data.get("protocol", [])
    elif _tomli is not None:
        data = _tomli.loads(raw)
        protocols = data.get("protocol", [])
    else:
        print(
            "python tomllib/tomli unavailable; using textual protocol parsing fallback",
            file=sys.stderr,
        )
        protocols = _parse_protocol_blocks_text(raw)

    no_equivalent = {
        p["interface"]
        for p in protocols
        if p.get("equivalent") == "no-equivalent"
    }
    smithay_equivalent = {
        p["interface"]
        for p in protocols
        if p.get("equivalent") == "smithay"
    }

    # Basic source module and compile expectation sanity.
    for entry in protocols:
        iface = entry["interface"]
        src = ROOT / entry["source_module"]
        if not src.exists():
            print(f"{iface}: source_module does not exist: {entry['source_module']}", file=sys.stderr)
            return 1
        if entry["compile_expectation"] not in EXPECTED_COMPILE:
            print(f"{iface}: invalid compile_expectation {entry['compile_expectation']}", file=sys.stderr)
            return 1
        if entry["equivalent"] == "no-equivalent" and entry.get("smithay_module") != "none":
            print(f"{iface}: no-equivalent must use smithay_module='none'", file=sys.stderr)
            return 1
        if entry["equivalent"] == "smithay" and entry.get("smithay_module") == "none":
            print(f"{iface}: smithay equivalent cannot use smithay_module='none'", file=sys.stderr)
            return 1
        if entry["equivalent"] == "no-equivalent":
            src_text = src.read_text(encoding="utf-8")
            if "allow_" not in src_text and "protocol_profile" not in src_text:
                print(
                    f"{iface}: no-equivalent protocol must be runtime-gated in {entry['source_module']}",
                    file=sys.stderr,
                )
                return 1

    survivor_text = SURVIVORS.read_text(encoding="utf-8")
    survivor_names = _extract_backtick_names(survivor_text)
    missing_in_survivors = sorted(name for name in no_equivalent if name not in survivor_names)
    if missing_in_survivors:
        print(
            "no-equivalent interfaces missing from non-smithay survivors doc: "
            + ", ".join(missing_in_survivors),
            file=sys.stderr,
        )
        return 1

    wayland_mod_text = WAYLAND_MOD.read_text(encoding="utf-8")
    runtime_names = set(re.findall(r'interface:\s*"([^"]+)"', wayland_mod_text))
    missing_in_runtime = sorted(name for name in smithay_equivalent if name not in runtime_names)
    if missing_in_runtime:
        print(
            "smithay-equivalent interfaces missing from smithay runtime binding set: "
            + ", ".join(missing_in_runtime),
            file=sys.stderr,
        )
        return 1

    compositor_text = COMPOSITOR_RS.read_text(encoding="utf-8")
    required_runtime_calls = [
        "smithay_runtime::register_core_shell",
        "smithay_runtime::register_extensions_wlr",
    ]
    missing_runtime_calls = [c for c in required_runtime_calls if c not in compositor_text]
    if missing_runtime_calls:
        print(
            "missing smithay runtime wiring in compositor register path: "
            + ", ".join(missing_runtime_calls),
            file=sys.stderr,
        )
        return 1

    if "smithay_scaffold" in compositor_text or "smithay_scaffold" in wayland_mod_text:
        print("legacy smithay_scaffold references remain in runtime wiring", file=sys.stderr)
        return 1

    legacy_display_text = LEGACY_DISPLAY_RS.read_text(encoding="utf-8")
    if "create_global::<CompositorState" in legacy_display_text:
        print(
            "legacy display path still creates globals directly; expected centralized smithay_runtime registration",
            file=sys.stderr,
        )
        return 1

    print("smithay coverage contract validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
