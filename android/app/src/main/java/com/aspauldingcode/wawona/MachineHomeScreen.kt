package com.aspauldingcode.wawona

import android.content.Context
import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.CenterFocusStrong
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
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
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

private data class BundledClientOption(
    val id: String,
    val name: String,
    val description: String
)

private val bundledClients = listOf(
    BundledClientOption("weston-simple-shm", "Weston Simple SHM", "Minimal shared-memory Wayland client"),
    BundledClientOption("weston", "Weston", "Wayland reference compositor (nested compositor)"),
    BundledClientOption("weston-terminal", "Weston Terminal", "Terminal emulator — uses host cursor"),
    BundledClientOption("foot", "Foot Terminal", "Lightweight Wayland terminal emulator"),
    BundledClientOption("weston-flower", "Weston Flower", "Animated cairo demo (toytoolkit)"),
    BundledClientOption("kmscube", "KMS Cube", "Spinning GL cube via iland + ANGLE"),
    BundledClientOption("weston-simple-egl", "Weston Simple EGL", "Wayland EGL demo client"),
    BundledClientOption("weston-smoke", "Weston Smoke", "Smoke particle cairo demo"),
    BundledClientOption("weston-clickdot", "Weston Clickdot", "Pointer click visualization demo"),
    BundledClientOption("weston-eventdemo", "Weston Event Demo", "Input event logging demo"),
    BundledClientOption("weston-resizor", "Weston Resizor", "Interactive resize demo"),
    BundledClientOption("weston-cliptest", "Weston Cliptest", "Clipping region demo"),
    BundledClientOption("weston-transformed", "Weston Transformed", "Buffer transform demo"),
    BundledClientOption("weston-stacking", "Weston Stacking", "Subsurface stacking demo"),
    BundledClientOption("weston-dnd", "Weston DnD", "Drag-and-drop demo"),
    BundledClientOption("weston-image", "Weston Image", "PNG image loader demo"),
    BundledClientOption("weston-scaler", "Weston Scaler", "Viewport scaler demo"),
    BundledClientOption("weston-editor", "Weston Editor", "Text editor demo"),
    BundledClientOption("weston-constraints", "Weston Constraints", "Pointer constraints demo"),
)

private fun bundledClientLabel(id: String): String =
    bundledClients.firstOrNull { it.id == id }?.name ?: id

private const val ANDROID_16_API = 36

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
    var legacyOverflowExpanded by remember { mutableStateOf(false) }
    var scopeFilter by remember { mutableStateOf(MachineScopeFilter.ALL) }
    val expressiveQuickActionsSupported = Build.VERSION.SDK_INT >= ANDROID_16_API
    val listBottomPadding = if (expressiveQuickActionsSupported) 112.dp else 12.dp

    val visibleProfiles = remember(profiles, scopeFilter) {
        profiles.filter { scopeFilter.matches(it.type) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Machine Configuration") },
                actions = {
                    if (!expressiveQuickActionsSupported) {
                        TextButton(onClick = onOpenSettings) {
                            Icon(Icons.Filled.Settings, contentDescription = null)
                        }
                        TextButton(onClick = { creating = true }) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                        }
                        Box {
                            TextButton(onClick = { legacyOverflowExpanded = true }) {
                                Icon(Icons.Filled.MoreVert, contentDescription = "More actions")
                            }
                            DropdownMenu(
                                expanded = legacyOverflowExpanded,
                                onDismissRequest = { legacyOverflowExpanded = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Settings") },
                                    leadingIcon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                                    onClick = {
                                        legacyOverflowExpanded = false
                                        onOpenSettings()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Add Machine Profile") },
                                    leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) },
                                    onClick = {
                                        legacyOverflowExpanded = false
                                        creating = true
                                    }
                                )
                            }
                        }
                    } else {
                        TextButton(onClick = onOpenSettings) {
                            Icon(Icons.Filled.Settings, contentDescription = "Settings")
                        }
                    }
                }
            )
        },
        floatingActionButton = {
            if (expressiveQuickActionsSupported) {
                ExpressiveSpeedDialFab(
                    actions = listOf(
                        SpeedDialAction(
                            label = "Add Machine Profile",
                            icon = Icons.Filled.Add,
                            onClick = { creating = true },
                        ),
                    ),
                )
            }
        }
    ) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 280.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(
                start = 16.dp,
                top = 12.dp,
                end = 16.dp,
                bottom = listBottomPadding
            ),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    MachineScopeFilter.entries.forEachIndexed { index, filter ->
                        SegmentedButton(
                            selected = scopeFilter == filter,
                            onClick = { scopeFilter = filter },
                            shape = SegmentedButtonDefaults.itemShape(
                                index = index,
                                count = MachineScopeFilter.entries.size
                            )
                        ) {
                            Text(filter.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }

            if (visibleProfiles.isEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(20.dp)) {
                            Text(
                                "No Matching Machines",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "Adjust the scope filter or add a new machine profile.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            } else {
                items(visibleProfiles, key = { it.id }) { profile ->
                    AnimatedVisibility(
                        visible = true,
                        enter = fadeIn() + scaleIn(initialScale = 0.95f, animationSpec = spring())
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
                            onStop = { onStop(profile) }
                        )
                    }
                }
            }
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

@OptIn(ExperimentalLayoutApi::class)
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

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
        )
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
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    status.displayTitle,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = statusColor
                )
                Spacer(Modifier.weight(1f))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
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

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (isRunning) {
                    OutlinedButton(onClick = onFocus) {
                        Icon(Icons.Outlined.CenterFocusStrong, contentDescription = null)
                        Spacer(Modifier.size(4.dp))
                        Text("Focus")
                    }
                    Button(
                        onClick = onStop,
                        colors = ButtonDefaultsButtonColors()
                    ) {
                        Icon(Icons.Filled.Stop, contentDescription = null)
                        Spacer(Modifier.size(4.dp))
                        Text("Stop")
                    }
                } else {
                    Button(
                        onClick = onConnect,
                        enabled = capabilities.launchSupported && status != MachineStatus.CONNECTING
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Spacer(Modifier.size(4.dp))
                        Text(
                            when (status) {
                                MachineStatus.CONNECTING -> "Starting…"
                                else -> "Start"
                            }
                        )
                    }
                }
                OutlinedButton(onClick = onEdit) {
                    Icon(Icons.Filled.Edit, contentDescription = null)
                    Spacer(Modifier.size(4.dp))
                    Text("Edit")
                }
                OutlinedButton(
                    onClick = onDelete,
                    enabled = !isRunning
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = null)
                    Spacer(Modifier.size(4.dp))
                    Text("Delete")
                }
            }
        }
    }
}

