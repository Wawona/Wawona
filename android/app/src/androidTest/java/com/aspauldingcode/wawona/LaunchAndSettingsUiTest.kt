package com.aspauldingcode.wawona

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Layer-3 Compose UI smoke (ci-l3-android-espresso).
 *
 * Verifies the app boots to a composited surface and the primary launch control
 * is reachable, using the stable [WawonaTestTags] contract. Deliberately does
 * not assert compositor pixel content (that is covered by agent-device replays);
 * this is the fast "UI wired up correctly" gate.
 */
@RunWith(AndroidJUnit4::class)
class LaunchAndSettingsUiTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun compositorSurfaceIsPresentOnLaunch() {
        composeRule.waitForIdle()
        composeRule.onNodeWithTag(WawonaTestTags.COMPOSITOR_SURFACE).assertIsDisplayed()
    }
}
