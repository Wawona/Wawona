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
        # Prefer appPath + noReset so XCTest activates a live Wawona instead of
        # cold-launch hanging on nix-store bundles. Set WAWONA_MAC2_MANAGE_APP=0
        # only for desktop-wide AX probes (Finder-rooted page_source).
        manage_app = os.environ.get("WAWONA_MAC2_MANAGE_APP", "1") == "1"
        bundle = os.environ.get("WAWONA_BUNDLE_ID", "com.aspauldingcode.Wawona")
        app = os.environ.get("WAWONA_APP_PATH", "").strip()
        if manage_app:
            opts.bundle_id = bundle
            if app and os.path.isdir(app):
                # Mac2 capability name is appPath (not XCUITest "app").
                opts.set_capability("appium:appPath", app)
        opts.set_capability("appium:showServerLogs", True)
        # Contended hosts often need >120s for WebDriverAgentMac xcodebuild.
        opts.set_capability(
            "appium:serverStartupTimeout",
            int(os.environ.get("WAWONA_MAC2_SERVER_STARTUP_MS", "300000")),
        )
        # Prefer a pre-warmed WDA (scripts/appium/ensure-wda-mac.sh). Avoids
        # Xcode 26 xcodebuild relaunch missing TestingInterop / _Testing_Foundation.
        wda_url = os.environ.get("WAWONA_MAC2_WDA_URL", "").strip()
        if not wda_url:
            host = os.environ.get("WAWONA_MAC2_WDA_HOST", "127.0.0.1").strip()
            port = os.environ.get("WAWONA_MAC2_WDA_PORT", "10100").strip()
            try:
                import urllib.request

                with urllib.request.urlopen(
                    f"http://{host}:{port}/status", timeout=1.5
                ) as resp:
                    if resp.status == 200:
                        wda_url = f"http://{host}:{port}"
            except Exception:
                wda_url = ""
        if wda_url:
            opts.set_capability("appium:webDriverAgentMacUrl", wda_url)
        bootstrap = os.environ.get("WAWONA_MAC2_BOOTSTRAP_ROOT", "").strip()
        if bootstrap and os.path.isdir(bootstrap):
            opts.set_capability("appium:bootstrapRoot", bootstrap)
        opts.set_capability(
            "appium:noReset",
            os.environ.get("WAWONA_APPIUM_NO_RESET", "1") == "1",
        )
        opts.set_capability(
            "appium:skipAppKill",
            os.environ.get("WAWONA_MAC2_SKIP_APP_KILL", "1") == "1",
        )
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
    """Capabilities for the Appium Linux AT-SPI2 driver."""
    app = os.environ.get("WAWONA_APP_PATH", "Wawona")
    return {
        "platformName": "Linux",
        "appium:automationName": os.environ.get(
            "WAWONA_LINUX_AUTOMATION", "atspi2"
        ),
        "appium:appName": os.environ.get("WAWONA_LINUX_APP_NAME", app),
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
