package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.content.ClipData
import android.content.ClipboardManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.NetworkInterface

private enum class SettingsTab(val label: String, val icon: ImageVector) {
    DISPLAY("Display", Icons.Filled.DesktopWindows),
    INPUT("Input", Icons.Filled.Keyboard),
    GRAPHICS("Graphics", Icons.Filled.GraphicEq),
    CONNECTION("Connection", Icons.Filled.Computer),
    ADVANCED("Advanced", Icons.Filled.Tune),
    WAYPIPE("Waypipe", Icons.Filled.Wifi),
    SSH("SSH", Icons.Filled.Lock),
    MACHINES("Machines", Icons.Filled.Storage),
    ABOUT("About", Icons.Filled.Info),
    DEPENDENCIES("Dependencies", Icons.Filled.Inventory)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDialog(
    prefs: SharedPreferences,
    onDismiss: () -> Unit,
    onApply: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val localIpAddress = remember { getLocalIpAddress(context) }
    var selectedTab by remember { mutableStateOf(SettingsTab.DISPLAY) }

    ModalBottomSheet(
        onDismissRequest = { onApply(); onDismiss() },
        sheetState = sheetState,
        modifier = Modifier.fillMaxHeight(0.92f),
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = {
            Box(
                Modifier
                    .padding(vertical = 12.dp)
                    .width(40.dp)
                    .height(4.dp)
                    .background(
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                        RoundedCornerShape(2.dp)
                    )
            )
        }
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight()
        ) {
            // Header
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Settings, null, Modifier.size(28.dp),
                    tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(12.dp))
                Text("Wawona Settings",
                    style = MaterialTheme.typography.headlineSmall.copy(
                        fontWeight = FontWeight.SemiBold, letterSpacing = (-0.01).sp),
                    color = MaterialTheme.colorScheme.onSurface)
            }

            // Section tabs
            ScrollableTabRow(
                selectedTabIndex = selectedTab.ordinal,
                modifier = Modifier.fillMaxWidth(),
                edgePadding = 16.dp,
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.primary,
                divider = {}
            ) {
                SettingsTab.entries.forEach { tab ->
                    Tab(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        text = { Text(tab.label, maxLines = 1) },
                        icon = { Icon(tab.icon, null, Modifier.size(18.dp)) }
                    )
                }
            }
            HorizontalDivider(Modifier.padding(top = 2.dp))

            // Tab content
            AnimatedContent(
                targetState = selectedTab,
                modifier = Modifier.weight(1f),
                transitionSpec = { fadeIn() togetherWith fadeOut() },
                label = "settings_tab"
            ) { tab ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .padding(bottom = 32.dp)
                ) {
                    when (tab) {
                        SettingsTab.DISPLAY -> DisplaySection(prefs)
                        SettingsTab.INPUT -> InputSection(prefs)
                        SettingsTab.GRAPHICS -> GraphicsSection(prefs)
                        SettingsTab.CONNECTION -> ConnectionSection(prefs, localIpAddress, context)
                        SettingsTab.ADVANCED -> AdvancedSection(prefs)
                        SettingsTab.WAYPIPE -> WaypipeSection(prefs, context)
                        SettingsTab.SSH -> SSHSection(prefs)
                        SettingsTab.MACHINES -> MachineStubsSection(prefs)
                        SettingsTab.ABOUT -> AboutSection(context)
                        SettingsTab.DEPENDENCIES -> DependenciesSection()
                    }
                }
            }
        }
    }
}

