"""Pytest fixtures for the Wawona Appium UI matrix."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from wawona_appium.drivers.session import create_driver, quit_driver
from wawona_appium.gates import (
    allows_new_window,
    container_kind_policy,
    feature_state,
    platform_name,
    skip_if_not_available,
    vm_kind_policy,
)
from wawona_appium.pages import (
    CompositorPage,
    MachinesPage,
    SettingsPage,
    TerminalPage,
)

ARTIFACTS = Path(
    os.environ.get(
        "WAWONA_APPIUM_ARTIFACTS",
        ".agent-device/test-artifacts/appium",
    )
)


def pytest_configure(config: pytest.Config) -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)


@pytest.fixture(scope="session")
def platform() -> str:
    return platform_name()


@pytest.fixture(scope="session")
def driver():
    """One Appium session per worker. Set WAWONA_APPIUM_DRY=1 to skip connect."""
    if os.environ.get("WAWONA_APPIUM_DRY") == "1":
        pytest.skip("WAWONA_APPIUM_DRY=1: no Appium server")
    drv = create_driver()
    yield drv
    quit_driver(drv)


@pytest.fixture
def machines(driver) -> MachinesPage:
    page = MachinesPage(driver)
    page.open_root()
    return page


@pytest.fixture
def settings(driver) -> SettingsPage:
    return SettingsPage(driver)


@pytest.fixture
def terminal(driver) -> TerminalPage:
    return TerminalPage(driver)


@pytest.fixture
def compositor(driver) -> CompositorPage:
    return CompositorPage(driver)


@pytest.fixture
def artifacts(request) -> Path:
    d = ARTIFACTS / platform_name() / request.node.name.replace("/", "_")
    d.mkdir(parents=True, exist_ok=True)
    return d


@pytest.fixture
def require_feature():
    def _req(feature: str, *, allow: set[str] | None = None):
        reason = skip_if_not_available(feature, allow=allow)
        if reason:
            pytest.skip(reason)

    return _req


@pytest.fixture
def gate_helpers():
    return {
        "vm": vm_kind_policy,
        "container": container_kind_policy,
        "allows_new_window": allows_new_window,
        "feature_state": feature_state,
        "platform": platform_name,
    }
