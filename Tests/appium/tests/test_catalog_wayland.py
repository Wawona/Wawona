"""Wayland catalog battery (plan 23.A / 23.B).

Clients are real Wayland processes in a Linux container or Colima guest,
forwarded into the host Wawona compositor (waypipe / vsock). Appium then
asserts the host surface AND saves a machine screenshot.

A green test without a non-blank PNG in catalog-gallery/ is a failure.
DRY mode must not claim catalog clients are tested.
"""

from __future__ import annotations

import os
import time
from pathlib import Path

import pytest

from wawona_appium.gates import catalog_entry, feature_state, platform_name
from wawona_appium.screenshot_evidence import (
    publish_gallery,
    require_client_screenshot,
    write_gallery_index,
)
from wawona_appium.wayland_guest import launch_client, wait_for_socket

pytestmark = [pytest.mark.catalog, pytest.mark.wayland]

COMPOSITORS = [
    "weston",
    "niri",
    "swaywm",
    "mangowm",
    "hyprland",
    "cosmic_de",
    "phosh_de",
    "kde_plasma_de",
    "kde_plasma_mobile_de",
    "gnome_de",
]
APPLICATIONS = [
    "weston_terminal",
    "weston_simple_shm",
    "foot",
    "ghostty_terminal",
    "konsole",
    "firefox_wayland",
    "thunar",
    "dolphin",
]


def _require_catalog_platform():
    name = platform_name()
    if name not in {"macos", "linux"}:
        pytest.skip("catalog Wayland guests run on macOS (Colima) or Linux (nested)")
    try:
        if feature_state("catalog_clients") != "available":
            pytest.skip(f"catalog_clients not available on {name}")
    except KeyError:
        pytest.skip(f"catalog_clients unset on {name}")


def _artifact_root(artifacts: Path) -> Path:
    # Prefer suite-wide gallery so CI uploads one folder of proof.
    env = os.environ.get("WAWONA_APPIUM_ARTIFACTS")
    if env:
        return Path(env)
    return artifacts.parent if artifacts.name else artifacts


def _launch_and_assert(client_id: str, kind: str, machines, compositor, artifacts):
    _require_catalog_platform()
    entry = catalog_entry(kind, client_id)
    if entry.get("status") != "available":
        pytest.fail(
            f"{client_id} must be an available Wayland guest in matrix.toml "
            f"(got {entry!r}). Do not skip-stub catalog clients."
        )

    if os.environ.get("WAWONA_APPIUM_DRY") == "1":
        pytest.fail(
            f"WAWONA_APPIUM_DRY=1 cannot prove {client_id}. "
            "Unset DRY, start Wawona (wayland-0), launch the guest, "
            "and capture a machine screenshot."
        )

    try:
        wait_for_socket(timeout=20)
    except FileNotFoundError as exc:
        pytest.fail(
            f"host compositor not up for {client_id}: {exc}. "
            "Start Wawona before claiming catalog clients are tested."
        )

    # Darwin catalog = Colima always. Linux CI may set nested.
    if platform_name() == "macos":
        os.environ["WAWONA_WAYLAND_GUEST"] = "colima"
    else:
        guest = entry.get("guest") or "nested"
        os.environ.setdefault("WAWONA_WAYLAND_GUEST", str(guest))

    # Host Present only exposes wwn.compositor.surface after Focus / after the
    # Wawona Terminal window closes (Start opens Terminal; close = Focus).
    # Catalog guests attach to the live sock; without that reveal the surface
    # a11y id is missing and screenshots stay blank.
    machines.open_root()
    if not compositor.exists(compositor.SURFACE):
        if machines.exists(machines.START) or machines.exists(machines.START_TAB):
            machines.start(placement="tab")
            time.sleep(2.0)
        elif machines.exists(machines.ADD):
            machines.add_machine(f"catalog-{client_id}", kind="native")
            machines.start(placement="tab")
            time.sleep(2.0)
    if machines.exists(machines.FOCUS):
        machines.tap(machines.FOCUS)
        time.sleep(1.0)
    # macOS: Start presents Wawona Terminal; closing it calls showSessionSurface.
    if not compositor.exists(compositor.SURFACE) and platform_name() == "macos":
        try:
            import subprocess

            script = (
                'tell application "System Events"\n'
                '  tell process "Wawona"\n'
                "    repeat with w in (every window)\n"
                '      if (name of w as text) contains "Terminal" then\n'
                "        try\n"
                "          click button 1 of w\n"
                "        end try\n"
                "      end if\n"
                "    end repeat\n"
                "  end tell\n"
                "end tell\n"
            )
            subprocess.run(
                ["osascript", "-e", script],
                check=False,
                capture_output=True,
                timeout=10,
            )
            time.sleep(1.5)
        except Exception:
            pass

    result = launch_client(client_id)
    (artifacts / f"guest-{client_id}.log").write_text(
        (result.stdout or "") + "\n" + (result.stderr or ""),
        encoding="utf-8",
    )
    if result.returncode != 0:
        pytest.fail(
            f"Wayland guest launch failed for {client_id} "
            f"(rc={result.returncode}): {(result.stderr or result.stdout)[-800:]}"
        )

    # Let the client paint before Focus / screenshot.
    settle = float(os.environ.get("WAWONA_CATALOG_SETTLE_SEC", "4"))
    time.sleep(settle)
    if machines.exists(machines.FOCUS):
        machines.tap(machines.FOCUS)
        time.sleep(1.0)

    deadline = time.time() + 90
    while time.time() < deadline:
        if compositor.exists(compositor.SURFACE):
            break
        time.sleep(1.0)
    assert compositor.exists(compositor.SURFACE), (
        f"compositor surface missing after launching Wayland client {client_id}. "
        "Start a Machines session so Present shows the host compositor."
    )
    compositor.wait_surface()
    compositor.tap_surface()

    shot = artifacts / f"wayland-{client_id}.png"
    # Prefer the compositor surface element (client pixels), not whole desktop.
    try:
        compositor.screenshot_surface(str(shot))
    except Exception:
        machines.screenshot(str(shot))
    require_client_screenshot(shot, client_id)
    gallery_root = _artifact_root(artifacts)
    published = publish_gallery(shot, gallery_root, client_id)
    require_client_screenshot(published, client_id)


@pytest.fixture(scope="module", autouse=True)
def _catalog_gallery_index(artifacts_module_root):
    yield
    clients = COMPOSITORS + APPLICATIONS
    write_gallery_index(artifacts_module_root, clients)


@pytest.fixture(scope="module")
def artifacts_module_root():
    env = os.environ.get("WAWONA_APPIUM_ARTIFACTS")
    if env:
        root = Path(env)
    else:
        root = Path(".agent-device/test-artifacts/appium")
    root.mkdir(parents=True, exist_ok=True)
    return root


@pytest.mark.parametrize("name", COMPOSITORS)
def test_catalog_compositor_wayland(name, machines, compositor, artifacts):
    _launch_and_assert(name, "compositors", machines, compositor, artifacts)


@pytest.mark.parametrize("name", APPLICATIONS)
def test_catalog_application_wayland(name, machines, compositor, artifacts):
    _launch_and_assert(name, "applications", machines, compositor, artifacts)
