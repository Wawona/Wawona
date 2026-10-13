"""Wayland catalog battery (plan 23.A / 23.B).

Clients are real Wayland processes in a Linux container or Colima guest,
forwarded into the host Wawona compositor (waypipe / vsock). Appium then
asserts the host surface. This is not a packaging-card skip list.
"""

from __future__ import annotations

import os
import time

import pytest

from wawona_appium.gates import catalog_entry, feature_state, platform_name
from wawona_appium.wayland_guest import launch_client, wait_for_socket

pytestmark = [pytest.mark.catalog, pytest.mark.wayland]


def _require_catalog_platform():
    name = platform_name()
    if name not in {"macos", "linux"}:
        pytest.skip("catalog Wayland guests run on macOS (container) or Linux (nested)")
    try:
        if feature_state("catalog_clients") != "available":
            pytest.skip(f"catalog_clients not available on {name}")
    except KeyError:
        pytest.skip(f"catalog_clients unset on {name}")


def _launch_and_assert(client_id: str, kind: str, machines, compositor, artifacts):
    _require_catalog_platform()
    entry = catalog_entry(kind, client_id)
    if entry.get("status") != "available":
        pytest.skip(entry.get("reason", f"{client_id} not available"))

    if os.environ.get("WAWONA_APPIUM_DRY") == "1":
        pytest.skip("WAWONA_APPIUM_DRY=1: guest launch skipped")

    try:
        wait_for_socket(timeout=20)
    except FileNotFoundError as exc:
        pytest.skip(f"host compositor not up: {exc}")

    # Prefer the guest backend declared on the catalog row when env unset.
    guest = entry.get("guest")
    if guest and not os.environ.get("WAWONA_WAYLAND_GUEST"):
        os.environ["WAWONA_WAYLAND_GUEST"] = str(guest)

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

    # Host UI: Focus / compositor surface must show the client.
    time.sleep(2.0)
    if machines.exists(machines.FOCUS):
        machines.tap(machines.FOCUS)
    deadline = time.time() + 60
    while time.time() < deadline:
        if compositor.exists(compositor.SURFACE):
            break
        time.sleep(1.0)
    assert compositor.exists(compositor.SURFACE), (
        f"compositor surface missing after launching Wayland client {client_id}"
    )
    compositor.wait_surface()
    compositor.tap_surface()
    machines.screenshot(str(artifacts / f"wayland-{client_id}.png"))


@pytest.mark.parametrize(
    "name",
    [
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
    ],
)
def test_catalog_compositor_wayland(name, machines, compositor, artifacts):
    _launch_and_assert(name, "compositors", machines, compositor, artifacts)


@pytest.mark.parametrize(
    "name",
    [
        "weston_terminal",
        "weston_simple_shm",
        "foot",
        "ghostty_terminal",
        "konsole",
        "firefox_wayland",
        "thunar",
        "dolphin",
    ],
)
def test_catalog_application_wayland(name, machines, compositor, artifacts):
    _launch_and_assert(name, "applications", machines, compositor, artifacts)
