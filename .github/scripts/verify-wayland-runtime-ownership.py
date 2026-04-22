#!/usr/bin/env python3
"""Verify Wayland runtime ownership against protocol manifest."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import argparse
import json
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
WAYLAND_ROOT = ROOT / "src" / "core" / "wayland"
COMPOSITOR_RS = ROOT / "src" / "core" / "compositor.rs"
WAYLAND_MOD = ROOT / "src" / "core" / "wayland" / "mod.rs"

RUNTIME_CORE_INTERFACES = {"wl_compositor", "wl_subcompositor", "xdg_wm_base"}

TYPE_HINT_OVERRIDES = {
    # Protocol global is manager, while manifest entry tracks child role interface.
    "zxdg_toplevel_decoration_v1": ["ZxdgDecorationManagerV1", "ZxdgToplevelDecorationV1"],
    "xdg_toplevel_icon_v1": ["XdgToplevelIconManagerV1", "XdgToplevelIconV1"],
}

DELEGATE_OWNERSHIP_MARKERS = {
    "wl_shm": "delegate_shm!",
    "wl_output": "delegate_output!",
    "zxdg_output_manager_v1": "delegate_output!",
    "wl_seat": "delegate_seat!",
    "wl_data_device_manager": "delegate_data_device!",
}


@dataclass
class ProtocolEntry:
    interface: str
    equivalent: str
    source_module: str


def load_toml(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8")
    if tomllib is not None:
        return tomllib.loads(raw)
    if _tomli is not None:
        return _tomli.loads(raw)
    # Text fallback for constrained CI/python shells.
    protocol_blocks: list[dict[str, str]] = []
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
            protocol_blocks.append(entry)
    return {"protocol": protocol_blocks}


def interface_to_type_hints(interface: str) -> list[str]:
    if interface in TYPE_HINT_OVERRIDES:
        return TYPE_HINT_OVERRIDES[interface]
    parts = interface.split("_")
    return ["".join(p.capitalize() for p in parts)]


def scoped_files(source_module: str) -> list[Path]:
    src = ROOT / source_module
    if src.is_file():
        if src.name == "mod.rs":
            return sorted(src.parent.glob("*.rs"))
        return [src]
    if src.is_dir():
        return sorted(src.glob("*.rs"))
    return []


def has_smithay_runtime_wiring() -> bool:
    text = COMPOSITOR_RS.read_text(encoding="utf-8")
    return (
        "smithay_runtime::register_core_shell" in text
        and "smithay_runtime::register_extensions_wlr" in text
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail when smithay-equivalent interfaces are still custom runtime",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        default=None,
        help="optional path to write JSON inventory report",
    )
    args = parser.parse_args()

    try:
        manifest = load_toml(MANIFEST)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    entries = [
        ProtocolEntry(
            interface=p["interface"],
            equivalent=p["equivalent"],
            source_module=p["source_module"],
        )
        for p in manifest.get("protocol", [])
    ]

    if not has_smithay_runtime_wiring():
        print("missing smithay_runtime core wiring in compositor.rs", file=sys.stderr)
        return 1

    report = []
    strict_failures: list[str] = []
    unknown_modules: list[str] = []
    wayland_mod_text = WAYLAND_MOD.read_text(encoding="utf-8")

    for entry in entries:
        files = scoped_files(entry.source_module)
        if not files:
            unknown_modules.append(entry.source_module)
            continue

        type_hints = interface_to_type_hints(entry.interface)
        create_matches = []
        dispatch_matches = []
        for file in files:
            text = file.read_text(encoding="utf-8")
            for hint in type_hints:
                if re.search(
                    rf"create_global::<\s*CompositorState\s*,[^>\n]*{re.escape(hint)}",
                    text,
                ):
                    create_matches.append(str(file.relative_to(ROOT)))
                if re.search(
                    rf"impl\s+(GlobalDispatch|Dispatch)<[^>\n]*{re.escape(hint)}",
                    text,
                ):
                    dispatch_matches.append(str(file.relative_to(ROOT)))

        create_matches = sorted(set(create_matches))
        dispatch_matches = sorted(set(dispatch_matches))

        marker = DELEGATE_OWNERSHIP_MARKERS.get(entry.interface)
        delegate_owned = marker is not None and marker in wayland_mod_text

        dual_registration = bool(create_matches or dispatch_matches)

        if entry.interface in RUNTIME_CORE_INTERFACES:
            owner = "smithay_runtime_core"
        elif delegate_owned:
            owner = "smithay_runtime"
        elif entry.equivalent == "no-equivalent":
            owner = "custom_survivor"
        elif create_matches or dispatch_matches:
            owner = "custom_runtime"
        else:
            owner = "unknown"

        report.append(
            {
                "interface": entry.interface,
                "equivalent": entry.equivalent,
                "source_module": entry.source_module,
                "owner": owner,
                "dual_registration": dual_registration,
                "custom_create_global_files": create_matches,
                "custom_dispatch_files": dispatch_matches,
            }
        )

        if (
            args.strict
            and entry.equivalent == "smithay"
            and (
                owner in {"custom_runtime", "unknown"}
                or (owner == "smithay_runtime" and dual_registration)
            )
        ):
            strict_failures.append(entry.interface)

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    if unknown_modules:
        print(
            "unknown source_module paths in manifest: " + ", ".join(sorted(set(unknown_modules))),
            file=sys.stderr,
        )
        return 1

    custom_smithay = [r["interface"] for r in report if r["equivalent"] == "smithay" and r["owner"] == "custom_runtime"]
    unknown_smithay = [r["interface"] for r in report if r["equivalent"] == "smithay" and r["owner"] == "unknown"]
    print(
        f"runtime ownership inventory: total={len(report)} smithay_custom={len(custom_smithay)} smithay_unknown={len(unknown_smithay)} strict={args.strict}"
    )
    if custom_smithay:
        print("smithay-equivalent still custom runtime: " + ", ".join(sorted(custom_smithay)))
    if unknown_smithay:
        print("smithay-equivalent unknown runtime owner: " + ", ".join(sorted(unknown_smithay)))

    if strict_failures:
        print(
            "strict runtime ownership failures (smithay-equivalent not runtime-owned by smithay_runtime bindings): "
            + ", ".join(sorted(strict_failures)),
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