@Composable
private fun MachineStubsSection(prefs: SharedPreferences) {
    SettingsSectionHeader("Virtual Machines", Icons.Filled.Storage)
    SettingsTextInputItem(
        prefs, "machineVmProviderStub", "VM Provider",
        "Provider identifier for future VM integration", Icons.Filled.Storage,
        "utm-se", KeyboardType.Text
    )
    SettingsTextInputItem(
        prefs, "machineVmDefaultVsockStub", "Default VSock Port",
        "Saved for future VM launch support", Icons.Filled.Tune,
        "1024", KeyboardType.Number
    )
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
    ) {
        Text(
            "VM launch is a v0.2.3 stub. Future support will come from Wawona's UTM SE fork.",
            Modifier.padding(12.dp),
            style = MaterialTheme.typography.bodySmall
        )
    }

    Spacer(Modifier.height(12.dp))

    SettingsSectionHeader("Containers", Icons.Filled.Inventory2)
    SettingsTextInputItem(
        prefs, "machineContainerRuntimeStub", "Container Runtime",
        "Default runtime for future container integration", Icons.Filled.Inventory2,
        "docker", KeyboardType.Text
    )
    SettingsTextInputItem(
        prefs, "machineContainerNamespaceStub", "Container Namespace",
        "Saved stub value for upcoming runtime hooks", Icons.Filled.AccountTree,
        "default", KeyboardType.Text
    )
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
    ) {
        Text(
            "Container launch is a v0.2.3 stub and intentionally non-functional right now.",
            Modifier.padding(12.dp),
            style = MaterialTheme.typography.bodySmall
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section composables
// ═══════════════════════════════════════════════════════════════════════════

@Composable
private fun DisplaySection(prefs: SharedPreferences) {
    LockedSwitchItem("Force Server-Side Decorations",
        "Compositor-drawn window borders (always enabled)", Icons.Filled.BorderOuter,
        alertTitle = "Force Server-Side Decorations",
        alertMessage = "Android does not support Client-Side Decoration (CSD). " +
            "Window decorations must be drawn by the compositor, so Force " +
            "Server-Side Decorations is always enabled.")
    SettingsSwitchItem(prefs, "autoScale", "Auto Scale",
        "Detect and match Android UI scaling", Icons.Filled.AspectRatio, default = true)
    SettingsSwitchItem(prefs, "respectSafeArea", "Respect Safe Area",
        "Avoid system UI and notches", Icons.Filled.Security, default = true)
}

@Composable
private fun GraphicsSection(prefs: SharedPreferences) {
    SettingsSectionHeader("Drivers", Icons.Filled.Speed)
    SettingsDropdownItem(prefs, "vulkanDriver", "Vulkan Driver",
        "Select Vulkan implementation. None disables Vulkan.", Icons.Filled.Speed, "None",
        listOf("None", "SwiftShader", "Turnip", "System"))
    SettingsDropdownItem(prefs, "openglDriver", "OpenGL Driver",
        "Select OpenGL/GLES implementation. None disables OpenGL.", Icons.Filled.GraphicEq, "None",
        listOf("None", "ANGLE", "System"))
    SettingsSectionHeader("Features", Icons.Filled.Tune)
    SettingsSwitchItem(prefs, "dmabufEnabled", "DmaBuf Support",
        "Enable DMA buffer sharing between clients", Icons.Filled.Share, default = true)
}

@Composable
private fun AdvancedSection(prefs: SharedPreferences) {
    SettingsSwitchItem(prefs, "colorOperations", "Color Operations",
        "Enable color profiles, HDR requests, etc.", Icons.Filled.Palette, default = true)
    SettingsSwitchItem(prefs, "nestedCompositorsSupport", "Nested Compositors",
        "Support nested Wayland compositors", Icons.Filled.Layers, default = true)
    SettingsSwitchItem(prefs, "multipleClients", "Multiple Clients",
        "Allow multiple Wayland clients", Icons.Filled.Group, default = false)
    SettingsSwitchItem(prefs, "enableLauncher", "Enable Launcher",
        "Show built-in application launcher", Icons.Filled.Apps, default = false)
    SettingsSwitchItem(prefs, "westonSimpleSHMEnabled", "Enable Weston Simple SHM",
        "Start weston-simple-shm on launch", Icons.Filled.PlayArrow, default = false)
    SettingsSwitchItem(prefs, "westonEnabled", "Enable Native Weston",
        "Start native weston compositor", Icons.Filled.Monitor, default = false)
    SettingsSwitchItem(prefs, "westonTerminalEnabled", "Enable Weston Terminal",
        "Start native weston-terminal client", Icons.Filled.Terminal, default = false)
}

@Composable
private fun InputSection(prefs: SharedPreferences) {
    SettingsSwitchItem(prefs, "touchpadMode", "Touchpad Mode",
        "1-finger = pointer, tap = click, 2-finger drag = scroll. When off, use direct touch (multi-touch)",
        Icons.Filled.TouchApp, default = false)
    SettingsSwitchItem(prefs, "enableTextAssist", "Enable Text Assist",
        "Autocorrect, text suggestions, smart punctuation, swipe-to-type, and text replacements via the native keyboard",
        Icons.Filled.Spellcheck, default = false)
    SettingsSwitchItem(prefs, "enableDictation", "Enable Dictation",
        "Voice dictation input. Spoken text is transcribed and sent to the focused Wayland client",
        Icons.Filled.Mic, default = false)
}

@Composable
private fun ConnectionSection(prefs: SharedPreferences, localIp: String?, context: Context) {
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
    ) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Info, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text("Local IP Address",
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface)
                Spacer(Modifier.height(4.dp))
                Text(localIp ?: "Not available",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontFamily = FontFamily.Monospace)
            }
        }
    }

    SettingsTextInputItem(prefs, "waypipeDisplay", "Wayland Display",
        "Display socket name (e.g., wayland-0)", Icons.Filled.DesktopWindows,
        "wayland-0", KeyboardType.Text, revertToDefaultOnEmpty = true)

    val androidSocketPath = remember { "${context.cacheDir.absolutePath}/waypipe" }
    SettingsTextInputItem(prefs, "waypipeSocket", "Socket Path",
        "Unix socket path (set by platform)", Icons.Filled.Folder,
        androidSocketPath, KeyboardType.Text, readOnly = true)
}

