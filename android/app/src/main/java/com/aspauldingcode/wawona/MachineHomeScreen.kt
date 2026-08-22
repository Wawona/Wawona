package com.aspauldingcode.wawona

import android.content.Context
import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.CenterFocusStrong
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.IconButton
import org.json.JSONObject

private val compactButtonPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)

private fun readBoolOverride(overrides: JSONObject?, key: String, globalDefault: Boolean): Boolean {
    if (overrides == null || !overrides.has(key)) return globalDefault
    return when (val raw = overrides.opt(key)) {
        is JSONObject -> when (raw.optString("type", "")) {
            "boolean" -> raw.optBoolean("value", globalDefault)
            else -> globalDefault
        }
        is Boolean -> raw
        else -> globalDefault
    }
}

private fun writeBoolOverride(overrides: JSONObject, key: String, value: Boolean, globalDefault: Boolean) {
    if (value == globalDefault) {
        overrides.remove(key)
    } else {
        overrides.put(
            key,
            JSONObject().apply {
                put("type", "boolean")
                put("value", value)
            }
        )
    }
}

private fun readStringOverride(overrides: JSONObject?, key: String, globalDefault: String): String {
    if (overrides == null || !overrides.has(key)) return globalDefault
    return when (val raw = overrides.opt(key)) {
        is JSONObject -> when (raw.optString("type", "")) {
            "string" -> raw.optString("value", globalDefault)
            else -> globalDefault
        }
        is String -> raw
        else -> globalDefault
    }
}

private fun writeStringOverride(overrides: JSONObject, key: String, value: String, globalDefault: String) {
    if (value == globalDefault) {
        overrides.remove(key)
    } else {
        overrides.put(
            key,
            JSONObject().apply {
                put("type", "string")
                put("value", value)
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MachineWelcomeScreen(
    profiles: List<MachineProfile>,
    thumbnailRevision: Int,
    activeMachineId: String?,
    machineStatusFor: (String) -> MachineStatus,
    onCreate: (MachineProfile) -> Unit,
    onUpdate: (MachineProfile) -> Unit,
    onDelete: (MachineProfile) -> Unit,
    onConnect: (MachineProfile) -> Unit,
    onFocus: (MachineProfile) -> Unit,
    onStop: (MachineProfile) -> Unit,
    onOpenSettings: () -> Unit
) {
    var editorProfile by remember { mutableStateOf<MachineProfile?>(null) }
    var creating by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var searchExpanded by remember { mutableStateOf(false) }
    val listBottomPadding = 72.dp
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())

    val visibleProfiles = remember(profiles, searchQuery) {
        MachineSearch.fuzzyFilter(profiles, searchQuery, MachineSearch::searchableText)
    }

    Scaffold(
        modifier = Modifier
            .nestedScroll(scrollBehavior.nestedScrollConnection)
            .testTag(WawonaTestTags.MACHINES_ROOT),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    if (searchExpanded) {
                        val searchFocus = remember { FocusRequester() }
                        LaunchedEffect(Unit) { searchFocus.requestFocus() }
                        TextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(searchFocus),
                            placeholder = { Text("Search machines") },
                            singleLine = true,
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                            ),
                        )
                    } else {
                        Text("Machine Configuration")
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background.copy(alpha = 0.82f),
                    scrolledContainerColor = MaterialTheme.colorScheme.background.copy(alpha = 0.96f),
                ),
                navigationIcon = {
                    if (searchExpanded) {
                        IconButton(onClick = {
                            searchExpanded = false
                            searchQuery = ""
                        }) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Close search",
                            )
                        }
                    }
                },
                actions = {
                    if (searchExpanded) {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Filled.Close, contentDescription = "Clear search")
                            }
                        }
                    } else {
                        IconButton(onClick = { searchExpanded = true }) {
                            Icon(Icons.Filled.Search, contentDescription = "Search machines")
                        }
                        IconButton(
                            onClick = onOpenSettings,
                            modifier = Modifier.testTag(WawonaTestTags.MACHINES_SETTINGS),
                        ) {
                            Icon(Icons.Filled.Settings, contentDescription = "Settings")
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            Surface(
                onClick = { creating = true },
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
                shadowElevation = 6.dp,
                modifier = Modifier
                    .padding(end = 16.dp, bottom = 16.dp)
                    .size(44.dp)
                    .testTag(WawonaTestTags.MACHINES_ADD),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Filled.Add,
                        contentDescription = "Add Machine",
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 280.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = 16.dp,
                    top = 12.dp,
                    end = 16.dp,
                    bottom = listBottomPadding,
                ),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                if (visibleProfiles.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 30.dp, bottom = 24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Icon(
                                Icons.Filled.Search,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(12.dp))
                            Text(
                                "No Matching Machines",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "Adjust search or add a new machine profile.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                } else {
                    items(visibleProfiles, key = { it.id }) { profile ->
                        AnimatedVisibility(
                            visible = true,
                            enter = fadeIn() + scaleIn(initialScale = 0.95f, animationSpec = spring()),
                        ) {
                            MachineGridCard(
                                profile = profile,
                                thumbnailRevision = thumbnailRevision,
                                status = machineStatusFor(profile.id),
                                isActive = profile.id == activeMachineId,
                                onEdit = { editorProfile = profile },
                                onDelete = { onDelete(profile) },
                                onConnect = { onConnect(profile) },
                                onFocus = { onFocus(profile) },
                                onStop = { onStop(profile) },
                            )
                        }
                    }
                }
            }

            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .height(20.dp)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                MaterialTheme.colorScheme.background.copy(alpha = 0.95f),
                                Color.Transparent,
                            ),
                        ),
                    ),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(28.dp)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                MaterialTheme.colorScheme.background.copy(alpha = 0.95f),
                            ),
                        ),
                    ),
            )
        }
    }

    if (creating || editorProfile != null) {
        MachineEditorSheet(
            title = if (creating) "Add Machine Profile" else "Edit Machine Profile",
            initial = editorProfile,
            onDismiss = {
                creating = false
                editorProfile = null
            },
            onSave = { saved ->
                if (editorProfile == null) onCreate(saved) else onUpdate(saved)
                creating = false
                editorProfile = null
            },
            onOpenSettings = onOpenSettings
        )
    }
}

