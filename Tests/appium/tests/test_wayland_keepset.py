"""Wayland keep-set sessions: Terminal ls, wasm, SSH, waypipe, drivers."""

from __future__ import annotations

import os
import time

import pytest

pytestmark = [pytest.mark.wayland]


def test_terminal_ls_sees_import(machines, terminal, artifacts, require_feature):
    require_feature("native_shell")
    marker = os.environ.get("WAWONA_IMPORT_MARKER", "appium-import-marker.txt")
    machines.start(placement="tab")
    terminal.wait_open()
    terminal.run_command(f"ls | grep {marker} || ls")
    machines.screenshot(str(artifacts / "terminal-ls.png"))


def test_hello_wasi_gui(machines, compositor, artifacts, require_feature):
    require_feature("wasm")
    # Editor path: create / start a Native Shell wasm session when UI allows.
    machines.add_machine("appium-wasm", kind="native")
    # Prefer editor wasm command field when present.
    if machines.exists(machines.EDIT):
        machines.tap(machines.EDIT)
        if machines.exists("wwn.machines.editor.wasm.command"):
            machines.type_into(
                "wwn.machines.editor.wasm.command", "wasm hello-wasi-gui"
            )
            machines.tap(machines.EDITOR_SAVE)
    machines.start(placement="tab")
    time.sleep(2.0)
    if compositor.exists(compositor.SURFACE):
        compositor.wait_surface()
    machines.screenshot(str(artifacts / "hello-wasi-gui.png"))


def test_ssh_session(machines, artifacts, require_feature):
    require_feature("ssh")
    host = os.environ.get("WAWONA_SSH_FIXTURE_HOST")
    if not host:
        pytest.skip("WAWONA_SSH_FIXTURE_HOST unset (start fixture sshd on runner)")
    machines.add_machine("appium-ssh", kind="native")
    machines.start(placement="tab")
    machines.screenshot(str(artifacts / "ssh.png"))


def test_waypipe_tcp(machines, artifacts, require_feature):
    require_feature("waypipe")
    if not os.environ.get("WAWONA_WAYPIPE_TCP_ENDPOINT"):
        pytest.skip("WAWONA_WAYPIPE_TCP_ENDPOINT unset")
    machines.add_machine("appium-waypipe-tcp", kind="native")
    machines.start(placement="tab")
    machines.screenshot(str(artifacts / "waypipe-tcp.png"))


def test_waypipe_ssh(machines, artifacts, require_feature):
    require_feature("waypipe")
    require_feature("ssh")
    if not os.environ.get("WAWONA_WAYPIPE_SSH_HOST"):
        pytest.skip("WAWONA_WAYPIPE_SSH_HOST unset")
    machines.add_machine("appium-waypipe-ssh", kind="native")
    machines.start(placement="tab")
    machines.screenshot(str(artifacts / "waypipe-ssh.png"))


def test_graphics_driver_switch(machines, settings, artifacts, require_feature):
    require_feature("gpu_driver_picker")
    machines.open_settings()
    settings.wait_open()
    if not settings.exists(settings.GRAPHICS):
        pytest.skip("graphics settings section missing")
    settings.open_section(settings.GRAPHICS)
    settings.screenshot(str(artifacts / "graphics-drivers.png"))
    if settings.exists(settings.DONE):
        settings.tap(settings.DONE)