@Composable
private fun WaypipeSection(prefs: SharedPreferences, context: Context) {
    SettingsInfoRow(
        title = "Waypipe",
        value = "v0.10.6",
        description = "Remote Wayland display proxy",
        icon = Icons.Filled.Wifi
    )

    SettingsDropdownItem(prefs, "waypipeCompress", "Compression",
        "Compression method for data transfers", Icons.Filled.Archive, "lz4",
        listOf("none", "lz4", "zstd"))

    val compress = remember { mutableStateOf(prefs.getString("waypipeCompress", "lz4") ?: "lz4") }
    LaunchedEffect(prefs.getString("waypipeCompress", "lz4")) {
        compress.value = prefs.getString("waypipeCompress", "lz4") ?: "lz4"
    }
    if (compress.value == "zstd" || compress.value.startsWith("zstd=")) {
        SettingsTextInputItem(prefs, "waypipeCompressLevel", "Compression Level",
            "Zstd compression level (1-22)", Icons.Filled.Tune, "7", KeyboardType.Number)
    }

    SettingsTextInputItem(prefs, "waypipeThreads", "Threads",
        "Number of threads (0 = auto)", Icons.Filled.Memory, "0",
        KeyboardType.Number, revertToDefaultOnEmpty = true)

    SettingsDropdownItem(prefs, "waypipeVideo", "Video Compression",
        "DMABUF video compression codec", Icons.Filled.VideoCall, "none",
        listOf("none", "h264", "vp9", "av1"))

    val videoCodec = remember { mutableStateOf(prefs.getString("waypipeVideo", "none") ?: "none") }
    LaunchedEffect(prefs.getString("waypipeVideo", "none")) {
        videoCodec.value = prefs.getString("waypipeVideo", "none") ?: "none"
    }
    if (videoCodec.value != "none") {
        SettingsDropdownItem(prefs, "waypipeVideoEncoding", "Video Encoding",
            "Hardware or software encoding", Icons.Filled.Settings, "hw",
            listOf("hw", "sw", "hwenc", "swenc"))
        SettingsDropdownItem(prefs, "waypipeVideoDecoding", "Video Decoding",
            "Hardware or software decoding", Icons.Filled.Settings, "hw",
            listOf("hw", "sw", "hwdec", "swdec"))
        LaunchedEffect(Unit) {
            val v = prefs.getString("waypipeVideoBpf", "")
            if (v != null && v.contains(".") && v.matches(Regex("^\\d+\\.\\d+.*")))
                prefs.edit().putString("waypipeVideoBpf", "").apply()
        }
        SettingsTextInputItem(prefs, "waypipeVideoBpf", "Bits Per Frame",
            "Target bit rate (e.g., 750000)", Icons.Filled.Speed, "", KeyboardType.Number)
    }

    // Remote execution (belongs in Waypipe since it's what runs on the remote end)
    SettingsSectionHeader("Remote Execution", Icons.Filled.PlayArrow)
    SettingsTextInputItem(prefs, "waypipeRemoteCommand", "Remote Command",
        "Application to run remotely (e.g., weston-terminal)", Icons.Filled.PlayArrow, "", KeyboardType.Text)
    SettingsMultiLineTextInputItem(prefs, "waypipeCustomScript", "Custom Script",
        "Full command line script (overrides Remote Command)", Icons.Filled.Code, "")

    Spacer(Modifier.height(8.dp))

    // Waypipe & SSH Logs
    var showLogsDialog by remember { mutableStateOf(false) }
    Surface(
        onClick = { showLogsDialog = true },
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(Modifier.padding(vertical = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Description, null, Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.secondary)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text("Waypipe & SSH Logs", style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface)
                Text("View and copy Waypipe/Dropbear output",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.Filled.ChevronRight, "Open", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (showLogsDialog) {
        WaypipeLogsDialog(
            logPath = File(context.cacheDir, "wawona-runtime/waypipe-stderr.log").absolutePath,
            onDismiss = { showLogsDialog = false }
        )
    }

    Spacer(Modifier.height(8.dp))

    // Advanced Waypipe Options
    var showAdvanced by remember { mutableStateOf(false) }
    Surface(
        onClick = { showAdvanced = true },
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(Modifier.padding(vertical = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.SettingsSuggest, null, Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.secondary)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text("Advanced Waypipe Options", style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface)
                Text("Debug, GPU, login shell, title prefix, security context",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.Filled.ChevronRight, "Open", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (showAdvanced) {
        AdvancedWaypipeDialog(prefs) { showAdvanced = false }
    }
}

@Composable
private fun SSHSection(prefs: SharedPreferences) {
    SettingsSwitchItem(prefs, "waypipeSSHEnabled", "Enable SSH",
        "Use SSH transport for waypipe connections", Icons.Filled.Lock, default = true)

    SettingsInfoRow(
        title = "SSH Library",
        value = "v2025.89",
        description = "Dropbear SSH client used for connections",
        icon = Icons.Filled.Lock
    )

    val sshEnabled = remember { mutableStateOf(prefs.getBoolean("waypipeSSHEnabled", true)) }
    LaunchedEffect(prefs.getBoolean("waypipeSSHEnabled", true)) {
        sshEnabled.value = prefs.getBoolean("waypipeSSHEnabled", true)
    }

    if (!sshEnabled.value) {
        Surface(
            Modifier.fillMaxWidth().padding(vertical = 8.dp),
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
        ) {
            Text("Enable SSH to configure connection settings.",
                Modifier.padding(24.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }

    // Connection settings
    SettingsSectionHeader("Connection", Icons.Filled.Computer)
    SettingsTextInputItem(prefs, "waypipeSSHHost", "SSH Host",
        "IP or hostname (use IP on Android; SSH config aliases like \"ssh\" don't resolve)",
        Icons.Filled.Computer, "", KeyboardType.Text)
    SettingsTextInputItem(prefs, "waypipeSSHUser", "SSH User",
        "SSH username", Icons.Filled.Person, "", KeyboardType.Text)

    // Auth method
    SettingsSectionHeader("Authentication", Icons.Filled.VpnKey)
    SettingsDropdownItem(prefs, "sshAuthMethod", "Auth Method",
        "How to authenticate with the remote host", Icons.Filled.VpnKey, "password",
        listOf("password", "publickey"))

    val authMethod = remember { mutableStateOf(prefs.getString("sshAuthMethod", "password") ?: "password") }
    LaunchedEffect(prefs.getString("sshAuthMethod", "password")) {
        authMethod.value = prefs.getString("sshAuthMethod", "password") ?: "password"
    }

    if (authMethod.value == "password") {
        SettingsPasswordInputItem(prefs, "waypipeSSHPassword", "SSH Password",
            "Password for SSH authentication", Icons.Filled.Password, "")
    } else {
        SettingsTextInputItem(prefs, "sshKeyPath", "Private Key Path",
            "Path to SSH private key (e.g., /sdcard/.ssh/id_ed25519)", Icons.Filled.Key,
            "", KeyboardType.Text)
        SettingsTextInputItem(prefs, "sshKeyPassphrase", "Key Passphrase",
            "Passphrase for encrypted private key (leave empty if none)", Icons.Filled.Password,
            "", KeyboardType.Password)
    }

    Spacer(Modifier.height(12.dp))

    // Test buttons -- read prefs FRESH at click time (not cached at composition)
    SettingsSectionHeader("Diagnostics", Icons.Filled.NetworkCheck)
    val scope = rememberCoroutineScope()
    var pingResult by remember { mutableStateOf<String?>(null) }
    var sshResult by remember { mutableStateOf<String?>(null) }
    var isPinging by remember { mutableStateOf(false) }
    var isSshTesting by remember { mutableStateOf(false) }

    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(
            onClick = {
                val host = prefs.getString("waypipeSSHHost", "") ?: ""
                if (host.isBlank()) { pingResult = "FAIL: SSH Host is empty"; return@OutlinedButton }
                isPinging = true; pingResult = null
                scope.launch {
                    pingResult = withContext(Dispatchers.IO) {
                        try { WawonaNative.nativeTestPing(host, 22, 5000) }
                        catch (e: Exception) { "FAIL: ${e.message}" }
                    }
                    isPinging = false
                }
            },
            modifier = Modifier.weight(1f),
            enabled = !isPinging,
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(Icons.Filled.NetworkPing, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (isPinging) "Pinging..." else "Test Ping")
        }

        OutlinedButton(
            onClick = {
                val host = prefs.getString("waypipeSSHHost", "") ?: ""
                val user = prefs.getString("waypipeSSHUser", "") ?: ""
                val pass = prefs.getString("waypipeSSHPassword", "") ?: ""
                if (host.isBlank()) { sshResult = "FAIL: SSH Host is empty"; return@OutlinedButton }
                if (user.isBlank()) { sshResult = "FAIL: SSH User is empty"; return@OutlinedButton }
                isSshTesting = true; sshResult = null
                scope.launch {
                    sshResult = withContext(Dispatchers.IO) {
                        try { WawonaNative.nativeTestSSH(host, user, pass, 22) }
                        catch (e: Exception) { "FAIL: ${e.message}" }
                    }
                    isSshTesting = false
                }
            },
            modifier = Modifier.weight(1f),
            enabled = !isSshTesting,
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(Icons.Filled.Wifi, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (isSshTesting) "Testing..." else "Test SSH")
        }
    }

    val ctx = LocalContext.current
    pingResult?.let { TestResultCard(it, ctx) }
    sshResult?.let { TestResultCard(it, ctx) }
}

@Composable
private fun AboutSection(context: Context) {
    val uriHandler = LocalUriHandler.current
    val version = try {
        val pkg = context.packageManager.getPackageInfo(context.packageName, 0)
        val v = pkg.versionName ?: "1.0"
        if (v.startsWith("v")) v else "v$v"
    } catch (_: Exception) { "v1.0" }

    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(24.dp))
        Image(
            painter = painterResource(com.aspauldingcode.wawona.R.drawable.ic_launcher_foreground),
            contentDescription = null,
            Modifier.size(100.dp)
        )
        Spacer(Modifier.height(16.dp))
        Text("Wawona",
            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold),
            color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(4.dp))
        Text("Version $version",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        Text("Alex Spaulding",
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(16.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedButton(
                onClick = { uriHandler.openUri("https://ko-fi.com/aspauldingcode") },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp)
            ) { Text("Ko-fi") }
            OutlinedButton(
                onClick = { uriHandler.openUri("https://github.com/sponsors/aspauldingcode") },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp)
            ) { Text("GitHub Sponsors") }
        }
        Spacer(Modifier.height(12.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(
                onClick = { uriHandler.openUri("https://github.com/aspauldingcode") }
            ) { Text("GitHub") }
            TextButton(
                onClick = { uriHandler.openUri("https://www.linkedin.com/in/aspauldingcode/") }
            ) { Text("LinkedIn") }
        }
        Spacer(Modifier.height(32.dp))
    }
}

@Composable
private fun DependenciesSection() {
    AboutDependencyRow("Waypipe", "v0.10.6", "Remote Wayland display proxy")
    AboutDependencyRow("libwayland", "v1.23", "Wayland protocol library")
    AboutDependencyRow("xkbcommon", "v1.7.0", "Keyboard handling library")
    AboutDependencyRow("LZ4", "v1.9", "Fast compression algorithm")
    AboutDependencyRow("Zstd", "v1.5", "Zstandard compression")
    AboutDependencyRow("libffi", "v3.4", "Foreign function interface")
    AboutDependencyRow("SwiftShader", "v2024", "Vulkan software renderer")
    AboutDependencyRow("Dropbear", "v2025.89", "SSH client for Android")
    AboutDependencyRow("OpenSSL", "v3.4", "Cryptography library")
}

@Composable
private fun AboutDependencyRow(name: String, version: String, description: String) {
    SettingsInfoRow(
        title = name,
        value = version,
        description = description,
        icon = Icons.Filled.Inventory2
    )
}

@Composable
private fun SettingsInfoRow(title: String, value: String, description: String, icon: ImageVector) {
    val displayVersion = if (value.startsWith("v")) value else "v$value"
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, null, Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface)
                Text(description, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(displayVersion, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.primary)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Waypipe Logs Dialog
// ═══════════════════════════════════════════════════════════════════════════

@Composable
private fun WaypipeLogsDialog(logPath: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    var logContent by remember { mutableStateOf("Loading...") }
    var refreshTrigger by remember { mutableStateOf(0) }
    LaunchedEffect(logPath, refreshTrigger) {
        logContent = withContext(Dispatchers.IO) {
            try {
                File(logPath).readText().ifEmpty { "(No logs yet. Start a machine session to generate output.)" }
            } catch (_: Exception) {
                "(Log file not found or empty. Start a machine session to generate output.)"
            }
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Waypipe & SSH Logs") },
        text = {
            Column {
                Text("Path: $logPath",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Logs appear when Waypipe runs. Tap Refresh to reload.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Surface(
                    Modifier.fillMaxWidth().heightIn(max = 300.dp),
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                ) {
                    Column(
                        Modifier.fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(12.dp)
                    ) {
                        Text(logContent,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace)
                    }
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { refreshTrigger++ }) {
                    Icon(Icons.Filled.Refresh, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Refresh")
                }
                Button(onClick = onDismiss) { Text("Close") }
            }
        },
        dismissButton = {
            TextButton(onClick = {
                clipboardManager.setPrimaryClip(ClipData.newPlainText("Waypipe Logs", logContent))
            }) {
                Icon(Icons.Filled.ContentCopy, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Copy to clipboard")
            }
        }
    )
}

// ═══════════════════════════════════════════════════════════════════════════
// Result card
// ═══════════════════════════════════════════════════════════════════════════

@Composable
fun TestResultCard(result: String, context: Context) {
    val isOk = result.startsWith("OK")
    val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp),
        color = if (isOk) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
        else MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            Text(result, Modifier.weight(1f),
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = if (isOk) MaterialTheme.colorScheme.onPrimaryContainer
                else MaterialTheme.colorScheme.onErrorContainer)
            IconButton(
                onClick = {
                    clipboardManager.setPrimaryClip(ClipData.newPlainText("SSH Test Result", result))
                },
                modifier = Modifier.size(36.dp)
            ) {
                Icon(Icons.Filled.ContentCopy, contentDescription = "Copy to clipboard",
                    tint = if (isOk) MaterialTheme.colorScheme.onPrimaryContainer
                    else MaterialTheme.colorScheme.onErrorContainer)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable composables
// ═══════════════════════════════════════════════════════════════════════════

@Composable
fun SettingsSectionHeader(title: String, icon: ImageVector) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(8.dp))
        Text(title,
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.SemiBold, letterSpacing = (-0.01).sp),
            color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
fun LockedSwitchItem(
    title: String, description: String, icon: ImageVector,
    alertTitle: String, alertMessage: String
) {
    var showDialog by remember { mutableStateOf(false) }
    Surface(
        onClick = { showDialog = true },
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    Spacer(Modifier.height(4.dp))
                    Text(description, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                }
            }
            Spacer(Modifier.width(16.dp))
            Switch(checked = true, onCheckedChange = { showDialog = true }, enabled = false,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = MaterialTheme.colorScheme.primary,
                    checkedTrackColor = MaterialTheme.colorScheme.primaryContainer
                ))
        }
    }
    if (showDialog) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(alertTitle) },
            text = { Text(alertMessage) },
            confirmButton = {
                TextButton(onClick = { showDialog = false }) { Text("OK") }
            }
        )
    }
}

@Composable
fun SettingsSwitchItem(
    prefs: SharedPreferences, key: String, title: String, description: String,
    icon: ImageVector, default: Boolean, enabled: Boolean = true
) {
    var checked by remember { mutableStateOf(prefs.getBoolean(key, default)) }
    LaunchedEffect(key) {
        if (enabled) checked = prefs.getBoolean(key, default)
        else { checked = default; prefs.edit().putBoolean(key, default).apply() }
    }
    Surface(
        onClick = { if (enabled) { checked = !checked; prefs.edit().putBoolean(key, checked).apply() } },
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (enabled) 0.4f else 0.2f)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 0.8f else 0.4f))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.6f))
                    Spacer(Modifier.height(4.dp))
                    Text(description, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (enabled) 1f else 0.6f))
                }
            }
            Spacer(Modifier.width(16.dp))
            Switch(checked = checked, onCheckedChange = {
                if (enabled) { checked = it; prefs.edit().putBoolean(key, it).apply() }
            }, enabled = enabled, colors = SwitchDefaults.colors(
                checkedThumbColor = MaterialTheme.colorScheme.primary,
                checkedTrackColor = MaterialTheme.colorScheme.primaryContainer,
                uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant,
                uncheckedTrackColor = MaterialTheme.colorScheme.surfaceVariant
            ))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsTextInputItem(
    prefs: SharedPreferences, key: String, title: String, description: String,
    icon: ImageVector, default: String, keyboardType: KeyboardType,
    revertToDefaultOnEmpty: Boolean = false, readOnly: Boolean = false
) {
    var text by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    LaunchedEffect(key) {
        if (!readOnly) text = prefs.getString(key, default) ?: default
        else { text = default; prefs.edit().putString(key, default).apply() }
    }
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(4.dp))
                    Text(description, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = text,
                onValueChange = { nv ->
                    if (!readOnly) {
                        val fv = if (revertToDefaultOnEmpty && nv.isEmpty()) default else nv
                        text = fv; prefs.edit().putString(key, fv).apply()
                    }
                },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
                readOnly = readOnly, enabled = !readOnly,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    disabledTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    disabledBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
                ),
                shape = RoundedCornerShape(12.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsPasswordInputItem(
    prefs: SharedPreferences, key: String, title: String, description: String,
    icon: ImageVector, default: String
) {
    var text by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(key) { text = prefs.getString(key, default) ?: default }
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(4.dp))
                    Text(description, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = text,
                onValueChange = { text = it; prefs.edit().putString(key, it).apply() },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
                visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    IconButton(onClick = { visible = !visible }) {
                        Icon(if (visible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                            "Toggle visibility")
                    }
                },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline
                ),
                shape = RoundedCornerShape(12.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsMultiLineTextInputItem(
    prefs: SharedPreferences, key: String, title: String, description: String,
    icon: ImageVector, default: String
) {
    var text by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    LaunchedEffect(key) { text = prefs.getString(key, default) ?: default }
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(4.dp))
                    Text(description, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = text,
                onValueChange = { text = it; prefs.edit().putString(key, it).apply() },
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                maxLines = 10, minLines = 4,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline
                ),
                shape = RoundedCornerShape(12.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDropdownItem(
    prefs: SharedPreferences, key: String, title: String, description: String,
    icon: ImageVector, default: String, options: List<String>
) {
    var expanded by remember { mutableStateOf(false) }
    var selectedOption by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    LaunchedEffect(key) { selectedOption = prefs.getString(key, default) ?: default }
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(4.dp))
                    Text(description, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(12.dp))
            Box {
                ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = !expanded }) {
                    OutlinedTextField(
                        value = selectedOption, onValueChange = {}, readOnly = true,
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.colorScheme.primary,
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                    ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        options.forEach { option ->
                            DropdownMenuItem(text = { Text(option) }, onClick = {
                                selectedOption = option
                                prefs.edit().putString(key, option).apply()
                                expanded = false
                            })
                        }
                    }
                }
            }
        }
    }
}

