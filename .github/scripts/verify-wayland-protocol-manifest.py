#!/usr/bin/env python3
"""Sanity-check the compliance protocol manifest."""

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

REQUIRED_PROFILES = {
    "store-safe",
    "store-safe-remote",
    "desktop-host",
    "full-dev",
}

REQUIRED_INTERFACES = {
    "wl_compositor",
    "wl_subcompositor",
    "wl_shm",
    "wl_output",
    "wl_seat",
    "wl_data_device_manager",
    "wl_fixes",
    "xdg_wm_base",
    "zxdg_toplevel_decoration_v1",
    "xdg_activation_v1",
    "zxdg_exporter_v2",
    "zxdg_importer_v2",
    "xdg_system_bell_v1",
    "xdg_toplevel_icon_v1",
    "xdg_toplevel_tag_manager_v1",
    "zwlr_screencopy_manager_v1",
    "zwlr_export_dmabuf_manager_v1",
    "zwlr_virtual_pointer_manager_v1",
    "zwp_virtual_keyboard_manager_v1",
    "zwlr_layer_shell_v1",
    "ext_foreign_toplevel_list_v1",
    "zwp_pointer_constraints_v1",
    "zwp_pointer_gestures_v1",
    "zwp_relative_pointer_manager_v1",
    "wp_cursor_shape_manager_v1",
    "zwp_text_input_manager_v3",
    "zwp_input_method_manager_v2",
    "zwp_primary_selection_device_manager_v1",
    "ext_data_control_manager_v1",
    "zwlr_data_control_manager_v1",
    "zwp_linux_dmabuf_v1",
    "wp_presentation",
    "wp_commit_timing_manager_v1",
    "wp_fifo_manager_v1",
    "wp_fractional_scale_manager_v1",
    "wp_viewporter",
    "wp_single_pixel_buffer_manager_v1",
    "wp_alpha_modifier_v1",
    "wp_content_type_manager_v1",
    "ext_background_effect_manager_v1",
    "zwp_idle_inhibit_manager_v1",
    "zwp_keyboard_shortcuts_inhibit_manager_v1",
    "ext_idle_notifier_v1",
    "wp_security_context_manager_v1",
    "ext_session_lock_manager_v1",
    "ext_output_image_capture_source_manager_v1",
    "ext_image_copy_capture_manager_v1",
    "wp_drm_lease_device_v1",
    "wp_linux_drm_syncobj_manager_v1",
    "xwayland_shell_v1",
    "zwp_xwayland_keyboard_grab_manager_v1",
}

ALLOWED_EXPOSURE = {
    "store-safe-core",
    "store-safe-conditional",
    "desktop-only",
    "internal-only",
}

ALLOWED_COMPILE_EXPECTATION = {
    "all-targets",
    "desktop-feature-gated",
    "linux-desktop-only",
}

ALLOWED_EQUIVALENT = {"smithay", "no-equivalent"}


def main() -> int:
    if not MANIFEST.exists():
        print(f"missing manifest: {MANIFEST}", file=sys.stderr)
        return 1

    raw = MANIFEST.read_text(encoding="utf-8")
    if tomllib is not None:
        data = tomllib.loads(raw)
    elif _tomli is not None:
        data = _tomli.loads(raw)
    else:
        print(
            "python tomllib/tomli unavailable; falling back to textual checks",
            file=sys.stderr,
        )
        missing_profiles = {
            p for p in REQUIRED_PROFILES if f'name = "{p}"' not in raw
        }
        missing_interfaces = {
            i for i in REQUIRED_INTERFACES if f'interface = "{i}"' not in raw
        }
        if missing_profiles:
            print(f"missing required profiles: {sorted(missing_profiles)}", file=sys.stderr)
            return 1
        if missing_interfaces:
            print(
                f"missing required protocol interfaces: {sorted(missing_interfaces)}",
                file=sys.stderr,
            )
            return 1
        print("wayland protocol manifest textual validation passed")
        return 0
    profiles = {entry.get("name") for entry in data.get("profile", [])}
    protocols = data.get("protocol", [])
    interfaces = {entry.get("interface") for entry in protocols}

    missing_profiles = REQUIRED_PROFILES - profiles
    missing_interfaces = REQUIRED_INTERFACES - interfaces
    if missing_profiles:
        print(f"missing required profiles: {sorted(missing_profiles)}", file=sys.stderr)
        return 1
    if missing_interfaces:
        print(
            f"missing required protocol interfaces: {sorted(missing_interfaces)}",
            file=sys.stderr,
        )
        return 1

    for entry in protocols:
        name = entry.get("interface", "<unknown>")
        for key in (
            "smithay_module",
            "exposure",
            "profiles",
            "source_module",
            "compile_expectation",
            "equivalent",
            "notes",
        ):
            if key not in entry:
                print(f"{name}: missing key '{key}'", file=sys.stderr)
                return 1
        if entry["exposure"] not in ALLOWED_EXPOSURE:
            print(f"{name}: invalid exposure '{entry['exposure']}'", file=sys.stderr)
            return 1
        if entry["compile_expectation"] not in ALLOWED_COMPILE_EXPECTATION:
            print(
                f"{name}: invalid compile_expectation '{entry['compile_expectation']}'",
                file=sys.stderr,
            )
            return 1
        if entry["equivalent"] not in ALLOWED_EQUIVALENT:
            print(f"{name}: invalid equivalent '{entry['equivalent']}'", file=sys.stderr)
            return 1
        if entry["equivalent"] == "no-equivalent" and entry["smithay_module"] != "none":
            print(
                f"{name}: no-equivalent protocols must use smithay_module='none'",
                file=sys.stderr,
            )
            return 1

    print("wayland protocol manifest validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
