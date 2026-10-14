"""Compositor surface + toolbar / keyboard page object."""

from __future__ import annotations

import time

from .base import BasePage


class CompositorPage(BasePage):
    SURFACE = "wwn.compositor.surface"
    TABS = "wwn.client.tabs"
    TOOLBAR = "wwn.toolbar.root"
    TOOLBAR_CUSTOMIZE = "wwn.toolbar.customize"
    KEYBOARD_DISMISS = "wwn.keyboard.dismiss"

    def wait_surface(self) -> None:
        self.wait_visible(self.SURFACE)

    def surface_rect(self) -> dict:
        el = self.wait_visible(self.SURFACE)
        return el.rect

    def tap_surface(self) -> None:
        self.tap(self.SURFACE)

    def screenshot_surface(self, path: str) -> None:
        """Capture the compositor surface element, not the whole desktop."""
        el = self.wait_visible(self.SURFACE)
        rect = getattr(el, "rect", None) or {}
        width = int(rect.get("width") or 0)
        height = int(rect.get("height") or 0)
        # SwiftUI used to expose a 1x1 AX wrapper; reject tiny element shots.
        if width >= 32 and height >= 32:
            try:
                el.screenshot(path)
                from pathlib import Path

                if Path(path).is_file() and Path(path).stat().st_size >= 12000:
                    return
            except Exception:
                pass
        # Fall back to the app/window shot (still Wawona, not full desktop).
        self.screenshot(path)

    def wait_toolbar(self) -> None:
        self.wait_visible(self.TOOLBAR)

    def customize_toolbar(self) -> None:
        self.tap(self.TOOLBAR_CUSTOMIZE)

    def dismiss_keyboard(self) -> None:
        if self.exists(self.KEYBOARD_DISMISS):
            self.tap(self.KEYBOARD_DISMISS)
        else:
            # Soft fallback: hide keyboard via Appium if available
            try:
                self.driver.hide_keyboard()
            except Exception:
                pass

    def assert_resized(self, before: dict, *, min_delta: int = 8) -> None:
        time.sleep(1.0)
        after = self.surface_rect()
        dw = abs(int(after.get("width", 0)) - int(before.get("width", 0)))
        dh = abs(int(after.get("height", 0)) - int(before.get("height", 0)))
        if dw < min_delta and dh < min_delta:
            raise AssertionError(
                f"Surface did not resize: before={before} after={after}"
            )
