package com.aspauldingcode.wawona

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Layer-3 Compose UI smoke (ci-l3-android-espresso).
 *
 * Industry-standard Android instrumentation. Asserts Machines (or Welcome)
 * testTags after launch. Gate: products runs this via
 * `connectedDebugAndroidTest` / adb; not agent-device CLI.
 */
@RunWith(AndroidJUnit4::class)
class LaunchAndSettingsUiTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun machinesUiIsPresentOnLaunch() {
        composeRule.waitForIdle()
        // Welcome may appear once; dismiss if the Continue tag is present.
        try {
            composeRule.onNodeWithTag(WawonaTestTags.WELCOME_CONTINUE).assertIsDisplayed()
            composeRule.onNodeWithTag(WawonaTestTags.WELCOME_CONTINUE).performClick()
            composeRule.waitForIdle()
        } catch (_: Throwable) {
            // Already past welcome.
        }
        composeRule.onNodeWithTag(WawonaTestTags.MACHINES_ROOT).assertIsDisplayed()
    }
}
