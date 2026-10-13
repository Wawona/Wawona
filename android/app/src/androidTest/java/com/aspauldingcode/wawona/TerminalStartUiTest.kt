package com.aspauldingcode.wawona

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Layer-3: Start opens Wawona Terminal (not StartupLog). Zero-AI gate for
 * Gate: products / connectedDebugAndroidTest.
 */
@RunWith(AndroidJUnit4::class)
@LargeTest
class TerminalStartUiTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun startShowsWawonaTerminalNotStartupLog() {
        composeRule.waitForIdle()
        try {
            composeRule.onNodeWithTag(WawonaTestTags.WELCOME_CONTINUE).assertIsDisplayed()
            composeRule.onNodeWithTag(WawonaTestTags.WELCOME_CONTINUE).performClick()
            composeRule.waitForIdle()
        } catch (_: Throwable) {
            // Already past welcome.
        }
        composeRule.onNodeWithTag(WawonaTestTags.MACHINES_ROOT).assertIsDisplayed()
        composeRule.onNodeWithTag(WawonaTestTags.MACHINES_START).performClick()
        composeRule.waitUntil(timeoutMillis = 30_000) {
            try {
                composeRule.onNodeWithTag(WawonaTestTags.TERMINAL_ROOT).assertIsDisplayed()
                true
            } catch (_: Throwable) {
                false
            }
        }
        composeRule.onNodeWithTag(WawonaTestTags.TERMINAL_ROOT).assertIsDisplayed()
        composeRule.onNodeWithTag(WawonaTestTags.TERMINAL_DONE).assertIsDisplayed()
        composeRule.onNodeWithText("Wawona Terminal").assertIsDisplayed()
    }
}
