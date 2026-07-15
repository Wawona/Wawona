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
    const val MACHINES_STOP = "wwn.machines.stop"
    const val MACHINES_FOCUS = "wwn.machines.focus"
    const val MACHINES_EDIT = "wwn.machines.edit"
    const val MACHINES_DELETE = "wwn.machines.delete"
    const val MACHINES_EDITOR = "wwn.machines.editor"

    fun machinesCard(machineId: String): String = "wwn.machines.card.$machineId"

    const val SETTINGS_ROOT = "wwn.settings.root"
    const val SETTINGS_DONE = "wwn.settings.done"
    const val SETTINGS_DISPLAY = "wwn.settings.display"
    const val SETTINGS_INPUT = "wwn.settings.input"
    const val SETTINGS_GRAPHICS = "wwn.settings.graphics"
    const val SETTINGS_CONNECTION = "wwn.settings.connection"
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
}
