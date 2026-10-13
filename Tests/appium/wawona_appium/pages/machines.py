"""Machines list / editor / overview page object."""

from __future__ import annotations

import time

from .base import BasePage


class MachinesPage(BasePage):
    ROOT = "wwn.machines.root"
    ADD = "wwn.machines.add"
    START = "wwn.machines.start"
    START_TAB = "wwn.machines.start.tab"
    START_WINDOW = "wwn.machines.start.window"
    STOP = "wwn.machines.stop"
    FOCUS = "wwn.machines.focus"
    EDIT = "wwn.machines.edit"
    DELETE = "wwn.machines.delete"
    SEARCH = "wwn.machines.search"
    PIN = "wwn.machines.pin"
    SIDEBAR = "wwn.machines.sidebar"
    OVERVIEW = "wwn.machines.overview"
    OVERVIEW_FOCUS = "wwn.machines.overview.focus"
    OVERVIEW_TERMINATE = "wwn.machines.overview.terminate"
    OVERVIEW_ADD = "wwn.machines.overview.add"
    TAG_CREATE = "wwn.machines.tag.create"
    TAG_NAME = "wwn.machines.tag.name"
    TAG_COLOR = "wwn.machines.tag.color"
    TAG_FILTER = "wwn.machines.tag.filter"
    IMPORT_FILE = "wwn.machines.import.file"
    EDITOR = "wwn.machines.editor"
    EDITOR_SAVE = "wwn.machines.editor.save"
    EDITOR_CANCEL = "wwn.machines.editor.cancel"
    EDITOR_NAME = "wwn.machines.editor.name"
    EDITOR_TYPE = "wwn.machines.editor.type"
    TYPE_NATIVE = "wwn.machines.editor.type.native"
    TYPE_VM = "wwn.machines.editor.type.virtual_machine"
    TYPE_CONTAINER = "wwn.machines.editor.type.container"
    SETTINGS = "wwn.machines.settings"

    def open_root(self) -> None:
        self.dismiss_welcome_if_present()
        self.wait_visible(self.ROOT)

    def add_machine(self, name: str, kind: str = "native") -> None:
        self.tap(self.ADD)
        self.wait_visible(self.EDITOR)
        type_id = {
            "native": self.TYPE_NATIVE,
            "virtual_machine": self.TYPE_VM,
            "container": self.TYPE_CONTAINER,
        }.get(kind, self.TYPE_NATIVE)
        if self.exists(type_id):
            self.tap(type_id)
        elif self.exists(self.EDITOR_TYPE):
            self.tap(self.EDITOR_TYPE)
        if self.exists(self.EDITOR_NAME):
            self.type_into(self.EDITOR_NAME, name)
        self.tap(self.EDITOR_SAVE)
        time.sleep(0.5)

    def start(self, placement: str = "tab") -> None:
        if placement == "window" and self.exists(self.START_WINDOW):
            self.tap(self.START_WINDOW)
        elif placement == "tab" and self.exists(self.START_TAB):
            self.tap(self.START_TAB)
        else:
            self.tap(self.START)

    def search(self, query: str) -> None:
        self.type_into(self.SEARCH, query)

    def pin(self) -> None:
        self.tap(self.PIN)

    def open_sidebar(self) -> None:
        if self.exists(self.SIDEBAR):
            self.tap(self.SIDEBAR)

    def open_overview(self) -> None:
        self.tap(self.OVERVIEW)

    def overview_focus(self) -> None:
        self.tap(self.OVERVIEW_FOCUS)

    def overview_terminate(self) -> None:
        self.tap(self.OVERVIEW_TERMINATE)

    def overview_add(self) -> None:
        self.tap(self.OVERVIEW_ADD)

    def create_tag(self, name: str) -> None:
        self.tap(self.TAG_CREATE)
        if self.exists(self.TAG_NAME):
            self.type_into(self.TAG_NAME, name)
        if self.exists(self.TAG_COLOR):
            self.tap(self.TAG_COLOR)

    def edit_rename(self, new_name: str) -> None:
        self.tap(self.EDIT)
        self.wait_visible(self.EDITOR)
        self.type_into(self.EDITOR_NAME, new_name)
        self.tap(self.EDITOR_SAVE)

    def import_file(self) -> None:
        self.tap(self.IMPORT_FILE)

    def open_settings(self) -> None:
        self.tap(self.SETTINGS)