@Composable
private fun ButtonDefaultsButtonColors() =
    androidx.compose.material3.ButtonDefaults.buttonColors(
        containerColor = MaterialTheme.colorScheme.error,
        contentColor = MaterialTheme.colorScheme.onError
    )

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
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                RoundedCornerShape(50)
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

private fun machineSubtitle(profile: MachineProfile): String = when (profile.type) {
    MachineType.NATIVE -> bundledClientLabel(profile.nativeLauncher)
    MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> {
        if (profile.sshHost.isBlank()) "SSH endpoint not configured"
        else "${profile.sshUser.ifBlank { "user" }}@${profile.sshHost}"
    }
    MachineType.VM -> "VM profile (${profile.vmSubtype.uppercase()})"
    MachineType.CONTAINER -> "Container profile (${profile.containerSubtype.uppercase()})"
}

private fun configurationSummary(profile: MachineProfile): String = when (profile.type) {
    MachineType.NATIVE -> {
        val client = bundledClientLabel(profile.nativeLauncher)
        if (client.isBlank()) "No client configured — edit to select one"
        else "Runs: $client"
    }
    MachineType.SSH_WAYPIPE -> {
        val cmd = profile.remoteCommand.ifBlank { "weston-simple-shm" }
        "Waypipe command: $cmd"
    }
    MachineType.SSH_TERMINAL -> {
        val cmd = profile.remoteCommand.ifBlank { "bash -l" }
        "SSH terminal command: $cmd"
    }
    MachineType.VM -> "Subtype: ${profile.vmSubtype.ifBlank { "qemu" }}"
    MachineType.CONTAINER -> "Subtype: ${profile.containerSubtype.ifBlank { "docker" }}"
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
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
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
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
    var nativeLauncher by remember { mutableStateOf(initial?.nativeLauncher ?: "weston-simple-shm") }
    var remoteCommand by remember { mutableStateOf(initial?.remoteCommand ?: "") }
    var vmIdentifier by remember { mutableStateOf(initial?.vmSettings?.vmIdentifier ?: "") }
    var vmVsockPort by remember { mutableStateOf(initial?.vmSettings?.vsockPort ?: "") }
    var vmNotes by remember { mutableStateOf(initial?.vmSettings?.notes ?: "") }
    var vmSubtype by remember { mutableStateOf(initial?.vmSubtype ?: "qemu") }
    var containerRef by remember { mutableStateOf(initial?.containerSettings?.containerRef ?: "") }
    var containerRuntime by remember { mutableStateOf(initial?.containerSettings?.runtime ?: "docker") }
    var containerEntry by remember { mutableStateOf(initial?.containerSettings?.entryCommand ?: "") }
    var containerNotes by remember { mutableStateOf(initial?.containerSettings?.notes ?: "") }
    var containerSubtype by remember { mutableStateOf(initial?.containerSubtype ?: "docker") }
    var machineTypePickerExpanded by remember { mutableStateOf(false) }
    var authMethodExpanded by remember { mutableStateOf(false) }
    var touchInputExpanded by remember { mutableStateOf(false) }
    var vulkanExpanded by remember { mutableStateOf(false) }
    var openglExpanded by remember { mutableStateOf(false) }

    val existingOverrides = remember(initial) {
        if (initial?.settingsOverrides != null) JSONObject(initial.settingsOverrides.toString()) else JSONObject()
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
        mutableStateOf(readBoolOverride(existingOverrides, "respectSafeArea", prefs.getBoolean("respectSafeArea", true)))
    }
    var showVirtualPointer by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "renderMacOSPointer", true))
    }
    var touchInputType by remember {
        mutableStateOf(readStringOverride(existingOverrides, "touchInputType", "Multi-Touch"))
    }
    var swapCmdAlt by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "swapCmdWithAlt", prefs.getBoolean("swapCmdAsCtrl", false)))
    }
    var universalClipboard by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "universalClipboard", prefs.getBoolean("universalClipboard", false)))
    }
    var vulkanDriver by remember {
        mutableStateOf(readStringOverride(existingOverrides, "vulkanDriver", prefs.getString("vulkanDriver", "none") ?: "none"))
    }
    var openglDriver by remember {
        mutableStateOf(readStringOverride(existingOverrides, "openglDriver", prefs.getString("openglDriver", "none") ?: "none"))
    }
    var dmabufEnabled by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "dmabufEnabled", prefs.getBoolean("nestedCompositorsSupport", true)))
    }
    var colorOperations by remember {
        mutableStateOf(readBoolOverride(existingOverrides, "colorOperations", prefs.getBoolean("colorSyncSupport", false)))
    }

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
        writeBoolOverride(settingsOverrides, "renderMacOSPointer", showVirtualPointer, true)
        writeStringOverride(settingsOverrides, "touchInputType", touchInputType, "Multi-Touch")
        writeBoolOverride(settingsOverrides, "swapCmdWithAlt", swapCmdAlt, prefs.getBoolean("swapCmdAsCtrl", false))
        writeBoolOverride(settingsOverrides, "universalClipboard", universalClipboard, prefs.getBoolean("universalClipboard", false))
        writeStringOverride(settingsOverrides, "vulkanDriver", vulkanDriver, prefs.getString("vulkanDriver", "none") ?: "none")
        writeStringOverride(settingsOverrides, "openglDriver", openglDriver, prefs.getString("openglDriver", "none") ?: "none")
        writeBoolOverride(settingsOverrides, "dmabufEnabled", dmabufEnabled, prefs.getBoolean("nestedCompositorsSupport", true))
        writeBoolOverride(settingsOverrides, "colorOperations", colorOperations, prefs.getBoolean("colorSyncSupport", false))
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
                vmSubtype = vmSubtype.trim().ifEmpty { "qemu" },
                containerSubtype = containerSubtype.trim().ifEmpty { "docker" },
                settingsOverrides = settingsOverrides,
                vmSettings = base.vmSettings.copy(
                    vmIdentifier = vmIdentifier.trim(),
                    vsockPort = vmVsockPort.trim(),
                    notes = vmNotes.trim(),
                    provider = vmSubtype.trim().ifEmpty { "qemu" }
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

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = screenHeight * 0.75f, max = screenHeight * 0.92f)
        ) {
            TopAppBar(
                title = {
                    Text(
                        if (showClientPicker) "Wayland Client" else title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
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
                }
            )

            if (showClientPicker) {
                BundledClientPicker(
                    selectedId = nativeLauncher,
                    onSelect = { id ->
                        nativeLauncher = id
                        showClientPicker = false
                    }
                )
            } else {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
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
                                    bundledClientLabel(nativeLauncher),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
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
                        ToggleRow("Show Virtual Pointer", showVirtualPointer) { showVirtualPointer = it }
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
                            options = listOf("none", "swiftshader", "turnip", "system"),
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
                        ToggleRow("Enable DMABUF", dmabufEnabled) { dmabufEnabled = it }
                        ToggleRow("HDR / Color Operations", colorOperations) { colorOperations = it }
                    }

                    if (type == MachineType.VM) {
                        EditorSectionCard(
                            title = "Virtual Machine",
                            subtitle = "Hypervisor metadata for launch orchestration."
                        ) {
                            OutlinedTextField(value = vmSubtype, onValueChange = { vmSubtype = it }, label = { Text("Subtype") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmIdentifier, onValueChange = { vmIdentifier = it }, label = { Text("VM Identifier") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmVsockPort, onValueChange = { vmVsockPort = it }, label = { Text("VSock Port") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = vmNotes, onValueChange = { vmNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
                        }
                    }

                    if (type == MachineType.CONTAINER) {
                        EditorSectionCard(
                            title = "Container",
                            subtitle = "Container runtime and startup command."
                        ) {
                            OutlinedTextField(value = containerSubtype, onValueChange = { containerSubtype = it }, label = { Text("Subtype") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = containerRuntime, onValueChange = { containerRuntime = it }, label = { Text("Runtime") }, singleLine = true, modifier = Modifier.fillMaxWidth())
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
    onSelect: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        bundledClients.forEach { client ->
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
                    tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
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
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            content()
        }
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
    onSelect: (String) -> Unit
) {
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = onExpandedChange) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(option) }, onClick = { onSelect(option) })
            }
        }
    }
}