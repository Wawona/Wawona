package com.aspauldingcode.wawona

import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedAssistChip
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeFloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import org.json.JSONObject

private data class NativeLauncherOption(
    val value: String,
    val label: String
)

private val nativeLauncherOptions = listOf(
    NativeLauncherOption("weston-simple-shm", "Weston Simple SHM"),
    NativeLauncherOption("weston-terminal", "Weston Terminal"),
    NativeLauncherOption("foot", "Foot Terminal"),
    NativeLauncherOption("weston", "Weston")
)

private fun nativeLauncherLabel(value: String): String =
    nativeLauncherOptions.firstOrNull { it.value == value }?.label ?: value

private const val ANDROID_16_API = 36
private const val INHERIT_GLOBAL_OPTION = "Inherit global"

private enum class BooleanOverride(val label: String, val encodedValue: Boolean?) {
    INHERIT("Inherit global", null),
    ENABLED("Enabled", true),
    DISABLED("Disabled", false)
}

private fun readBooleanOverride(settingsOverrides: JSONObject?, key: String): BooleanOverride {
    if (settingsOverrides == null || !settingsOverrides.has(key)) return BooleanOverride.INHERIT
    val raw = settingsOverrides.opt(key)
    val encoded = when (raw) {
        is JSONObject -> {
            when (raw.optString("type", "")) {
                "boolean" -> if (raw.optBoolean("value", false)) BooleanOverride.ENABLED else BooleanOverride.DISABLED
                else -> null
            }
        }
        is Boolean -> if (raw) BooleanOverride.ENABLED else BooleanOverride.DISABLED
        else -> null
    }
    return encoded ?: BooleanOverride.INHERIT
}

private fun writeBooleanOverride(settingsOverrides: JSONObject, key: String, value: BooleanOverride) {
    if (value.encodedValue == null) {
        settingsOverrides.remove(key)
        return
    }
    settingsOverrides.put(
        key,
        JSONObject().apply {
            put("type", "boolean")
            put("value", value.encodedValue)
        }
    )
}

private fun readStringOverride(settingsOverrides: JSONObject?, key: String): String? {
    if (settingsOverrides == null || !settingsOverrides.has(key)) return null
    return when (val raw = settingsOverrides.opt(key)) {
        is JSONObject -> {
            when (raw.optString("type", "")) {
                "string" -> raw.optString("value", "")
                else -> null
            }
        }
        is String -> raw
        else -> null
    }?.ifBlank { null }
}

