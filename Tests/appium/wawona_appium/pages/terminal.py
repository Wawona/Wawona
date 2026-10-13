"""Wawona Terminal host page object."""

from __future__ import annotations

import time

from .base import BasePage


class TerminalPage(BasePage):
    ROOT = "wwn.terminal.root"
    DONE = "wwn.terminal.done"

    def wait_open(self) -> None:
        self.wait_visible(self.ROOT)

    def run_command(self, command: str) -> None:
        """Type a command into the focused terminal / soft keyboard path."""
        self.wait_open()
        # Prefer accessibility typing on the terminal root; platforms map this
        # to the first-responder text input or PTY accessory.
        try:
            el = self.find(self.ROOT)
            el.click()
            el.send_keys(command + "\n")
        except Exception:
            # Fallback: active element
            active = self.driver.switch_to.active_element
            active.send_keys(command + "\n")
        time.sleep(0.8)

    def page_source_contains(self, needle: str) -> bool:
        src = self.driver.page_source or ""
        return needle in src

    def dismiss(self) -> None:
        if self.exists(self.DONE):
            self.tap(self.DONE)
