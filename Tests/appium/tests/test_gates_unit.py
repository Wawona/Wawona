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
    assert entry["guest"] == "container"
    assert entry.get("recipe") == "weston-container"


def test_catalog_hyprland_available_container():
    entry = catalog_entry("compositors", "hyprland")
    assert entry["status"] == "available"
    assert entry["guest"] == "container"


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
            assert entry["guest"] in {"container", "colima", "nested"}, name


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