@Composable
private fun MachineGridCard(
    profile: MachineProfile,
    thumbnailRevision: Int,
    status: MachineStatus,
    isActive: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onConnect: () -> Unit,
    onFocus: () -> Unit,
    onStop: () -> Unit
) {
    val context = LocalContext.current
    val thumbnailBitmap = remember(profile.id, thumbnailRevision) {
        MachineThumbnailStore.load(context, profile.id)
    }
    val capabilities = profile.capabilities()
    val isRunning = status == MachineStatus.CONNECTED || status == MachineStatus.CONNECTING
    val statusColor = statusColorFor(status)
    val subtitle = machineSubtitle(profile)
    val summary = configurationSummary(profile)

    val cardShape = RoundedCornerShape(20.dp)
    // Lift the card visibly off the near-black compositor background, matching the
    // iOS glass card (white @ 0.05 over ultra-thin material).
    val cardSurface = lerp(
        MaterialTheme.colorScheme.surface,
        MaterialTheme.colorScheme.onSurface,
        0.07f,
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(WawonaTestTags.machinesCard(profile.id))
            .shadow(
                elevation = 20.dp,
                shape = cardShape,
                clip = false,
                ambientColor = Color.Black.copy(alpha = 0.35f),
                spotColor = Color.Black.copy(alpha = 0.45f),
            )
            .border(
                width = 1.dp,
                color = Color.White.copy(alpha = 0.2f),
                shape = cardShape,
            ),
        shape = cardShape,
        colors = CardDefaults.cardColors(containerColor = cardSurface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MachineCardBanner(
                profileName = profile.name,
                subtitle = subtitle,
                statusColor = statusColor,
                thumbnailBitmap = thumbnailBitmap
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    statusIconFor(status),
                    contentDescription = null,
                    tint = statusColor,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.size(6.dp))
                Text(
                    status.displayTitle,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = statusColor,
                    maxLines = 1,
                )
                Spacer(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StatusChip(machineScopeLabel(profile.type))
                    StatusChip(typeChipLabel(profile))
                    if (isActive) StatusChip("ACTIVE")
                }
            }

            Text(
                summary,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (isRunning) {
                    CompactOutlinedButton(
                        onClick = onFocus,
                        modifier = Modifier.weight(1f).testTag(WawonaTestTags.MACHINES_FOCUS),
                    ) {
                        Icon(Icons.Outlined.CenterFocusStrong, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(4.dp))
                        Text("Focus", maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    CompactFilledButton(
                        onClick = onStop,
                        modifier = Modifier.weight(1f).testTag(WawonaTestTags.MACHINES_STOP),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error,
                            contentColor = MaterialTheme.colorScheme.onError,
                        ),
                    ) {
                        Icon(Icons.Filled.Stop, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(4.dp))
                        Text("Stop", maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                } else {
                    CompactFilledButton(
                        onClick = onConnect,
                        modifier = Modifier.weight(1f).testTag(WawonaTestTags.MACHINES_START),
                        enabled = capabilities.launchSupported && status != MachineStatus.CONNECTING,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                        ),
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(4.dp))
                        Text(
                            when (status) {
                                MachineStatus.CONNECTING -> "Starting…"
                                else -> "Start"
                            },
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                CompactOutlinedButton(
                    onClick = onEdit,
                    modifier = Modifier.weight(1f).testTag(WawonaTestTags.MACHINES_EDIT),
                ) {
                    Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.size(4.dp))
                    Text("Edit", maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                CompactOutlinedButton(
                    onClick = onDelete,
                    enabled = !isRunning,
                    modifier = Modifier.weight(1f).testTag(WawonaTestTags.MACHINES_DELETE),
                    contentColor = MaterialTheme.colorScheme.error,
                    borderColor = MaterialTheme.colorScheme.error.copy(alpha = 0.5f),
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.size(4.dp))
                    Text("Delete", maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

private fun machineSubtitle(profile: MachineProfile): String = MachineSearch.subtitle(profile)

private fun configurationSummary(profile: MachineProfile): String = MachineSearch.summary(profile)

@Composable
private fun CompactOutlinedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    contentColor: Color = MaterialTheme.colorScheme.onSurface,
    borderColor: Color = MaterialTheme.colorScheme.outline,
    content: @Composable RowScope.() -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minWidth = 0.dp),
        enabled = enabled,
        contentPadding = compactButtonPadding,
        border = BorderStroke(1.dp, borderColor),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = contentColor,
        ),
        content = content,
    )
}

@Composable
private fun CompactFilledButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: androidx.compose.material3.ButtonColors = ButtonDefaults.buttonColors(),
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minWidth = 0.dp),
        enabled = enabled,
        contentPadding = compactButtonPadding,
        colors = colors,
        content = content,
    )
}

@Composable
private fun statusIconFor(status: MachineStatus) = when (status) {
    MachineStatus.CONNECTED -> Icons.Filled.CheckCircle
    MachineStatus.CONNECTING -> Icons.Filled.Sync
    MachineStatus.DEGRADED -> Icons.Filled.Warning
    MachineStatus.ERROR -> Icons.Filled.Error
    MachineStatus.DISCONNECTED -> Icons.Filled.PauseCircle
}

@Composable
private fun MachineCardBanner(
    profileName: String,
    subtitle: String,
    statusColor: Color,
    thumbnailBitmap: android.graphics.Bitmap?
) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(90.dp)
            .clip(shape)
    ) {
        if (thumbnailBitmap != null) {
            Image(
                bitmap = thumbnailBitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.linearGradient(
                            colors = listOf(
                                statusColor.copy(alpha = 0.32f),
                                Color(0xFF6366F1).copy(alpha = 0.18f)
                            )
                        )
                    )
            )
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.10f),
                            Color.Black.copy(alpha = 0.40f)
                        )
                    )
                )
        )
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    profileName.ifBlank { "Unnamed Machine" },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.82f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Icon(
                Icons.Filled.Computer,
                contentDescription = null,
                tint = statusColor,
                modifier = Modifier
                    .size(40.dp)
                    .background(Color.White.copy(alpha = 0.35f), RoundedCornerShape(10.dp))
                    .padding(8.dp)
            )
        }
    }
}

