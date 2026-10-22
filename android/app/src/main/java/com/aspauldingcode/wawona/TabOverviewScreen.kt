package com.aspauldingcode.wawona

import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Safari-style Tab Overview: search + preview cards for running sessions.
 * Focus opens the compositor surface. Close stops the machine.
 */
@Composable
fun TabOverviewScreen(
    profiles: List<MachineProfile>,
    activeMachineId: String?,
    machineStatusFor: (String) -> MachineStatus,
    onFocus: (MachineProfile) -> Unit,
    onClose: (MachineProfile) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var query by rememberSaveable { mutableStateOf("") }
    val running = remember(profiles, activeMachineId) {
        profiles.filter {
            val s = machineStatusFor(it.id)
            s == MachineStatus.CONNECTED ||
                s == MachineStatus.CONNECTING ||
                it.id == activeMachineId
        }
    }
    val filtered = remember(running, query) {
        val q = query.trim()
        if (q.isEmpty()) {
            running
        } else {
            val lower = q.lowercase()
            running.filter { it.name.lowercase().contains(lower) }
        }
    }
    val tabCount = if (filtered.size == 1) "1 Tab" else "${filtered.size} Tabs"
    val scheme = MaterialTheme.colorScheme

    Column(
        modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Outlined.Dashboard,
                contentDescription = null,
                tint = scheme.primary,
            )
            Text(
                "Tab Overview",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Text(
                tabCount,
                style = MaterialTheme.typography.labelLarge,
                color = scheme.onSurfaceVariant,
            )
        }
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp, bottom = 12.dp)
                .semantics { contentDescription = "Search Tabs" },
            singleLine = true,
            placeholder = { Text("Search Tabs") },
            leadingIcon = {
                Icon(Icons.Filled.Search, contentDescription = null)
            },
        )
        when {
            running.isEmpty() -> {
                Box(
                    Modifier
                        .fillMaxSize()
                        .padding(top = 32.dp),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Outlined.Dashboard,
                            contentDescription = null,
                            modifier = Modifier.size(40.dp),
                            tint = scheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(
                            "No Active Tabs",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            "Start a machine, then open Tab Overview to switch sessions.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = scheme.onSurfaceVariant,
                            modifier = Modifier
                                .padding(horizontal = 24.dp)
                                .padding(top = 4.dp),
                        )
                    }
                }
            }
            filtered.isEmpty() -> {
                Text(
                    "No Matching Tabs",
                    style = MaterialTheme.typography.bodyLarge,
                    color = scheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 24.dp),
                )
            }
            else -> {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 200.dp),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(filtered, key = { it.id }) { profile ->
                        TabOverviewCard(
                            profile = profile,
                            status = machineStatusFor(profile.id),
                            isActive = profile.id == activeMachineId,
                            onFocus = { onFocus(profile) },
                            onClose = { onClose(profile) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TabOverviewCard(
    profile: MachineProfile,
    status: MachineStatus,
    isActive: Boolean,
    onFocus: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val thumbnail = remember(profile.id) {
        MachineThumbnailStore.load(context, profile.id)
    }
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(16.dp)
    val borderColor = if (isActive) scheme.primary else scheme.outlineVariant
    val statusLabel = buildString {
        append(status.displayTitle)
        if (isActive) append(" · Active")
    }
    var swipeOffset by remember(profile.id) { mutableFloatStateOf(0f) }
    val clientRatio = thumbnail?.let { bmp ->
        if (bmp.height > 0) bmp.width.toFloat() / bmp.height.toFloat() else null
    }

    Column(
        modifier
            .fillMaxWidth()
            .offset { IntOffset(swipeOffset.roundToInt(), 0) }
            .pointerInput(profile.id) {
                val threshold = -72.dp.toPx()
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (swipeOffset < threshold) {
                            onClose()
                        } else {
                            swipeOffset = 0f
                        }
                    },
                    onHorizontalDrag = { _, dragAmount ->
                        val next = swipeOffset + dragAmount
                        if (next < 0f) swipeOffset = next
                    },
                )
            }
            .clip(shape)
            .border(
                width = if (isActive) 2.dp else 1.dp,
                color = borderColor,
                shape = shape,
            )
            .background(scheme.surfaceContainerLow)
            .clickable(onClick = onFocus)
            .semantics {
                contentDescription = "${profile.name}, $statusLabel. Double tap to focus"
            }
            .padding(6.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 6.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Filled.Computer,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = if (isActive) scheme.primary else scheme.onSurfaceVariant,
            )
            Text(
                profile.name,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = if (isActive) FontWeight.Bold else FontWeight.Medium,
                maxLines = 1,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 6.dp),
            )
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(scheme.scrim.copy(alpha = 0.45f)),
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Close ${profile.name}",
                    tint = scheme.onPrimary,
                    modifier = Modifier.size(14.dp),
                )
            }
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (clientRatio != null) {
                        Modifier.aspectRatio(clientRatio)
                    } else {
                        Modifier
                    }
                )
                .clip(RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (thumbnail != null) {
                Image(
                    bitmap = thumbnail.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Filled.Computer,
                        contentDescription = null,
                        modifier = Modifier.size(28.dp),
                        tint = scheme.onSurfaceVariant.copy(alpha = 0.5f),
                    )
                    Text(
                        statusLabel,
                        style = MaterialTheme.typography.labelSmall,
                        color = scheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
            }
        }
    }
}
