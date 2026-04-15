package com.aspauldingcode.wawona

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedAssistChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.unit.dp

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
    onOpenSession: (MachineSession) -> Unit
) {
    var editorProfile by remember { mutableStateOf<MachineProfile?>(null) }
    var creating by remember { mutableStateOf(false) }
    val snackbars = remember { SnackbarHostState() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Wawona Machines") },
                actions = {
                    TextButton(onClick = { creating = true }) {
                        Icon(Icons.Filled.Add, contentDescription = null)
                        Spacer(Modifier.size(6.dp))
                        Text("Add")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbars) }
    ) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 300.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
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
                    Card(modifier = Modifier.fillMaxWidth()) {
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
                            OutlinedButton(onClick = { onOpenSession(session) }) {
                                Text("Open")
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

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
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
                Button(onClick = onConnect, enabled = capabilities.launchSupported) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Spacer(Modifier.size(4.dp))
                    AnimatedContent(targetState = status, label = "connectStatus") { current ->
                        Text(if (current == MachineStatus.CONNECTING) "Connecting" else "Connect")
                    }
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
    MachineType.NATIVE -> "Native"
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
    var type by remember { mutableStateOf(initial?.type ?: MachineType.SSH_WAYPIPE) }
    var sshHost by remember { mutableStateOf(initial?.sshHost ?: "") }
    var sshUser by remember { mutableStateOf(initial?.sshUser ?: "") }
    var sshPassword by remember { mutableStateOf(initial?.sshPassword ?: "") }
    var sshBinary by remember { mutableStateOf(initial?.sshBinary ?: "ssh") }
    var sshAuthMethod by remember { mutableStateOf(initial?.sshAuthMethod ?: "password") }
    var sshKeyPath by remember { mutableStateOf(initial?.sshKeyPath ?: "") }
    var sshKeyPassphrase by remember { mutableStateOf(initial?.sshKeyPassphrase ?: "") }
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
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                MachineType.entries.forEach { candidate ->
                    ElevatedAssistChip(
                        onClick = { type = candidate },
                        label = { Text(candidate.value) }
                    )
                }
            }

            if (type == MachineType.SSH_WAYPIPE || type == MachineType.SSH_TERMINAL) {
                OutlinedTextField(value = sshHost, onValueChange = { sshHost = it }, label = { Text("SSH host") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshUser, onValueChange = { sshUser = it }, label = { Text("SSH user") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshPassword, onValueChange = { sshPassword = it }, label = { Text("SSH password") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshBinary, onValueChange = { sshBinary = it }, label = { Text("SSH binary") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshAuthMethod, onValueChange = { sshAuthMethod = it }, label = { Text("SSH auth method (password|key)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshKeyPath, onValueChange = { sshKeyPath = it }, label = { Text("SSH key path") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = sshKeyPassphrase, onValueChange = { sshKeyPassphrase = it }, label = { Text("SSH key passphrase") }, singleLine = true, modifier = Modifier.fillMaxWidth())
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

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(
                    onClick = {
                        val trimmedName = name.trim().ifEmpty { "Unnamed Machine" }
                        val base = initial ?: MachineProfile(
                            name = trimmedName,
                            type = type
                        )
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
                                remoteCommand = remoteCommand.trim(),
                                vmSubtype = vmSubtype.trim().ifEmpty { "qemu" },
                                containerSubtype = containerSubtype.trim().ifEmpty { "docker" },
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
