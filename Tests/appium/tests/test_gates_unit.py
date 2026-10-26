"""Offline unit tests for matrix.toml and selectors (no Appium server)."""

from __future__ import annotations

import pytest

from wawona_appium.gates import (
    allows_new_window,
    catalog_entry,
    feature_state,
    load_matrix,
    platform_row,
)
from wawona_appium.selectors import required_cross_platform_ids
from wawona_appium.drivers.session import _linux_capabilities


def test_matrix_has_all_platforms():
    m = load_matrix()
    expected = {
        "ios",
        "ipados",
        "tvos",
        "watchos",
        "visionos",
        "macos",
        "android",
        "linux",
    }
    assert set(m["platforms"].keys()) == expected


def test_linux_capabilities_select_installed_driver(monkeypatch):
    monkeypatch.delenv("WAWONA_LINUX_AUTOMATION", raising=False)
    monkeypatch.delenv("WAWONA_LINUX_APP_NAME", raising=False)
    monkeypatch.setenv("WAWONA_APP_PATH", "/tmp/Wawona.AppImage")

    caps = _linux_capabilities()

    assert caps["platformName"] == "Linux"
    assert caps["appium:automationName"] == "atspi2"
    assert caps["appium:appName"] == "/tmp/Wawona.AppImage"
    assert "appium:app" not in caps


@pytest.mark.parametrize(
    "platform,vm,container",
    [
        ("tvos", "forbidden", "forbidden"),
        ("watchos", "forbidden", "forbidden"),
        ("macos", "planned", "available"),
        ("ios", "planned", "planned"),
    ],
)
def test_vm_container_gates(platform, vm, container, monkeypatch):
    monkeypatch.setenv("WAWONA_APPIUM_PLATFORM", platform)
    assert feature_state("vm") == vm
    assert feature_state("container") == container


def test_macos_allows_new_window(monkeypatch):
    monkeypatch.setenv("WAWONA_APPIUM_PLATFORM", "macos")
    assert allows_new_window() is True


def test_ios_phone_no_new_window(monkeypatch):
    monkeypatch.setenv("WAWONA_APPIUM_PLATFORM", "ios")
    assert allows_new_window() is False


def test_catalog_weston_available_with_guest():
    entry = catalog_entry("compositors", "weston")
    assert entry["status"] == "available"
    assert entry["guest"] == "colima"
    assert entry.get("command") == "weston"


def test_catalog_hyprland_available_colima():
    entry = catalog_entry("compositors", "hyprland")
    assert entry["status"] == "available"
    assert entry["guest"] == "colima"
    assert entry.get("command") == "Hyprland"


def test_catalog_foot_colima():
    entry = catalog_entry("applications", "foot")
    assert entry["status"] == "available"
    assert entry["guest"] == "colima"
    assert entry.get("command") == "foot"


def test_every_catalog_row_has_wayland_guest():
    m = load_matrix()
    for kind in ("compositors", "applications"):
        for name, entry in m["catalog"][kind].items():
            assert entry["status"] == "available", name
            # Darwin catalog = Colima. Linux CI may override with nested via env.
            assert entry["guest"] == "colima", name


def test_selectors_nonempty():
    ids = required_cross_platform_ids()
    assert "wwn.machines.add" in ids
    assert "wwn.machines.pin" in ids
    assert "wwn.toolbar.customize" in ids
    assert "wwn.keyboard.dismiss" in ids
    assert len(ids) >= 40


def test_platform_row_linux_has_catalog(monkeypatch):
    monkeypatch.setenv("WAWONA_APPIUM_PLATFORM", "linux")
    row = platform_row()
    assert row.get("catalog_clients") == "available"


def test_platform_row_macos_has_catalog(monkeypatch):
    monkeypatch.setenv("WAWONA_APPIUM_PLATFORM", "macos")
    row = platform_row()
    assert row.get("catalog_clients") == "available"


def test_catalog_ids_match_gallery_lists():
    from tests.test_catalog_wayland import APPLICATIONS, COMPOSITORS

    m = load_matrix()
    assert set(m["catalog"]["compositors"]) == set(COMPOSITORS)
    assert set(m["catalog"]["applications"]) == set(APPLICATIONS)
