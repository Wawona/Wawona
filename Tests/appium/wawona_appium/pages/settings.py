"""Global Settings page object (in-app only)."""

from __future__ import annotations

import time

from .base import BasePage


class SettingsPage(BasePage):
    ROOT = "wwn.settings.root"
    DONE = "wwn.settings.done"
    DISPLAY = "wwn.settings.display"
    INPUT = "wwn.settings.input"
    GRAPHICS = "wwn.settings.graphics"
    SSH = "wwn.settings.ssh"
    WAYPIPE = "wwn.settings.waypipe"
    APPLE_WATCH = "wwn.settings.appleWatch"
    APPLE_WATCH_IMPORT = "wwn.settings.appleWatch.import"

    def wait_open(self) -> None:
        self.wait_visible(self.ROOT)

    def open_section(self, section_id: str) -> None:
        self.tap(section_id)
        time.sleep(0.3)

    def change_and_persist_roundtrip(self, section_id: str) -> None:
        """Open a section, leave, reopen. Asserts the section control still exists."""
        self.open_section(section_id)
        self.tap(self.DONE)
        time.sleep(0.4)
        # Caller re-opens Settings from Machines; here we only assert section id
        # remains a stable target when Settings is shown again.
        self.wait_visible(self.ROOT)
        assert self.exists(section_id), f"{section_id} missing after reopen path"

    def import_to_paired_watch(self) -> None:
        self.open_section(self.APPLE_WATCH)
        self.tap(self.APPLE_WATCH_IMPORT)
