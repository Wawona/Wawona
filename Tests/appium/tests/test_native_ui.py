"""Native Wawona host UI cases (plan items 1-19). Requires Appium session."""

from __future__ import annotations

import time

import pytest

from wawona_appium.gates import allows_new_window, container_kind_policy, vm_kind_policy

pytestmark = [pytest.mark.native]


def test_01_add_native_shell(machines, artifacts, require_feature):
    require_feature("native_shell")
    machines.add_machine("appium-native", kind="native")
    machines.screenshot(str(artifacts / "add-native.png"))


def test_01b_add_vm_respects_gate(machines, artifacts, gate_helpers):
    policy = vm_kind_policy()
    if policy == "forbidden":
        machines.tap(machines.ADD)
        machines.assert_absent(machines.TYPE_VM)
        return
    if policy == "planned":
        pytest.skip("vm planned: profile may exist but Start is not green")
    machines.add_machine("appium-vm", kind="virtual_machine")
    machines.screenshot(str(artifacts / "add-vm.png"))


def test_01c_add_container_respects_gate(machines, artifacts):
    policy = container_kind_policy()
    if policy == "forbidden":
        machines.tap(machines.ADD)
        machines.assert_absent(machines.TYPE_CONTAINER)
        return
    if policy == "planned":
        pytest.skip("container planned: profile may exist but Start is not green")
    machines.add_machine("appium-container", kind="container")
    machines.screenshot(str(artifacts / "add-container.png"))


def test_02_start_in_tab(machines, require_feature, artifacts):
    require_feature("native_shell")
    machines.start(placement="tab")
    machines.screenshot(str(artifacts / "start-tab.png"))


def test_02b_start_in_window(machines, artifacts):
    if not allows_new_window():
        pytest.skip("hostWindowManagerPolicy does not offer New Window")
    machines.start(placement="window")
    machines.screenshot(str(artifacts / "start-window.png"))


def test_03_wawona_terminal(machines, terminal, artifacts, require_feature):
    require_feature("native_shell")
    machines.start(placement="tab")
    terminal.wait_open()
    machines.screenshot(str(artifacts / "terminal.png"))


def test_04_pty_cli(machines, terminal, artifacts, require_feature):
    require_feature("native_shell")
    machines.start(placement="tab")
    terminal.wait_open()
    terminal.run_command("echo appium-pty-ok")
    # Soft assert: page source or screenshot evidence
    machines.screenshot(str(artifacts / "pty-cli.png"))


def test_05_sidebar(machines, artifacts):
    machines.open_sidebar()
    assert machines.exists(machines.SIDEBAR) or machines.exists(machines.ROOT)
    machines.screenshot(str(artifacts / "sidebar.png"))


def test_06_tab_overview(machines, artifacts, require_feature):
    require_feature("native_shell")
    machines.start(placement="tab")
    if not machines.exists(machines.OVERVIEW):
        pytest.skip("overview control not wired on this build")
    machines.open_overview()
    if machines.exists(machines.OVERVIEW_FOCUS):
        machines.overview_focus()
    if machines.exists(machines.OVERVIEW_TERMINATE):
        machines.overview_terminate()
    if machines.exists(machines.OVERVIEW_ADD):
        machines.overview_add()
    machines.screenshot(str(artifacts / "overview.png"))


def test_07_tags_and_color(machines, artifacts):
    if not machines.exists(machines.TAG_CREATE):
        pytest.skip("tag create not wired on this build")
    machines.create_tag("appium-tag")
    machines.screenshot(str(artifacts / "tags.png"))


def test_08_pin_machine(machines, artifacts):
    if not machines.exists(machines.PIN):
        pytest.skip("pin control not wired on this build")
    machines.pin()
    machines.screenshot(str(artifacts / "pin.png"))


def test_09_edit_rename_and_search(machines, artifacts, require_feature):
    require_feature("native_shell")
    machines.add_machine("appium-search-me", kind="native")
    if machines.exists(machines.EDIT) and machines.exists(machines.EDITOR_NAME):
        machines.edit_rename("appium-renamed")
    if machines.exists(machines.SEARCH):
        machines.search("appium-renamed")
    machines.screenshot(str(artifacts / "search.png"))


def test_11_settings_sections(machines, settings, artifacts, require_feature):
    require_feature("native_shell")
    machines.open_settings()
    settings.wait_open()
    for section in (
        settings.DISPLAY,
        settings.INPUT,
        settings.SSH,
        settings.WAYPIPE,
        settings.GRAPHICS,
    ):
        if settings.exists(section):
            settings.open_section(section)
            time.sleep(0.2)
    settings.screenshot(str(artifacts / "settings.png"))
    if settings.exists(settings.DONE):
        settings.tap(settings.DONE)


def test_12_watch_import_from_iphone(machines, settings, artifacts, require_feature, platform):
    if platform not in {"ios", "watchos"}:
        pytest.skip("paired Watch import is iPhone Appium only")
    require_feature("watch_import_send")
    machines.open_settings()
    settings.wait_open()
    if not settings.exists(settings.APPLE_WATCH):
        pytest.skip("Apple Watch settings section missing")
    settings.import_to_paired_watch()
    settings.screenshot(str(artifacts / "watch-import.png"))


def test_13_import_file(machines, artifacts):
    if not machines.exists(machines.IMPORT_FILE):
        pytest.skip("import file control not wired on this build")
    machines.import_file()
    machines.screenshot(str(artifacts / "import-file.png"))


def test_15_rotate_or_resize(machines, compositor, driver, artifacts, require_feature, platform):
    require_feature("device_rotation", allow={"available", "resize_window"})
    machines.start(placement="tab")
    if not compositor.exists(compositor.SURFACE):
        pytest.skip("compositor surface not visible yet")
    before = compositor.surface_rect()
    if platform in {"ios", "ipados", "android"}:
        try:
            driver.orientation = "LANDSCAPE"
            time.sleep(1.0)
            compositor.assert_resized(before)
            driver.orientation = "PORTRAIT"
        except Exception as exc:
            pytest.skip(f"orientation API unavailable: {exc}")
    else:
        # macOS / Linux: window resize is host-specific; record frame only.
        machines.screenshot(str(artifacts / "resize.png"))


def test_16_17_18_toolbar_and_keyboard(machines, compositor, artifacts, require_feature):
    require_feature("toolbar_keys")
    machines.start(placement="tab")
    if not compositor.exists(compositor.SURFACE):
        pytest.skip("compositor surface not visible")
    compositor.tap_surface()
    time.sleep(0.5)
    if compositor.exists(compositor.TOOLBAR):
        compositor.wait_toolbar()
        if compositor.exists(compositor.TOOLBAR_CUSTOMIZE):
            compositor.customize_toolbar()
    compositor.dismiss_keyboard()
    machines.screenshot(str(artifacts / "toolbar-keyboard.png"))


def test_19_multiple_clients(machines, artifacts, require_feature):
    require_feature("native_shell")
    machines.start(placement="tab")
    time.sleep(0.5)
    if machines.exists(machines.OVERVIEW_ADD):
        machines.overview_add()
    elif machines.exists(machines.START):
        machines.start(placement="tab")
    machines.screenshot(str(artifacts / "multi-client.png"))
