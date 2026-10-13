"""Build Appium WebDriver sessions from WAWONA_APPIUM_* environment variables."""

from __future__ import annotations

import os
from typing import Any

from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.options.ios import XCUITestOptions
from appium.options.mac import Mac2Options
from selenium.webdriver.remote.webdriver import WebDriver


def _server_url() -> str:
    return os.environ.get("WAWONA_APPIUM_SERVER", "http://127.0.0.1:4723")


def _platform() -> str:
    return os.environ.get("WAWONA_APPIUM_PLATFORM", "ios").strip().lower()


def _apple_options() -> XCUITestOptions | Mac2Options:
    platform = _platform()
    if platform == "macos":
        opts = Mac2Options()
        opts.platform_name = "mac"
        opts.automation_name = "Mac2"
        bundle = os.environ.get("WAWONA_BUNDLE_ID", "com.aspauldingcode.Wawona")
        opts.bundle_id = bundle
        app = os.environ.get("WAWONA_APP_PATH")
        if app:
            opts.app = app
        opts.set_capability("appium:showServerLogs", True)
        return opts

    opts = XCUITestOptions()
    opts.platform_name = "iOS"
    opts.automation_name = "XCUITest"
    opts.device_name = os.environ.get(
        "WAWONA_DEVICE_NAME",
        {
            "ios": "iPhone 17 Pro",
            "ipados": "iPad Pro 13-inch (M4)",
            "tvos": "Apple TV 4K (3rd generation)",
            "visionos": "Apple Vision Pro",
            "watchos": "iPhone 17 Pro",  # phone side of watch pair
        }.get(platform, "iPhone 17 Pro"),
    )
    if os.environ.get("WAWONA_PLATFORM_VERSION"):
        opts.platform_version = os.environ["WAWONA_PLATFORM_VERSION"]
    app = os.environ.get("WAWONA_APP_PATH")
    if app:
        opts.app = app
    opts.bundle_id = os.environ.get("WAWONA_BUNDLE_ID", "com.aspauldingcode.Wawona")
    opts.no_reset = os.environ.get("WAWONA_APPIUM_NO_RESET", "1") == "1"
    opts.new_command_timeout = int(os.environ.get("WAWONA_APPIUM_CMD_TIMEOUT", "120"))
    # Multi-Touch for Wayland client taps (product default may be Touchpad).
    opts.set_capability("appium:settings[snapshotMaxDepth]", 60)
    return opts


def _android_options() -> UiAutomator2Options:
    opts = UiAutomator2Options()
    opts.platform_name = "Android"
    opts.automation_name = "UiAutomator2"
    opts.app = os.environ.get("WAWONA_APP_PATH", "")
    opts.app_package = os.environ.get(
        "WAWONA_ANDROID_PACKAGE", "com.aspauldingcode.wawona"
    )
    opts.app_activity = os.environ.get(
        "WAWONA_ANDROID_ACTIVITY", ".MainActivity"
    )
    opts.no_reset = os.environ.get("WAWONA_APPIUM_NO_RESET", "1") == "1"
    opts.new_command_timeout = int(os.environ.get("WAWONA_APPIUM_CMD_TIMEOUT", "120"))
    opts.set_capability("appium:autoGrantPermissions", True)
    return opts


def _linux_capabilities() -> dict[str, Any]:
    """Capabilities for appium-linux-driver / AT-SPI2.

    Falls back to a generic Appium session; the runner must install
    appium-linux-driver and set DISPLAY.
    """
    app = os.environ.get("WAWONA_APP_PATH", "Wawona")
    return {
        "platformName": "Linux",
        "appium:automationName": os.environ.get(
            "WAWONA_LINUX_AUTOMATION", "Linux"
        ),
        "appium:app": app,
        "appium:appName": os.environ.get("WAWONA_LINUX_APP_NAME", "Wawona"),
        "appium:newCommandTimeout": int(
            os.environ.get("WAWONA_APPIUM_CMD_TIMEOUT", "120")
        ),
    }


def create_driver() -> WebDriver:
    platform = _platform()
    url = _server_url()
    if platform == "android":
        return webdriver.Remote(url, options=_android_options())
    if platform == "linux":
        from appium.options.common import AppiumOptions

        opts = AppiumOptions()
        opts.load_capabilities(_linux_capabilities())
        return webdriver.Remote(url, options=opts)
    return webdriver.Remote(url, options=_apple_options())


def quit_driver(driver: WebDriver | None) -> None:
    if driver is None:
        return
    try:
        driver.quit()
    except Exception:
        pass
