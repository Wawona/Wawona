package com.aspauldingcode.wawona

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

/**
 * One Android task for Wawona Terminal when Start is New Window.
 * New Tab stays in [MainActivity]. API 24+ only, same gate as [SessionActivity].
 */
class TerminalActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WawonaGuestTerm.attachWindow(this)
        title = intent.getStringExtra(EXTRA_TITLE) ?: "Wawona Terminal"
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
                    TerminalWindow()
                }
            }
        }
    }

    override fun onDestroy() {
        WawonaGuestTerm.detachWindow(this)
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TITLE = "title"

        fun createIntent(context: Context, title: String): Intent =
            Intent(context, TerminalActivity::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT,
                )
            }
    }
}

@Composable
private fun TerminalWindow() {
    GuestConsoleOverlay(
        term = WawonaGuestTerm.term,
        onDismiss = { WawonaGuestTerm.finishWindow() },
        acceptKeys = WawonaGuestTerm.acceptsKeys,
        modifier = Modifier.fillMaxSize(),
    )
}