private fun writeStringOverride(settingsOverrides: JSONObject, key: String, value: String) {
    if (value == INHERIT_GLOBAL_OPTION || value.isBlank()) {
        settingsOverrides.remove(key)
        return
    }
    settingsOverrides.put(
        key,
        JSONObject().apply {
            put("type", "string")
            put("value", value)
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MachineWelcomeScreen(
    profiles: List<MachineProfile>,
    sessions: List<MachineSession>,
    machineStatusFor: (String) -> MachineStatus,
    onCreate: (MachineProfile) -> Unit,
    onUpdate: (MachineProfile) -> Unit,
    onDelete: (MachineProfile) -> Unit,
    onConnect: (MachineProfile) -> Unit,
    onOpenSession: (MachineSession) -> Unit,
    onOpenSettings: () -> Unit
) {
    var editorProfile by remember { mutableStateOf<MachineProfile?>(null) }
    var creating by remember { mutableStateOf(false) }
    var quickActionsExpanded by remember { mutableStateOf(false) }
    var legacyOverflowExpanded by remember { mutableStateOf(false) }
    val snackbars = remember { SnackbarHostState() }
    val expressiveQuickActionsSupported = Build.VERSION.SDK_INT >= ANDROID_16_API
    val listBottomPadding = if (expressiveQuickActionsSupported) 112.dp else 12.dp

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Wawona Machines") },
                actions = {
                    if (!expressiveQuickActionsSupported) {
                        TextButton(onClick = onOpenSettings) {
                            Icon(Icons.Filled.Settings, contentDescription = null)
                            Spacer(Modifier.size(6.dp))
                            Text("Settings")
                        }
                        TextButton(onClick = { creating = true }) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Spacer(Modifier.size(6.dp))
                            Text("Add")
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
                                    text = { Text("Wawona Settings") },
                                    leadingIcon = {
                                        Icon(Icons.Filled.Settings, contentDescription = null)
                                    },
                                    onClick = {
                                        legacyOverflowExpanded = false
                                        onOpenSettings()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Create Machine") },
                                    leadingIcon = {
                                        Icon(Icons.Filled.Add, contentDescription = null)
                                    },
                                    onClick = {
                                        legacyOverflowExpanded = false
                                        creating = true
                                    }
                                )
                            }
                        }
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbars) },
        floatingActionButton = {
            if (expressiveQuickActionsSupported) {
                Box {
                    LargeFloatingActionButton(
                        onClick = { quickActionsExpanded = !quickActionsExpanded }
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = "Machine actions")
                    }
                    DropdownMenu(
                        expanded = quickActionsExpanded,
                        onDismissRequest = { quickActionsExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Wawona Settings") },
                            leadingIcon = {
                                Icon(Icons.Filled.Settings, contentDescription = null)
                            },
                            onClick = {
                                quickActionsExpanded = false
                                onOpenSettings()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Create Machine") },
                            leadingIcon = {
                                Icon(Icons.Filled.Add, contentDescription = null)
                            },
                            onClick = {
                                quickActionsExpanded = false
                                creating = true
                            }
                        )
                    }
                }
            }
        }
    ) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 300.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(
                start = 16.dp,
                top = 12.dp,
                end = 16.dp,
                bottom = listBottomPadding
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(
                    "Saved machines",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
                )
            }

            if (profiles.isEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp)) {
                            Text("No machines yet")
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "Create your first machine to start local, SSH, VM, or container sessions.",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }
            } else {
                items(profiles, key = { it.id }) { profile ->
                    AnimatedVisibility(
                        visible = true,
                        enter = fadeIn() + scaleIn(initialScale = 0.92f, animationSpec = spring())
                    ) {
                        MachineGridCard(
                            profile = profile,
                            status = machineStatusFor(profile.id),
                            onEdit = { editorProfile = profile },
                            onDelete = { onDelete(profile) },
                            onConnect = { onConnect(profile) }
                        )
                    }
                }
            }

            if (sessions.isNotEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Spacer(Modifier.height(8.dp))
                }
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Text(
                        "Active sessions",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
                    )
                }
                items(sessions, key = { it.sessionId }) { session ->
                    val sessionActionLabel = when (session.state) {
                        MachineSessionState.DISCONNECTED,
                        MachineSessionState.DEGRADED,
                        MachineSessionState.ERROR -> "Reopen"
                        else -> "Open"
                    }
                    val actionEnabled = session.state != MachineSessionState.CONNECTING
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = actionEnabled) { onOpenSession(session) }
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(session.machineName, fontWeight = FontWeight.SemiBold)
                                Text(
                                    "${session.machineType.value} - ${session.state.name.lowercase()}",
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                            OutlinedButton(
                                enabled = actionEnabled,
                                onClick = { onOpenSession(session) }
                            ) {
                                Text(sessionActionLabel)
                            }
                        }
                    }
                }
            }
        }
    }

    if (creating || editorProfile != null) {
        MachineEditorSheet(
            title = if (creating) "Add Machine" else "Edit Machine",
            initial = editorProfile,
            onDismiss = {
                creating = false
                editorProfile = null
            },
            onSave = {
                if (editorProfile == null) {
                    onCreate(it)
                } else {
                    onUpdate(it)
                }
                creating = false
                editorProfile = null
            }
        )
    }

    LaunchedEffect(profiles.isEmpty()) {
        if (profiles.isEmpty()) {
            snackbars.showSnackbar("Add a machine to begin.")
        }
    }
}

