package com.aspauldingcode.wawona

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.CenterFocusStrong
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

sealed class MachinesNavDest {
    data object Machines : MachinesNavDest()
    data object TabOverview : MachinesNavDest()
    data class Tag(val tagId: String) : MachinesNavDest()
}

/**
 * iOS Machine Configuration sidebar: Machines + Tab Overview + Tags.
 */
@Composable
fun MachinesConfigurationSidebar(
    tags: List<MachineTag>,
    selected: MachinesNavDest,
    onSelect: (MachinesNavDest) -> Unit,
    onCreateTag: () -> Unit,
    onEditTag: (MachineTag) -> Unit,
    onDeleteTag: (MachineTag) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxHeight()
            .width(240.dp)
            .verticalScroll(rememberScrollState())
            .padding(vertical = 12.dp),
    ) {
        Text(
            "Machines",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
        NavigationDrawerItem(
            label = { Text("Machines") },
            selected = selected is MachinesNavDest.Machines,
            onClick = { onSelect(MachinesNavDest.Machines) },
            icon = { Icon(Icons.Filled.Computer, contentDescription = null) },
            colors = NavigationDrawerItemDefaults.colors(
                selectedContainerColor = MaterialTheme.colorScheme.secondaryContainer,
            ),
            modifier = Modifier.padding(horizontal = 12.dp),
        )
        NavigationDrawerItem(
            label = { Text("Tab Overview") },
            selected = selected is MachinesNavDest.TabOverview,
            onClick = { onSelect(MachinesNavDest.TabOverview) },
            icon = { Icon(Icons.Filled.Dashboard, contentDescription = null) },
            colors = NavigationDrawerItemDefaults.colors(
                selectedContainerColor = MaterialTheme.colorScheme.secondaryContainer,
            ),
            modifier = Modifier.padding(horizontal = 12.dp),
        )
        HorizontalDivider(Modifier.padding(vertical = 12.dp))
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Tags",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 8.dp),
            )
            TextButton(onClick = onCreateTag) {
                Icon(Icons.Filled.Add, contentDescription = "New tag", modifier = Modifier.size(18.dp))
            }
        }
        if (tags.isEmpty()) {
            Text(
                "No tags yet",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
            )
        } else {
            tags.forEach { tag ->
                NavigationDrawerItem(
                    label = {
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(tag.name, modifier = Modifier.weight(1f))
                            IconButton(
                                onClick = { onEditTag(tag) },
                                modifier = Modifier.size(32.dp),
                            ) {
                                Icon(
                                    Icons.Filled.Edit,
                                    contentDescription = "Edit tag",
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    },
                    selected = (selected as? MachinesNavDest.Tag)?.tagId == tag.id,
                    onClick = { onSelect(MachinesNavDest.Tag(tag.id)) },
                    icon = {
                        Box(
                            Modifier
                                .size(12.dp)
                                .clip(CircleShape)
                                .background(MachineTagPalette.color(tag.colorHex)),
                        )
                    },
                    colors = NavigationDrawerItemDefaults.colors(
                        selectedContainerColor = MaterialTheme.colorScheme.secondaryContainer,
                    ),
                    modifier = Modifier
                        .padding(horizontal = 12.dp)
                        .pointerInput(tag.id) {
                            detectTapGestures(onLongPress = { onEditTag(tag) })
                        },
                )
            }
        }
    }
}

@Composable
fun TabOverviewPlaceholder(
    profiles: List<MachineProfile>,
    activeMachineId: String?,
    machineStatusFor: (String) -> MachineStatus,
    onFocus: (MachineProfile) -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Text(
            "Tab Overview",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            "Running and recent machine sessions. Focus returns to an active session.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp, bottom = 16.dp),
        )
        val running = profiles.filter {
            val s = machineStatusFor(it.id)
            s == MachineStatus.CONNECTED || s == MachineStatus.CONNECTING || it.id == activeMachineId
        }
        if (running.isEmpty()) {
            Text(
                "No active sessions",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 24.dp),
            )
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 260.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(running, key = { it.id }) { profile ->
                    val status = machineStatusFor(profile.id)
                    val isActive = profile.id == activeMachineId
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                        ),
                    ) {
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(Icons.Filled.Computer, contentDescription = null)
                                Text(
                                    profile.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            Text(
                                buildString {
                                    append(status.displayTitle)
                                    if (isActive) append(" · Active")
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            FilledTonalButton(
                                onClick = { onFocus(profile) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Icon(
                                    Icons.Outlined.CenterFocusStrong,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                                Text("Focus", modifier = Modifier.padding(start = 8.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}