fun getLocalIpAddress(context: Context): String? {
    try {
        val interfaces = NetworkInterface.getNetworkInterfaces()
        while (interfaces.hasMoreElements()) {
            val ni = interfaces.nextElement()
            val addrs = ni.inetAddresses
            while (addrs.hasMoreElements()) {
                val addr = addrs.nextElement()
                if (!addr.isLoopbackAddress && addr.hostAddress?.contains(":") == false)
                    return addr.hostAddress
            }
        }
    } catch (_: Exception) {}
    return null
}

@Composable
fun AdvancedWaypipeDialog(prefs: SharedPreferences, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Advanced Waypipe Options") },
        text = {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
                SettingsSwitchItem(prefs, "waypipeDebug", "Debug Mode",
                    "Enable verbose logging", Icons.Filled.BugReport, default = false)
                SettingsSwitchItem(prefs, "waypipeDisableGpu", "Disable GPU",
                    "Force software rendering", Icons.Filled.Memory, default = false)
                SettingsSwitchItem(prefs, "waypipeOneshot", "One-Shot",
                    "Exit after first client disconnects", Icons.Filled.ExitToApp, default = false)
                SettingsSwitchItem(prefs, "waypipeLoginShell", "Login Shell",
                    "Use login shell on remote host", Icons.Filled.Terminal, default = false)
                SettingsSwitchItem(prefs, "waypipeSleepOnExit", "Sleep on Exit",
                    "Keep socket open after exit", Icons.Filled.Timer, default = false)
                SettingsSwitchItem(prefs, "waypipeUnlinkOnExit", "Unlink on Exit",
                    "Remove socket file on exit", Icons.Filled.Delete, default = true)

                Spacer(Modifier.height(8.dp))

                SettingsTextInputItem(prefs, "waypipeTitlePrefix", "Title Prefix",
                    "Window title prefix (e.g., Remote:)", Icons.Filled.Label, "", KeyboardType.Text)
                SettingsTextInputItem(prefs, "waypipeSecCtx", "Security Context",
                    "Wayland security context string", Icons.Filled.Shield, "", KeyboardType.Text)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } }
    )
}
