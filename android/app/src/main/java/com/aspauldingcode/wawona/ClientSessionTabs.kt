package com.aspauldingcode.wawona

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * In-window client tabs for concurrent Wayland clients (issue #84 / #65).
 * Selection focuses/activates the matching bundled client when possible.
 */
@Composable
fun ClientSessionTabs(
    tabs: List<ClientTab>,
    selectedId: String,
    onSelect: (ClientTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (tabs.isEmpty()) return
    val selectedIndex = tabs.indexOfFirst { it.id == selectedId }.coerceAtLeast(0)
    ScrollableTabRow(
        selectedTabIndex = selectedIndex,
        edgePadding = 8.dp,
        modifier = modifier
            .fillMaxWidth()
            .testTag(WawonaTestTags.CLIENT_TABS),
    ) {
        tabs.forEach { tab ->
            Tab(
                selected = tab.id == selectedId,
                onClick = { onSelect(tab) },
                text = {
                    Text(
                        tab.title,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                },
            )
        }
    }
}

data class ClientTab(
    val id: String,
    val title: String,
)
