package com.aspauldingcode.wawona

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.DisableSelection
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A launcher-style app drawer shown when Wawona runs as a desktop/home
 * replacement. It presents two kinds of entries side by side:
 *
 *  1. **Wayland clients** — the native clients configured on native Machine
 *     Configuration profiles, launched into the running Wawona compositor.
 *  2. **Android apps** — ordinary installed apps, launched via the Android
 *     PackageManager.
 *
 * This is the visible surface that gives the "Wayland desktop for Android"
 * feel: both worlds live in one drawer.
 */
private sealed interface DrawerEntry {
    val key: String
    val label: String

    data class Wayland(
        val profile: MachineProfile,
        val icon: ImageVector,
    ) : DrawerEntry {
        override val key: String get() = "wayland:${profile.id}"
        override val label: String get() = profile.name.ifBlank { "Wayland" }
    }

    data class Android(
        val app: AndroidApp,
    ) : DrawerEntry {
        override val key: String get() = "android:${app.packageName}"
        override val label: String get() = app.label
    }
}

@Composable
fun AppDrawer(
    waylandMachines: List<MachineProfile>,
    onLaunchWaylandMachine: (MachineProfile) -> Unit,
    onLaunchAndroidApp: (AndroidApp) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var query by remember { mutableStateOf("") }

    val androidApps by produceState(initialValue = emptyList<AndroidApp>()) {
        value = withContext(Dispatchers.Default) {
            AndroidAppLauncher.installedApps(context)
        }
    }

    val entries = remember(waylandMachines, androidApps) {
        buildList {
            waylandMachines.forEach { profile ->
                add(
                    DrawerEntry.Wayland(
                        profile = profile,
                        icon = BundledClients.all
                            .firstOrNull { it.id == profile.nativeLauncher }
                            ?.icon
                            ?: Icons.Filled.Apps,
                    )
                )
            }
            androidApps.forEach { add(DrawerEntry.Android(it)) }
        }
    }

    val filtered = remember(entries, query) {
        val q = query.trim()
        if (q.isEmpty()) entries
        else entries.filter { it.label.contains(q, ignoreCase = true) }
    }

    Surface(
        modifier = modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background.copy(alpha = 0.96f),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .padding(horizontal = 16.dp),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    placeholder = { Text("Search apps & clients") },
                    shape = RoundedCornerShape(28.dp),
                    colors = TextFieldDefaults.colors(
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                    ),
                )
                Spacer(Modifier.size(8.dp))
                Surface(
                    onClick = onDismiss,
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.size(48.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Close, contentDescription = "Close app drawer")
                    }
                }
            }

            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 92.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (waylandMachines.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        DrawerSectionLabel("Wayland Clients")
                    }
                }
                items(
                    filtered.filterIsInstance<DrawerEntry.Wayland>(),
                    key = { it.key },
                ) { entry ->
                    DrawerTile(
                        label = entry.label,
                        onClick = { onLaunchWaylandMachine(entry.profile) },
                    ) {
                        Icon(
                            entry.icon,
                            contentDescription = null,
                            modifier = Modifier.size(34.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }

                val androidEntries = filtered.filterIsInstance<DrawerEntry.Android>()
                if (androidEntries.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        DrawerSectionLabel("Android Apps")
                    }
                    items(androidEntries, key = { it.key }) { entry ->
                        DrawerTile(
                            label = entry.label,
                            onClick = { onLaunchAndroidApp(entry.app) },
                        ) {
                            val bitmap = remember(entry.app.packageName) {
                                entry.app.icon?.toBitmap(width = 96, height = 96)
                            }
                            if (bitmap != null) {
                                androidx.compose.foundation.Image(
                                    bitmap = bitmap.asImageBitmap(),
                                    contentDescription = null,
                                    modifier = Modifier.size(48.dp),
                                )
                            } else {
                                Icon(
                                    Icons.Filled.Apps,
                                    contentDescription = null,
                                    modifier = Modifier.size(34.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }

                if (filtered.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .padding(top = 48.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Icon(
                                Icons.Filled.Search,
                                contentDescription = null,
                                modifier = Modifier.size(40.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "No matching apps or clients",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DrawerSectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(top = 4.dp, bottom = 2.dp),
    )
}

@Composable
private fun DrawerTile(
    label: String,
    onClick: () -> Unit,
    icon: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
            contentAlignment = Alignment.Center,
        ) {
            icon()
        }
        DisableSelection {
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