@Composable
private fun MachineGridCard(
    profile: MachineProfile,
    status: MachineStatus,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onConnect: () -> Unit
) {
    val capabilities = profile.capabilities()
    val statusColor = when (status) {
        MachineStatus.CONNECTED -> Color(0xFF34D399)
        MachineStatus.CONNECTING -> Color(0xFF60A5FA)
        MachineStatus.DEGRADED -> Color(0xFFFBBF24)
        MachineStatus.ERROR -> Color(0xFFFB7185)
        MachineStatus.DISCONNECTED -> MaterialTheme.colorScheme.outline
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(profile.name, fontWeight = FontWeight.SemiBold)
                ElevatedAssistChip(
                    onClick = {},
                    label = { Text(status.name.lowercase()) },
                    leadingIcon = {
                        Icon(
                            Icons.Filled.Computer,
                            contentDescription = null,
                            tint = statusColor
                        )
                    }
                )
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ElevatedAssistChip(onClick = {}, label = { Text(machineScopeLabel(profile.type)) })
                ElevatedAssistChip(onClick = {}, label = { Text(typeLabel(profile)) })
                if (!capabilities.launchSupported) {
                    ElevatedAssistChip(onClick = {}, label = { Text("Stub") })
                }
            }

            Text(
                connectionLabel(profile),
                style = MaterialTheme.typography.bodySmall
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(onClick = onEdit) {
                    Icon(Icons.Filled.Edit, contentDescription = null)
                    Spacer(Modifier.size(4.dp))
                    Text("Edit")
                }
                OutlinedButton(onClick = onDelete) {
                    Icon(Icons.Filled.Delete, contentDescription = null)
                    Spacer(Modifier.size(4.dp))
                    Text("Delete")
                }
            }

            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = onConnect,
                enabled = capabilities.launchSupported && status != MachineStatus.CONNECTING
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Spacer(Modifier.size(6.dp))
                AnimatedContent(targetState = status, label = "runStatus") { current ->
                    Text(
                        when (current) {
                            MachineStatus.CONNECTING -> "Starting..."
                            MachineStatus.CONNECTED -> "Running"
                            else -> "Run Machine"
                        }
                    )
                }
            }
        }
    }
}

private fun machineScopeLabel(type: MachineType): String = when (type) {
    MachineType.NATIVE, MachineType.VM, MachineType.CONTAINER -> "Local"
    MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> "Remote"
}

private fun typeLabel(profile: MachineProfile): String = when (profile.type) {
    MachineType.NATIVE -> "Native (${nativeLauncherLabel(profile.nativeLauncher)})"
    MachineType.SSH_WAYPIPE -> "SSH Waypipe"
    MachineType.SSH_TERMINAL -> "SSH Terminal"
    MachineType.VM -> "VM ${profile.vmSubtype.uppercase()}"
    MachineType.CONTAINER -> "Container ${profile.containerSubtype.uppercase()}"
}

private fun connectionLabel(profile: MachineProfile): String = when (profile.type) {
    MachineType.NATIVE -> "This device"
    MachineType.VM -> "VM id: ${profile.vmSettings.vmIdentifier.ifBlank { "n/a" }}"
    MachineType.CONTAINER -> "Container: ${profile.containerSettings.containerRef.ifBlank { "n/a" }}"
    MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> {
        if (profile.sshHost.isBlank()) "SSH target not configured"
        else "${profile.sshUser.ifBlank { "user" }}@${profile.sshHost}"
    }
}