@Composable
private fun StatusChip(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        modifier = Modifier
            .background(
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.14f),
                RoundedCornerShape(50),
            )
            .padding(horizontal = 8.dp, vertical = 5.dp)
    )
}

private fun statusColorFor(status: MachineStatus): Color = when (status) {
    MachineStatus.CONNECTED -> Color(0xFF34D399)
    MachineStatus.CONNECTING -> Color(0xFF60A5FA)
    MachineStatus.DEGRADED -> Color(0xFFFBBF24)
    MachineStatus.ERROR -> Color(0xFFFB7185)
    MachineStatus.DISCONNECTED -> Color(0xFF94A3B8)
}

private fun machineScopeLabel(type: MachineType): String = when (type) {
    MachineType.NATIVE, MachineType.VM, MachineType.CONTAINER -> "LOCAL"
    MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> "REMOTE"
}

private fun typeChipLabel(profile: MachineProfile): String = when (profile.type) {
    MachineType.NATIVE -> "NATIVE"
    MachineType.SSH_WAYPIPE -> "SSH+WAYPIPE"
    MachineType.SSH_TERMINAL -> "SSH TERMINAL"
    MachineType.VM -> "VM"
    MachineType.CONTAINER -> "CONTAINER"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MachineEditorSheet(
    title: String,
    initial: MachineProfile?,
    onDismiss: () -> Unit,
    onSave: (MachineProfile) -> Unit,
    onOpenSettings: () -> Unit
) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE) }
    var showClientPicker by remember { mutableStateOf(false) }

    var name by remember { mutableStateOf(initial?.name ?: "") }
    var type by remember { mutableStateOf(initial?.type ?: MachineType.NATIVE) }
    var sshHost by remember { mutableStateOf(initial?.sshHost ?: "") }
    var sshPort by remember { mutableStateOf((initial?.sshPort ?: 22).toString()) }
    var sshUser by remember { mutableStateOf(initial?.sshUser ?: "") }
    var sshPassword by remember { mutableStateOf(initial?.sshPassword ?: "") }
    var sshKeyPath by remember { mutableStateOf(initial?.sshKeyPath ?: "") }
    var sshKeyPassphrase by remember { mutableStateOf(initial?.sshKeyPassphrase ?: "") }
    var sshAuthMethod by remember { mutableStateOf(initial?.sshAuthMethod ?: "password") }
    var nativeLauncher by remember { mutableStateOf(initial?.nativeLauncher ?: "weston-terminal") }
    var wasmModulePath by remember {
        mutableStateOf(initial?.runtimeOverrides?.optString("wasmModulePath", "") ?: "")
    }
    var remoteCommand by remember { mutableStateOf(initial?.remoteCommand ?: "") }
    var vmIdentifier by remember { mutableStateOf(initial?.vmSettings?.vmIdentifier ?: "") }
    var vmVsockPort by remember { mutableStateOf(initial?.vmSettings?.vsockPort ?: "") }
    var vmNotes by remember { mutableStateOf(initial?.vmSettings?.notes ?: "") }
    var containerRef by remember { mutableStateOf(initial?.containerSettings?.containerRef ?: "") }
    var containerRuntime by remember { mutableStateOf(initial?.containerSettings?.runtime ?: "docker") }
    var containerEntry by remember { mutableStateOf(initial?.containerSettings?.entryCommand ?: "") }
    var containerNotes by remember { mutableStateOf(initial?.containerSettings?.notes ?: "") }
    var machineTypePickerExpanded by remember { mutableStateOf(false) }
    var authMethodExpanded by remember { mutableStateOf(false) }
    var touchInputExpanded by remember { mutableStateOf(false) }
    var vulkanExpanded by remember { mutableStateOf(false) }
    var openglExpanded by remember { mutableStateOf(false) }
    var compositorBackendExpanded by remember { mutableStateOf(false) }

    val existingOverrides = remember(initial) {
        if (initial != null) SettingsOverrides.merge(initial) else JSONObject()
    }
    var machineThumbnailEnabled by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "machineThumbnailEnabledOverride", true))
    }
    var forceSsd by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "forceServerSideDecorations", prefs.getBoolean("forceServerSideDecorations", false)))
    }
    var autoScale by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "autoScale", prefs.getBoolean("autoRetinaScaling", true)))
    }
    var respectSafeArea by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "respectSafeArea",
                prefs.getBoolean("respectSafeArea", true)
            )
        )
    }
    var showVirtualPointer by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "renderMacOSPointer",
                prefs.getBoolean("renderMacOSPointer", false)
            )
        )
    }
    var nestedCompositorCursor by remember {
        mutableStateOf(
            SettingsOverrides.readString(
                existingOverrides,
                "nestedCompositorCursor",
                prefs.getString("nestedCompositorCursor", "virtual") ?: "virtual"
            ).let { if (it == "host") "host" else "virtual" }
        )
    }
    var nestedCursorExpanded by remember { mutableStateOf(false) }
    var touchInputType by remember {
        mutableStateOf(
            SettingsOverrides.readString(
                existingOverrides,
                "touchInputType",
                if (prefs.getBoolean("touchpadMode", false)) "Touchpad" else "Multi-Touch"
            )
        )
    }
    var swapCmdAlt by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "swapCmdWithAlt", prefs.getBoolean("swapCmdAsCtrl", false)))
    }
    var universalClipboard by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "universalClipboard", prefs.getBoolean("universalClipboard", false)))
    }
    var vulkanDriver by remember {
        mutableStateOf(
            readStringOverride(
                existingOverrides,
                "vulkanDriver",
                prefs.getString("vulkanDriver", "system") ?: "system"
            ).lowercase().takeIf { it in setOf("none", "swiftshader", "system") }
                ?: "system"
        )
    }
    var openglDriver by remember {
        mutableStateOf(readStringOverride(existingOverrides, "openglDriver", prefs.getString("openglDriver", "angle") ?: "angle"))
    }
    var compositorBackend by remember {
        mutableStateOf(
            SettingsOverrides.readString(
                existingOverrides,
                "compositorBackend",
                prefs.getString("compositorBackend", "auto") ?: "auto"
            ).lowercase().takeIf { it in setOf("auto", "wayland", "drm") }
                ?: "auto"
        )
    }
    var dmabufEnabled by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "dmabufEnabled", prefs.getBoolean("nestedCompositorsSupport", true)))
    }
    var colorOperations by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "colorOperations", prefs.getBoolean("colorSyncSupport", false)))
    }
    var shakeToCloseOverride by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "shakeToCloseEnabled",
                prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true)
            )
        )
    }
    var swipeBackOverride by remember {
        mutableStateOf(
            SettingsOverrides.readBool(
                existingOverrides,
                "swipeBackToCloseEnabled",
                prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true)
            )
        )
    }
    var machineEnvironment by remember {
        mutableStateOf(
            if (initial != null) EnvironmentOverrides.loadMachine(initial) else mutableMapOf()
        )
    }
    var showMachineEnvEditor by remember { mutableStateOf(false) }
    var machineEnvEditName by remember { mutableStateOf("") }
    var machineEnvEditValue by remember { mutableStateOf("") }
    var machineEnvIsNew by remember { mutableStateOf(false) }

    fun performSave() {
        val trimmedName = name.trim().ifEmpty { "Unnamed Machine" }
        val sanitizedHostPort = MachineInputSanitizer.splitHostAndPort(
            sshHost,
            sshPort.ifBlank { null },
            initial?.sshPort ?: 22
        )
        val base = initial ?: MachineProfile(name = trimmedName, type = type)
        val settingsOverrides = JSONObject(base.settingsOverrides.toString())
        writeBoolOverride(settingsOverrides, "machineThumbnailEnabledOverride", machineThumbnailEnabled, true)
        writeBoolOverride(settingsOverrides, "forceServerSideDecorations", forceSsd, prefs.getBoolean("forceServerSideDecorations", false))
        writeBoolOverride(settingsOverrides, "autoScale", autoScale, prefs.getBoolean("autoRetinaScaling", true))
        writeBoolOverride(settingsOverrides, "respectSafeArea", respectSafeArea, prefs.getBoolean("respectSafeArea", true))
        writeBoolOverride(
            settingsOverrides,
            "renderMacOSPointer",
            showVirtualPointer,
            prefs.getBoolean("renderMacOSPointer", false)
        )
        writeStringOverride(
            settingsOverrides,
            "nestedCompositorCursor",
            nestedCompositorCursor,
            prefs.getString("nestedCompositorCursor", "virtual") ?: "virtual"
        )
        writeStringOverride(
            settingsOverrides,
            "touchInputType",
            touchInputType,
            if (prefs.getBoolean("touchpadMode", false)) "Touchpad" else "Multi-Touch"
        )
        writeBoolOverride(settingsOverrides, "swapCmdWithAlt", swapCmdAlt, prefs.getBoolean("swapCmdAsCtrl", false))
        writeBoolOverride(settingsOverrides, "universalClipboard", universalClipboard, prefs.getBoolean("universalClipboard", false))
        writeStringOverride(settingsOverrides, "vulkanDriver", vulkanDriver, prefs.getString("vulkanDriver", "system") ?: "system")
        writeStringOverride(settingsOverrides, "openglDriver", openglDriver, prefs.getString("openglDriver", "angle") ?: "angle")
        writeStringOverride(
            settingsOverrides,
            "compositorBackend",
            compositorBackend,
            prefs.getString("compositorBackend", "auto") ?: "auto"
        )
        writeBoolOverride(settingsOverrides, "dmabufEnabled", dmabufEnabled, prefs.getBoolean("nestedCompositorsSupport", true))
        writeBoolOverride(settingsOverrides, "colorOperations", colorOperations, prefs.getBoolean("colorSyncSupport", false))
        writeBoolOverride(settingsOverrides, "shakeToCloseEnabled", shakeToCloseOverride, prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true))
        writeBoolOverride(settingsOverrides, "swipeBackToCloseEnabled", swipeBackOverride, prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true))
        val withEnv = EnvironmentOverrides.withMachineEnv(base, machineEnvironment)
        val runtimeOverrides = JSONObject(withEnv.runtimeOverrides.toString())
        val trimmedWasm = wasmModulePath.trim()
        if (nativeLauncher == "wawona-wasm" && trimmedWasm.isNotEmpty()) {
            runtimeOverrides.put("wasmModulePath", trimmedWasm)
            runtimeOverrides.put("bundledAppID", "wawona-wasm")
        } else {
            runtimeOverrides.remove("wasmModulePath")
        }
        onSave(
            base.copy(
                name = trimmedName,
                type = type,
                sshHost = sanitizedHostPort.host,
                sshPort = sanitizedHostPort.port,
                sshUser = sshUser.trim(),
                sshPassword = sshPassword,
                sshAuthMethod = sshAuthMethod.trim().ifEmpty { "password" },
                sshKeyPath = sshKeyPath.trim(),
                sshKeyPassphrase = sshKeyPassphrase,
                nativeLauncher = nativeLauncher,
                remoteCommand = remoteCommand.trim(),
                settingsOverrides = settingsOverrides,
                runtimeOverrides = runtimeOverrides,
                vmSettings = base.vmSettings.copy(
                    vmIdentifier = vmIdentifier.trim(),
                    vsockPort = vmVsockPort.trim(),
                    notes = vmNotes.trim()
                ),
                containerSettings = base.containerSettings.copy(
                    runtime = containerRuntime.trim().ifEmpty { "docker" },
                    containerRef = containerRef.trim(),
                    entryCommand = containerEntry.trim(),
                    notes = containerNotes.trim()
                )
            )
        )
    }

    WawonaModalSheet(
        onDismiss = onDismiss,
        title = if (showClientPicker) "Wayland Client" else title,
        defaultDetent = WawonaSheetDetent.Medium,
        scrollBehavior = WawonaSheetScrollBehavior.ContentFirst,
        navigationIcon = {
            if (showClientPicker) {
                IconButton(onClick = { showClientPicker = false }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            } else {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
        actions = {
            if (!showClientPicker) {
                TextButton(onClick = { performSave() }) {
                    Text("Save", fontWeight = FontWeight.SemiBold)
                }
            }
        },
    ) { contentScrollState ->
        LaunchedEffect(showClientPicker) { contentScrollState.scrollTo(0) }
        AnimatedContent(
            targetState = showClientPicker,
            modifier = Modifier.testTag(WawonaTestTags.MACHINES_EDITOR),
            transitionSpec = {
                val slideSpec = tween<androidx.compose.ui.unit.IntOffset>(durationMillis = 320, easing = FastOutSlowInEasing)
                val fadeSpec = tween<Float>(durationMillis = 220, easing = LinearOutSlowInEasing)
                val transform = if (targetState) {
                    (slideInHorizontally(slideSpec) { it } + fadeIn(fadeSpec)).togetherWith(
                        slideOutHorizontally(slideSpec) { -it / 4 } + fadeOut(fadeSpec),
                    )
                } else {
                    (slideInHorizontally(slideSpec) { -it } + fadeIn(fadeSpec)).togetherWith(
                        slideOutHorizontally(slideSpec) { it / 4 } + fadeOut(fadeSpec),
                    )
                }
                transform.using(SizeTransform(clip = false))
            },
            label = "machineEditorClientPicker",
        ) { pickingClient ->
            if (pickingClient) {
                BundledClientPicker(
                    selectedId = nativeLauncher,
                    scrollState = contentScrollState,
                    onSelect = { id ->
                        nativeLauncher = id
                        showClientPicker = false
                    },
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(contentScrollState)
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    EditorSectionCard(
                        title = "Connection Profile",
                        subtitle = "Name and type for this machine profile."
                    ) {
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it },
                            label = { Text("Display Name") },
                            placeholder = { Text("e.g. Studio Linux VM") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        MachineTypeDropdown(
                            selected = type,
                            expanded = machineTypePickerExpanded,
                            onExpandedChange = { machineTypePickerExpanded = it },
                            onSelect = {
                                type = it
                                machineTypePickerExpanded = false
                            }
                        )
                        HorizontalDivider()
                        ToggleRow("Show Session Thumbnail On Card", machineThumbnailEnabled) {
                            machineThumbnailEnabled = it
                        }
                    }

                    if (type == MachineType.NATIVE) {
                        EditorSectionCard(
                            title = "Wayland Client",
                            subtitle = "Choose a bundled client to connect directly to the compositor via Wayland socket. No SSH or network required."
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { showClientPicker = true }
                                    .padding(vertical = 8.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Bundled Client")
                                Text(
                                    if (nativeLauncher == "wawona-wasm" && wasmModulePath.isNotBlank()) {
                                        wasmModulePath.substringAfterLast('/')
                                    } else {
                                        BundledClients.labelFor(nativeLauncher)
                                    },
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            if (nativeLauncher == "wawona-wasm") {
                                OutlinedTextField(
                                    value = wasmModulePath,
                                    onValueChange = { wasmModulePath = it },
                                    label = { Text("Wasm module path") },
                                    placeholder = { Text("/sdcard/…/wayland-shm-rust.wasm") },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth()
                                )
                                Text(
                                    "Wayland WASI `.wasm` run by the bundled Wawona Runtime.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    if (type == MachineType.SSH_WAYPIPE || type == MachineType.SSH_TERMINAL) {
                        val isWaypipe = type == MachineType.SSH_WAYPIPE
                        EditorSectionCard(
                            title = if (isWaypipe) "SSH + Waypipe" else "SSH Connection",
                            subtitle = if (isWaypipe) {
                                "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe."
                            } else {
                                "Connects to a remote host via SSH and opens a terminal session."
                            }
                        ) {
                            OutlinedTextField(value = sshHost, onValueChange = { sshHost = it }, label = { Text("Host") }, placeholder = { Text("host.example.com") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = sshUser, onValueChange = { sshUser = it }, label = { Text("User") }, placeholder = { Text("username") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(
                                value = sshPort,
                                onValueChange = { sshPort = it.filter { ch -> ch.isDigit() }.take(5) },
                                label = { Text("Port") },
                                placeholder = { Text("22") },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                modifier = Modifier.fillMaxWidth()
                            )
                            OutlinedTextField(value = sshKeyPath, onValueChange = { sshKeyPath = it }, label = { Text("SSH Key Path") }, placeholder = { Text("~/.ssh/id_ed25519") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            AuthMethodDropdown(
                                selected = sshAuthMethod,
                                expanded = authMethodExpanded,
                                onExpandedChange = { authMethodExpanded = it },
                                onSelect = {
                                    sshAuthMethod = it
                                    authMethodExpanded = false
                                }
                            )
                            if (sshAuthMethod == "password") {
                                OutlinedTextField(
                                    value = sshPassword,
                                    onValueChange = { sshPassword = it },
                                    label = { Text("Password") },
                                    singleLine = true,
                                    visualTransformation = PasswordVisualTransformation(),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            } else {
                                OutlinedTextField(
                                    value = sshKeyPassphrase,
                                    onValueChange = { sshKeyPassphrase = it },
                                    label = { Text("Key Passphrase") },
                                    singleLine = true,
                                    visualTransformation = PasswordVisualTransformation(),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                            OutlinedTextField(
                                value = remoteCommand,
                                onValueChange = { remoteCommand = it },
                                label = { Text(if (isWaypipe) "Remote Command" else "Remote Shell Command") },
                                placeholder = { Text(if (isWaypipe) "weston-simple-shm" else "bash -l") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }

                    EditorSectionCard(
                        title = "Display / Input / Graphics",
                        subtitle = "Per-machine overrides for global Display, Input, Graphics, and HDR settings."
                    ) {
                        TextButton(onClick = onOpenSettings) {
                            Text("Open Wawona Settings…")
                        }
                        ToggleRow("Force Server-Side Decorations", forceSsd) { forceSsd = it }
                        ToggleRow("Auto Scale", autoScale) { autoScale = it }
                        ToggleRow("Respect Safe Area", respectSafeArea) { respectSafeArea = it }
                        ToggleRow("Show Virtual Cursor", showVirtualPointer) { showVirtualPointer = it }
                        StringDropdownField(
                            label = "Nested Compositor Cursor",
                            selected = if (nestedCompositorCursor == "host") "Host Cursor" else "Virtual Pointer",
                            options = listOf("Virtual Pointer", "Host Cursor"),
                            expanded = nestedCursorExpanded && showVirtualPointer,
                            onExpandedChange = { if (showVirtualPointer) nestedCursorExpanded = it },
                            onSelect = {
                                nestedCompositorCursor = if (it == "Host Cursor") "host" else "virtual"
                                nestedCursorExpanded = false
                            },
                            enabled = showVirtualPointer,
                        )
                        StringDropdownField(
                            label = "Touch Input Type",
                            selected = touchInputType,
                            options = listOf("Multi-Touch", "Touchpad"),
                            expanded = touchInputExpanded,
                            onExpandedChange = { touchInputExpanded = it },
                            onSelect = {
                                touchInputType = it
                                touchInputExpanded = false
                            }
                        )
                        ToggleRow("Swap CMD with ALT", swapCmdAlt) { swapCmdAlt = it }
                        ToggleRow("Universal Clipboard", universalClipboard) { universalClipboard = it }
                        StringDropdownField(
                            label = "Vulkan Driver",
                            selected = vulkanDriver,
                            options = listOf("none", "swiftshader", "system"),
                            expanded = vulkanExpanded,
                            onExpandedChange = { vulkanExpanded = it },
                            onSelect = {
                                vulkanDriver = it
                                vulkanExpanded = false
                            }
                        )
                        StringDropdownField(
                            label = "OpenGL Driver",
                            selected = openglDriver,
                            options = listOf("none", "angle", "system"),
                            expanded = openglExpanded,
                            onExpandedChange = { openglExpanded = it },
                            onSelect = {
                                openglDriver = it
                                openglExpanded = false
                            }
                        )
                        StringDropdownField(
                            label = "Display Backend",
                            selected = when (compositorBackend) {
                                "wayland" -> "Wayland (nested)"
                                "drm" -> "DRM/KMS (wwn-iland)"
                                else -> "Auto"
                            },
                            options = listOf("Auto", "Wayland (nested)", "DRM/KMS (wwn-iland)"),
                            expanded = compositorBackendExpanded,
                            onExpandedChange = { compositorBackendExpanded = it },
                            onSelect = {
                                compositorBackend = when (it) {
                                    "Wayland (nested)" -> "wayland"
                                    "DRM/KMS (wwn-iland)" -> "drm"
                                    else -> "auto"
                                }
                                compositorBackendExpanded = false
                            }
                        )
                        ToggleRow("Enable DMABUF", dmabufEnabled) { dmabufEnabled = it }
                        ToggleRow("Enable HDR", colorOperations) { colorOperations = it }
                        HorizontalDivider()
                        ToggleRow("Shake to Exit Machine", shakeToCloseOverride) { shakeToCloseOverride = it }
                        ToggleRow("Swipe Back to Exit Machine", swipeBackOverride) { swipeBackOverride = it }
                        HorizontalDivider()
                        Text(
                            "Env Vars (this machine)",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            if (machineEnvironment.isEmpty())
                                "Inherit global (Settings → Env Vars). Add overrides for this machine only."
                            else
                                "${machineEnvironment.size} machine override(s). Machine wins over global.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        machineEnvironment.toList().sortedBy { it.first }.forEach { (envName, entry) ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(envName, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        if (entry.action == "unset") "(unset)" else (entry.value ?: ""),
                                        fontFamily = FontFamily.Monospace,
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                                TextButton(onClick = {
                                    machineEnvIsNew = false
                                    machineEnvEditName = envName
                                    machineEnvEditValue = entry.value ?: ""
                                    showMachineEnvEditor = true
                                }) { Text("Edit") }
                                TextButton(onClick = {
                                    machineEnvironment = machineEnvironment.toMutableMap().also { it.remove(envName) }
                                }) { Text("Reset") }
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = {
                                machineEnvIsNew = true
                                machineEnvEditName = ""
                                machineEnvEditValue = ""
                                showMachineEnvEditor = true
                            }) { Text("New") }
                            if (machineEnvironment.isNotEmpty()) {
                                TextButton(onClick = { machineEnvironment = mutableMapOf() }) {
                                    Text("Clear all")
                                }
                            }
                        }
                        if (showMachineEnvEditor) {
                            AlertDialog(
                                onDismissRequest = { showMachineEnvEditor = false },
                                title = { Text(if (machineEnvIsNew) "New Variable" else "Edit Variable") },
                                text = {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        OutlinedTextField(
                                            value = machineEnvEditName,
                                            onValueChange = { machineEnvEditName = it },
                                            label = { Text("Name") },
                                            enabled = machineEnvIsNew,
                                            singleLine = true,
                                        )
                                        OutlinedTextField(
                                            value = machineEnvEditValue,
                                            onValueChange = { machineEnvEditValue = it },
                                            label = { Text("Value") },
                                            singleLine = true,
                                        )
                                    }
                                },
                                confirmButton = {
                                    TextButton(onClick = {
                                        val n = machineEnvEditName.trim()
                                        if (n.isNotEmpty()) {
                                            machineEnvironment = machineEnvironment.toMutableMap().also {
                                                it[n] = EnvironmentOverrides.Entry.set(machineEnvEditValue)
                                            }
                                        }
                                        showMachineEnvEditor = false
                                    }) { Text("Save") }
                                },
                                dismissButton = {
                                    TextButton(onClick = { showMachineEnvEditor = false }) { Text("Cancel") }
                                },
                            )
                        }
                    }

                    if (type == MachineType.VM) {
                        EditorSectionCard(
                            title = "Virtual Machine",
                            subtitle = "Hypervisor is selected automatically for this platform."
                        ) {
                            // VM engine is fixed per build target by wwn-vms and is
                            // not user-configurable (Residual E).
                            OutlinedTextField(value = "QEMU/AVF", onValueChange = {}, label = { Text("Backend") }, singleLine = true, readOnly = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmIdentifier, onValueChange = { vmIdentifier = it }, label = { Text("VM Identifier") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmVsockPort, onValueChange = { vmVsockPort = it }, label = { Text("VSock Port") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmNotes, onValueChange = { vmNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
                        }
                    }

                    if (type == MachineType.CONTAINER) {
                        EditorSectionCard(
                            title = "Container",
                            subtitle = "Container runtime is selected automatically for this platform."
                        ) {
                            // Container backend is fixed per build target by
                            // wwn-containers and is not user-configurable (Residual E).
                            OutlinedTextField(value = "container-in-VM", onValueChange = {}, label = { Text("Backend") }, singleLine = true, readOnly = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerRef, onValueChange = { containerRef = it }, label = { Text("Container Ref") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerEntry, onValueChange = { containerEntry = it }, label = { Text("Entry Command") }, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerNotes, onValueChange = { containerNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BundledClientPicker(
    selectedId: String,
    scrollState: ScrollState,
    onSelect: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(scrollState)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        BundledClients.all.forEach { client ->
            val isSelected = client.id == selectedId
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(
                        if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
                        else Color.Transparent
                    )
                    .clickable { onSelect(client.id) }
                    .padding(horizontal = 8.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Icon(
                    client.icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f),
                    modifier = Modifier.size(22.dp),
                )
                Column(Modifier.weight(1f)) {
                    Text(client.name, fontWeight = FontWeight.SemiBold)
                    Text(
                        client.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun EditorSectionCard(
    title: String,
    subtitle: String,
    content: @Composable () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                // Subtle lighter section fill matching iOS sectionCard (secondary @ 0.08).
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
                RoundedCornerShape(14.dp),
            )
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.28f),
                shape = RoundedCornerShape(14.dp),
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MachineTypeDropdown(
    selected: MachineType,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (MachineType) -> Unit
) {
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = onExpandedChange) {
        OutlinedTextField(
            value = selected.displayLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text("Type") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) {
            MachineType.entries.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(candidate.displayLabel) },
                    onClick = { onSelect(candidate) }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AuthMethodDropdown(
    selected: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (String) -> Unit
) {
    val label = if (selected == "key") "Key" else "Password"
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = onExpandedChange) {
        OutlinedTextField(
            value = label,
            onValueChange = {},
            readOnly = true,
            label = { Text("Auth Method") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) {
            DropdownMenuItem(text = { Text("Password") }, onClick = { onSelect("password") })
            DropdownMenuItem(text = { Text("Key") }, onClick = { onSelect("key") })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StringDropdownField(
    label: String,
    selected: String,
    options: List<String>,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (String) -> Unit,
    enabled: Boolean = true,
) {
    ExposedDropdownMenuBox(
        expanded = expanded && enabled,
        onExpandedChange = { if (enabled) onExpandedChange(it) },
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded && enabled) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded && enabled, onDismissRequest = { onExpandedChange(false) }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(option) }, onClick = { onSelect(option) })
            }
        }
    }
}