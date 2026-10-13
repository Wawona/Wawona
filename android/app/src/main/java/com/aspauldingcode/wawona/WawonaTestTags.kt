package com.aspauldingcode.wawona

/**
 * Stable Compose `testTag` identifiers for agent-device / Espresso / UiAutomator.
 *
 * Keep in sync with Apple `WWNA11y` / `WawonaA11y` (`wwn.<surface>.<control>`).
 * Prefer `id="wwn.…"` selectors in smoke scripts. Renaming a tag is a breaking
 * change for automation.
 *
 * Root composables should enable `testTagsAsResourceId = true` so tags appear
 * as Android resource-ids for agent-device / uiautomator.
 */
object WawonaTestTags {
    const val WELCOME_ROOT = "wwn.welcome.root"
    const val WELCOME_CONTINUE = "wwn.welcome.continue"

    const val MACHINES_ROOT = "wwn.machines.root"
    const val MACHINES_SETTINGS = "wwn.machines.settings"
    const val MACHINES_ADD = "wwn.machines.add"
    const val MACHINES_START = "wwn.machines.start"
    const val MACHINES_START_TAB = "wwn.machines.start.tab"
    const val MACHINES_START_WINDOW = "wwn.machines.start.window"
    const val MACHINES_STOP = "wwn.machines.stop"
    const val MACHINES_FOCUS = "wwn.machines.focus"
    const val MACHINES_EDIT = "wwn.machines.edit"
    const val MACHINES_DELETE = "wwn.machines.delete"
    const val MACHINES_SEARCH = "wwn.machines.search"
    const val MACHINES_PIN = "wwn.machines.pin"
    const val MACHINES_SIDEBAR = "wwn.machines.sidebar"
    const val MACHINES_OVERVIEW = "wwn.machines.overview"
    const val MACHINES_OVERVIEW_FOCUS = "wwn.machines.overview.focus"
    const val MACHINES_OVERVIEW_TERMINATE = "wwn.machines.overview.terminate"
    const val MACHINES_OVERVIEW_ADD = "wwn.machines.overview.add"
    const val MACHINES_TAG_CREATE = "wwn.machines.tag.create"
    const val MACHINES_TAG_NAME = "wwn.machines.tag.name"
    const val MACHINES_TAG_COLOR = "wwn.machines.tag.color"
    const val MACHINES_TAG_FILTER = "wwn.machines.tag.filter"
    const val MACHINES_IMPORT_FILE = "wwn.machines.import.file"
    const val MACHINES_EDITOR = "wwn.machines.editor"
    const val MACHINES_EDITOR_SAVE = "wwn.machines.editor.save"
    const val MACHINES_EDITOR_CANCEL = "wwn.machines.editor.cancel"
    const val MACHINES_EDITOR_NAME = "wwn.machines.editor.name"
    const val MACHINES_EDITOR_TYPE = "wwn.machines.editor.type"
    const val MACHINES_EDITOR_TYPE_NATIVE = "wwn.machines.editor.type.native"
    const val MACHINES_EDITOR_TYPE_VM = "wwn.machines.editor.type.virtual_machine"
    const val MACHINES_EDITOR_TYPE_CONTAINER = "wwn.machines.editor.type.container"

    fun machinesCard(machineId: String): String = "wwn.machines.card.$machineId"

    const val SETTINGS_ROOT = "wwn.settings.root"
    const val SETTINGS_DONE = "wwn.settings.done"
    const val SETTINGS_DISPLAY = "wwn.settings.display"
    const val SETTINGS_INPUT = "wwn.settings.input"
    const val SETTINGS_GRAPHICS = "wwn.settings.graphics"
    const val SETTINGS_CONNECTION = "wwn.settings.connection"
    const val SETTINGS_ENVIRONMENT = "wwn.settings.environment"
    const val SETTINGS_LOCAL_SHELL = "wwn.settings.local.shell"
    const val SETTINGS_DESKTOP = "wwn.settings.desktop"
    const val SETTINGS_ADVANCED = "wwn.settings.advanced"
    const val SETTINGS_WAYPIPE = "wwn.settings.waypipe"
    const val SETTINGS_SSH = "wwn.settings.ssh"
    const val SETTINGS_MACHINES = "wwn.settings.machines"
    const val SETTINGS_ABOUT = "wwn.settings.about"
    const val SETTINGS_DEPENDENCIES = "wwn.settings.dependencies"

    /** @deprecated Use [SETTINGS_ROOT]. Kept for older espresso callers. */
    @Deprecated("Use SETTINGS_ROOT", ReplaceWith("SETTINGS_ROOT"))
    const val SETTINGS_DIALOG = "wwn.settings.root"

    /** @deprecated Use [MACHINES_SETTINGS]. */
    @Deprecated("Use MACHINES_SETTINGS", ReplaceWith("MACHINES_SETTINGS"))
    const val SETTINGS_OPEN = "wwn.machines.settings"

    const val COMPOSITOR_SURFACE = "wwn.compositor.surface"
    const val CLIENT_TABS = "wwn.client.tabs"
    const val APP_DRAWER_OPEN = "wwn.appdrawer.open"

    /** Wawona Terminal Start host (replaces StartupLog preview). */
    const val TERMINAL_ROOT = "wwn.terminal.root"
    const val TERMINAL_DONE = "wwn.terminal.done"
    /** @deprecated Prefer [TERMINAL_DONE]; kept for iOS GuestConsole parity docs. */
    const val GUEST_CONSOLE_DONE = "wwn.guestConsole.done"

    const val TOOLBAR_ROOT = "wwn.toolbar.root"
    const val TOOLBAR_CUSTOMIZE = "wwn.toolbar.customize"
    const val KEYBOARD_DISMISS = "wwn.keyboard.dismiss"
}