@Composable
fun MachineSessionStrip(
    sessions: List<MachineSession>,
    activeSessionId: String?,
    onShowMachines: () -> Unit,
    onSelectSession: (MachineSession) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Sessions", fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onShowMachines) {
                    Icon(Icons.Filled.Computer, contentDescription = null)
                    Spacer(Modifier.size(4.dp))
                    Text("Machines")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                sessions.forEach { session ->
                    ElevatedAssistChip(
                        onClick = { onSelectSession(session) },
                        label = {
                            val marker = if (session.sessionId == activeSessionId) "●" else "○"
                            Text("$marker ${session.machineName}")
                        }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MachineEditorSheet(
    title: String,
    initial: MachineProfile?,
    onDismiss: () -> Unit,
    onSave: (MachineProfile) -> Unit
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var type by remember { mutableStateOf(initial?.type ?: MachineType.NATIVE) }
    var sshHost by remember { mutableStateOf(initial?.sshHost ?: "") }
    var sshUser by remember { mutableStateOf(initial?.sshUser ?: "") }
    var sshPassword by remember { mutableStateOf(initial?.sshPassword ?: "") }
    var sshBinary by remember { mutableStateOf(initial?.sshBinary ?: "ssh") }
    var sshAuthMethod by remember { mutableStateOf(initial?.sshAuthMethod ?: "password") }
    var sshKeyPath by remember { mutableStateOf(initial?.sshKeyPath ?: "") }
    var sshKeyPassphrase by remember { mutableStateOf(initial?.sshKeyPassphrase ?: "") }
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
    var nativeLauncherPickerExpanded by remember { mutableStateOf(false) }
    val existingOverrides = remember(initial) {
        if (initial?.settingsOverrides != null) JSONObject(initial.settingsOverrides.toString()) else JSONObject()
    }
    var overrideAutoScale by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "autoScale"))
    }
    var overrideRespectSafeArea by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "respectSafeArea"))
    }
    var overrideTouchpadMode by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "touchpadMode"))
    }
    var overrideTextAssist by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "enableTextAssist"))
    }
    var overrideDictation by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "enableDictation"))
    }
    var overrideDmabufEnabled by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "dmabufEnabled"))
    }
    var overrideColorOperations by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "colorOperations"))
    }
    var overrideShakeToClose by remember {
        mutableStateOf(readBooleanOverride(existingOverrides, "wawona.pref.shakeToCloseEnabled"))
    }
    var overrideVulkanDriver by remember {
        mutableStateOf(readStringOverride(existingOverrides, "vulkanDriver") ?: INHERIT_GLOBAL_OPTION)
    }
    var overrideOpenGLDriver by remember {
        mutableStateOf(readStringOverride(existingOverrides, "openglDriver") ?: INHERIT_GLOBAL_OPTION)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Machine name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            ExposedDropdownMenuBox(
                expanded = machineTypePickerExpanded,
                onExpandedChange = { machineTypePickerExpanded = it }
            ) {
                OutlinedTextField(
                    value = type.value,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Machine type") },
                    trailingIcon = {
                        ExposedDropdownMenuDefaults.TrailingIcon(expanded = machineTypePickerExpanded)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor()
                )
                DropdownMenu(
                    expanded = machineTypePickerExpanded,
                    onDismissRequest = { machineTypePickerExpanded = false }
                ) {
                    MachineType.entries.forEach { candidate ->
                        DropdownMenuItem(
                            text = { Text(candidate.value) },
                            onClick = {
                                type = candidate
                                machineTypePickerExpanded = false
                            }
                        )
                    }
                }
            }

            if (type == MachineType.NATIVE) {
                ExposedDropdownMenuBox(
                    expanded = nativeLauncherPickerExpanded,
                    onExpandedChange = { nativeLauncherPickerExpanded = it }
                ) {
                    OutlinedTextField(
                        value = nativeLauncherLabel(nativeLauncher),
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Bundled native app") },
                        trailingIcon = {
                            ExposedDropdownMenuDefaults.TrailingIcon(expanded = nativeLauncherPickerExpanded)
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor()
                    )
                    DropdownMenu(
                        expanded = nativeLauncherPickerExpanded,
                        onDismissRequest = { nativeLauncherPickerExpanded = false }
                    ) {
                        nativeLauncherOptions.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.label) },
                                onClick = {
                                    nativeLauncher = option.value
                                    nativeLauncherPickerExpanded = false
                                }
                            )
                        }
                    }
                }
            }

            if (type == MachineType.SSH_WAYPIPE || type == MachineType.SSH_TERMINAL) {
                OutlinedTextField(value = sshHost, onValueChange = { sshHost = it }, label = { Text("SSH host") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshUser, onValueChange = { sshUser = it }, label = { Text("SSH user") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    value = sshPassword,
                    onValueChange = { sshPassword = it },
                    label = { Text("SSH password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(value = sshBinary, onValueChange = { sshBinary = it }, label = { Text("SSH binary") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshAuthMethod, onValueChange = { sshAuthMethod = it }, label = { Text("SSH auth method (password|key)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshKeyPath, onValueChange = { sshKeyPath = it }, label = { Text("SSH key path") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    value = sshKeyPassphrase,
                    onValueChange = { sshKeyPassphrase = it },
                    label = { Text("SSH key passphrase") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(value = remoteCommand, onValueChange = { remoteCommand = it }, label = { Text("Remote command") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }

            if (type == MachineType.VM) {
                OutlinedTextField(value = vmSubtype, onValueChange = { vmSubtype = it }, label = { Text("VM subtype (qemu/utm/other)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = vmIdentifier, onValueChange = { vmIdentifier = it }, label = { Text("VM identifier") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = vmVsockPort, onValueChange = { vmVsockPort = it }, label = { Text("VSock port") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = vmNotes, onValueChange = { vmNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
            }

            if (type == MachineType.CONTAINER) {
                OutlinedTextField(value = containerSubtype, onValueChange = { containerSubtype = it }, label = { Text("Container subtype (docker/podman/lxc)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = containerRuntime, onValueChange = { containerRuntime = it }, label = { Text("Runtime") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = containerRef, onValueChange = { containerRef = it }, label = { Text("Container ref") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = containerEntry, onValueChange = { containerEntry = it }, label = { Text("Entry command") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = containerNotes, onValueChange = { containerNotes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
            }

            Spacer(Modifier.height(12.dp))
            Text(
                "Per-machine settings overrides",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                "These override global Wawona Settings only for this machine.",
                style = MaterialTheme.typography.bodySmall
            )

            OverrideBooleanDropdown(
                title = "Auto Scale",
                state = overrideAutoScale,
                onStateChange = { overrideAutoScale = it }
            )
            OverrideBooleanDropdown(
                title = "Respect Safe Area",
                state = overrideRespectSafeArea,
                onStateChange = { overrideRespectSafeArea = it }
            )
            OverrideBooleanDropdown(
                title = "Touchpad Mode",
                state = overrideTouchpadMode,
                onStateChange = { overrideTouchpadMode = it }
            )
            OverrideBooleanDropdown(
                title = "Enable Text Assist",
                state = overrideTextAssist,
                onStateChange = { overrideTextAssist = it }
            )
            OverrideBooleanDropdown(
                title = "Enable Dictation",
                state = overrideDictation,
                onStateChange = { overrideDictation = it }
            )
            OverrideStringDropdown(
                title = "Vulkan Driver",
                selected = overrideVulkanDriver,
                options = listOf(INHERIT_GLOBAL_OPTION, "None", "SwiftShader", "Turnip", "System"),
                onSelected = { overrideVulkanDriver = it }
            )
            OverrideStringDropdown(
                title = "OpenGL Driver",
                selected = overrideOpenGLDriver,
                options = listOf(INHERIT_GLOBAL_OPTION, "None", "ANGLE", "System"),
                onSelected = { overrideOpenGLDriver = it }
            )
            OverrideBooleanDropdown(
                title = "Enable DMABUF",
                state = overrideDmabufEnabled,
                onStateChange = { overrideDmabufEnabled = it }
            )
            OverrideBooleanDropdown(
                title = "Color Operations",
                state = overrideColorOperations,
                onStateChange = { overrideColorOperations = it }
            )
            OverrideBooleanDropdown(
                title = "Shake to Exit Machine",
                state = overrideShakeToClose,
                onStateChange = { overrideShakeToClose = it }
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(
                    onClick = {
                        val trimmedName = name.trim().ifEmpty { "Unnamed Machine" }
                        val base = initial ?: MachineProfile(
                            name = trimmedName,
                            type = type
                        )
                        val settingsOverrides = JSONObject(base.settingsOverrides.toString())
                        writeBooleanOverride(settingsOverrides, "autoScale", overrideAutoScale)
                        writeBooleanOverride(settingsOverrides, "respectSafeArea", overrideRespectSafeArea)
                        writeBooleanOverride(settingsOverrides, "touchpadMode", overrideTouchpadMode)
                        writeBooleanOverride(settingsOverrides, "enableTextAssist", overrideTextAssist)
                        writeBooleanOverride(settingsOverrides, "enableDictation", overrideDictation)
                        writeStringOverride(settingsOverrides, "vulkanDriver", overrideVulkanDriver)
                        writeStringOverride(settingsOverrides, "openglDriver", overrideOpenGLDriver)
                        writeBooleanOverride(settingsOverrides, "dmabufEnabled", overrideDmabufEnabled)
                        writeBooleanOverride(settingsOverrides, "colorOperations", overrideColorOperations)
                        writeBooleanOverride(settingsOverrides, "wawona.pref.shakeToCloseEnabled", overrideShakeToClose)
                        onSave(
                            base.copy(
                                name = trimmedName,
                                type = type,
                                sshHost = sshHost.trim(),
                                sshUser = sshUser.trim(),
                                sshPassword = sshPassword,
                                sshBinary = sshBinary.trim().ifEmpty { "ssh" },
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
                ) {
                    Text("Save")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OverrideBooleanDropdown(
    title: String,
    state: BooleanOverride,
    onStateChange: (BooleanOverride) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = state.label,
            onValueChange = {},
            readOnly = true,
            label = { Text(title) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            BooleanOverride.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.label) },
                    onClick = {
                        onStateChange(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OverrideStringDropdown(
    title: String,
    selected: String,
    options: List<String>,
    onSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(title) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelected(option)
                        expanded = false
                    }
                )
            }
        }
    }
}
