package com.aspauldingcode.wawona

/**
 * Stable Compose `testTag` identifiers for Layer-3 UI tests (ci-l3-android-espresso).
 *
 * These are the automation contract between the app and `androidTest`
 * (Compose UI Test). Renaming a tag is a breaking change for the UI tests, so
 * keep them here as the single source of truth.
 */
object WawonaTestTags {
    /** Settings entry point (open settings dialog). */
    const val SETTINGS_OPEN = "wwn.settings.open"

    /** Settings dialog root container. */
    const val SETTINGS_DIALOG = "wwn.settings.dialog"

    /** The compositor surface view host. */
    const val COMPOSITOR_SURFACE = "wwn.compositor.surface"

    /** Desktop-replacement app drawer open button (shown over the desktop). */
    const val APP_DRAWER_OPEN = "wwn.appdrawer.open"
}
