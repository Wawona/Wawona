package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import com.aspauldingcode.wawona.anowaw.AnowawPowerController
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.IconButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import android.widget.ImageView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.content.ClipData
import android.content.ClipboardManager
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.NetworkInterface
import androidx.compose.animation.togetherWith

private enum class SettingsTab(val label: String, val icon: ImageVector, val testTag: String) {
    DISPLAY("Display", Icons.Filled.DesktopWindows, WawonaTestTags.SETTINGS_DISPLAY),
    INPUT("Input", Icons.Filled.Keyboard, WawonaTestTags.SETTINGS_INPUT),
    GRAPHICS("Graphics", Icons.Filled.GraphicEq, WawonaTestTags.SETTINGS_GRAPHICS),
    CONNECTION("Connection", Icons.Filled.Computer, WawonaTestTags.SETTINGS_CONNECTION),
    ENVIRONMENT("Env Vars", Icons.Filled.List, WawonaTestTags.SETTINGS_ENVIRONMENT),
    LOCAL_SHELL("Local Shell", Icons.Filled.Folder, WawonaTestTags.SETTINGS_LOCAL_SHELL),
    DESKTOP("Desktop", Icons.Filled.DesktopMac, WawonaTestTags.SETTINGS_DESKTOP),
    ADVANCED("Advanced", Icons.Filled.Tune, WawonaTestTags.SETTINGS_ADVANCED),
    WAYPIPE("Waypipe", Icons.Filled.Wifi, WawonaTestTags.SETTINGS_WAYPIPE),
    SSH("SSH", Icons.Filled.Lock, WawonaTestTags.SETTINGS_SSH),
    MACHINES("Machines", Icons.Filled.Storage, WawonaTestTags.SETTINGS_MACHINES),
    ABOUT("About", Icons.Filled.Info, WawonaTestTags.SETTINGS_ABOUT),
    DEPENDENCIES("Dependencies", Icons.Filled.Inventory, WawonaTestTags.SETTINGS_DEPENDENCIES);

    val accentColor: Color
        get() = when (this) {
            DISPLAY -> Color(0xFF4285F4)
            INPUT -> Color(0xFF34A853)
            GRAPHICS -> Color(0xFFEA4335)
            CONNECTION -> Color(0xFFFBBC04)
            ENVIRONMENT -> Color(0xFF00BFA5)
            LOCAL_SHELL -> Color(0xFF188038)
            DESKTOP -> Color(0xFF00ACC1)
            ADVANCED -> Color(0xFF9AA0A6)
            WAYPIPE -> Color(0xFF1A73E8)
            SSH -> Color(0xFF5F6368)
            MACHINES -> Color(0xFF9334E6)
            ABOUT -> Color(0xFF188038)
            DEPENDENCIES -> Color(0xFF1967D2)
        }
}

private data class SettingsChoiceSpec(
    val key: String,
    val title: String,
    val options: List<String>,
    val optionLabels: Map<String, String> = emptyMap(),
    val default: String,
    val persist: ((SharedPreferences, String) -> Unit)? = null,
)

private val LocalOpenSettingsChoice = staticCompositionLocalOf<(SettingsChoiceSpec) -> Unit> {
    {}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDialog(
    prefs: SharedPreferences,
    onDismiss: () -> Unit,
    onApply: () -> Unit
) {
    val context = LocalContext.current
    val localIpAddress = remember { getLocalIpAddress(context) }
    val configuration = LocalConfiguration.current
    val isWide = configuration.screenWidthDp >= 600
    var selectedTab by remember { mutableStateOf(SettingsTab.DISPLAY) }
    var narrowDetailTab by remember { mutableStateOf<SettingsTab?>(null) }
    var choicePage by remember { mutableStateOf<SettingsChoiceSpec?>(null) }

    WawonaModalSheet(
        onDismiss = { onApply(); onDismiss() },
        title = choicePage?.title ?: "Wawona Settings",
        defaultDetent = WawonaSheetDetent.Large,
        scrollBehavior = WawonaSheetScrollBehavior.ExpandWithContent,
        navigationIcon = {
            if (choicePage != null) {
                IconButton(onClick = { choicePage = null }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            } else if (!isWide && narrowDetailTab != null) {
                IconButton(onClick = { narrowDetailTab = null }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        },
        actions = {
            TextButton(
                onClick = { onApply(); onDismiss() },
                modifier = Modifier.testTag(WawonaTestTags.SETTINGS_DONE),
            ) {
                Text("Done")
            }
        },
    ) { _ ->
        CompositionLocalProvider(LocalOpenSettingsChoice provides { spec -> choicePage = spec }) {
            if (choicePage != null) {
                SettingsChoiceList(
                    spec = choicePage!!,
                    prefs = prefs,
                    onPicked = { choicePage = null },
                )
            } else if (isWide) {
            Row(Modifier.fillMaxSize().testTag(WawonaTestTags.SETTINGS_ROOT)) {
                SettingsSidebarList(
                    selected = selectedTab,
                    onSelect = { selectedTab = it; choicePage = null },
                    modifier = Modifier.width(220.dp),
                )
                VerticalDivider()
                SettingsSectionContent(
                    tab = selectedTab,
                    prefs = prefs,
                    context = context,
                    localIpAddress = localIpAddress,
                    modifier = Modifier.weight(1f),
                )
            }
        } else {
            androidx.compose.animation.AnimatedContent(
                targetState = narrowDetailTab,
                transitionSpec = {
                    if (targetState != null) {
                        (androidx.compose.animation.slideInHorizontally { width -> width } + androidx.compose.animation.fadeIn()).togetherWith(
                                androidx.compose.animation.slideOutHorizontally { width -> -width } + androidx.compose.animation.fadeOut())
                    } else {
                        (androidx.compose.animation.slideInHorizontally { width -> -width } + androidx.compose.animation.fadeIn()).togetherWith(
                                androidx.compose.animation.slideOutHorizontally { width -> width } + androidx.compose.animation.fadeOut())
                    }
                },
                label = "SettingsNavigation",
                modifier = Modifier.testTag(WawonaTestTags.SETTINGS_ROOT)
            ) { currentTab ->
                if (currentTab == null) {
                    SettingsSidebarList(
                        selected = null,
                        onSelect = { narrowDetailTab = it },
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    SettingsSectionContent(
                        tab = currentTab,
                        prefs = prefs,
                        context = context,
                        localIpAddress = localIpAddress,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
        }
    }
}

@Composable
private fun SettingsSidebarList(
    selected: SettingsTab?,
    onSelect: (SettingsTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(vertical = 8.dp)
            .testTag(WawonaTestTags.SETTINGS_ROOT),
    ) {
        SettingsTab.entries.forEach { tab ->
            val isSelected = selected == tab
            Surface(
                onClick = { onSelect(tab) },
                color = if (isSelected) {
                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f)
                } else {
                    MaterialTheme.colorScheme.surfaceContainerLow
                },
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 2.dp)
                    .testTag(tab.testTag)
                    .border(
                        width = 1.dp,
                        color = if (isSelected) {
                            tab.accentColor.copy(alpha = 0.45f)
                        } else {
                            MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.28f)
                        },
                        shape = RoundedCornerShape(12.dp),
                    ),
            ) {
                Row(
                    Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        tab.icon,
                        contentDescription = tab.label,
                        modifier = Modifier.size(20.dp),
                        tint = tab.accentColor,
                    )
                    Spacer(Modifier.width(12.dp))
                    Text(tab.label, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@Composable
private fun SettingsSectionContent(
    tab: SettingsTab,
    prefs: SharedPreferences,
    context: Context,
    localIpAddress: String?,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxSize()
            .testTag(tab.testTag)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .padding(bottom = 24.dp),
    ) {
        when (tab) {
            SettingsTab.DISPLAY -> DisplaySection(prefs)
            SettingsTab.INPUT -> InputSection(prefs)
            SettingsTab.GRAPHICS -> GraphicsSection(prefs)
            SettingsTab.CONNECTION -> ConnectionSection(prefs, localIpAddress, context, SettingsTab.CONNECTION.accentColor)
            SettingsTab.ENVIRONMENT -> EnvironmentSection(prefs, SettingsTab.ENVIRONMENT.accentColor)
            SettingsTab.LOCAL_SHELL -> LocalShellSection(context, SettingsTab.LOCAL_SHELL.accentColor)
            SettingsTab.DESKTOP -> {
                DesktopSection(prefs, context, SettingsTab.DESKTOP.accentColor)
                LockscreenSection(prefs, SettingsTab.DESKTOP.accentColor)
            }
            SettingsTab.ADVANCED -> AdvancedSection(prefs)
            SettingsTab.WAYPIPE -> WaypipeSection(prefs, context, SettingsTab.WAYPIPE.accentColor)
            SettingsTab.SSH -> SSHSection(prefs, SettingsTab.SSH.accentColor)
            SettingsTab.MACHINES -> MachineStubsSection(prefs, SettingsTab.MACHINES.accentColor)
            SettingsTab.ABOUT -> AboutSection(context)
            SettingsTab.DEPENDENCIES -> DependenciesSection()
        }
    }
}

@Composable
private fun MachineStubsSection(prefs: SharedPreferences, accent: Color) {
    SettingsSectionHeader("Machines", Icons.Filled.Storage, accent)
    SettingsGroup(accent) {
        SettingsSwitchItem(prefs, "wawona.pref.shakeToCloseEnabled", "Shake to Exit Machine",
            "When enabled, shaking the device asks before closing the active machine session.",
            Icons.Filled.Vibration, default = true, iconTint = accent)
        SettingsSwitchItem(prefs, "wawona.pref.swipeBackToCloseEnabled", "Swipe Back to Exit Machine",
            "When enabled, the system back gesture asks before closing the active machine session.",
            Icons.Filled.ArrowBack, default = true, iconTint = accent)
        SettingsSwitchItem(prefs, "MachineSessionThumbnailsEnabled", "Session Thumbnails",
            "Save the last frame from a machine session and show it on machine cards.",
            Icons.Filled.Image, default = true, iconTint = accent)
    }
    SettingsTextInputItem(
        prefs, "machineVmProvider", "VM Provider",
        "Hypervisor lane (microvm, utm-se, qemu-jit)", Icons.Filled.Storage,
        "utm-se", KeyboardType.Text
    )
    SettingsTextInputItem(
        prefs, "machineVmDefaultVsockPort", "Default VSock Port",
        "Guest waypipe port (wwn-vms mobile guest default)", Icons.Filled.Tune,
        "1024", KeyboardType.Number
    )
    SettingsTextInputItem(
        prefs, "machineContainerDefaultRef", "Default Image Ref",
        "OCI reference for container profiles", Icons.Filled.Inventory2,
        "alpine:3.20", KeyboardType.Text
    )
    SettingsTextInputItem(
        prefs, "machineContainerRuntime", "Container Runtime",
        "In-guest runtime (crun/podman/proot)", Icons.Filled.AccountTree,
        "crun", KeyboardType.Text
    )
}

// ═══════════════════════════════════════════════════════════════════════════
// Section composables
// ═══════════════════════════════════════════════════════════════════════════

@Composable
private fun DisplaySection(prefs: SharedPreferences) {
    SettingsSectionHeader("Display", Icons.Filled.DesktopWindows, SettingsTab.DISPLAY.accentColor)
    SettingsGroup(SettingsTab.DISPLAY.accentColor) {
        SettingsSwitchItem(prefs, "colorOperations", "Enable HDR",
            "Color profiles and HDR present path", Icons.Filled.Palette, default = true,
            iconTint = SettingsTab.DISPLAY.accentColor)
        SettingsSwitchItem(prefs, "respectSafeArea", "Respect Safe Area",
            "Avoid system UI and notches", Icons.Filled.Security, default = true, iconTint = SettingsTab.DISPLAY.accentColor)
    }
}

@Composable
private fun GraphicsSection(prefs: SharedPreferences) {
    SettingsSectionHeader("Drivers", Icons.Filled.Speed, SettingsTab.GRAPHICS.accentColor)
    SettingsGroup(SettingsTab.GRAPHICS.accentColor) {
        SettingsDropdownItem(prefs, "vulkanDriver", "Vulkan Driver",
            "Select Vulkan implementation. None disables Vulkan.", Icons.Filled.Speed, "System",
            listOf("None", "SwiftShader", "System"), iconTint = SettingsTab.GRAPHICS.accentColor)
        SettingsDropdownItem(prefs, "openglDriver", "OpenGL Driver",
            "Select OpenGL/GLES implementation. None disables OpenGL.", Icons.Filled.GraphicEq, "ANGLE",
            listOf("None", "ANGLE", "System"), iconTint = SettingsTab.GRAPHICS.accentColor)
    }
}

@Composable
private fun EnvironmentSection(prefs: SharedPreferences, accent: Color) {
    var map by remember {
        mutableStateOf(EnvironmentOverrides.loadGlobal(prefs).toList().sortedBy { it.first })
    }
    var showEditor by remember { mutableStateOf(false) }
    var editName by remember { mutableStateOf("") }
    var editValue by remember { mutableStateOf("") }
    var isNew by remember { mutableStateOf(false) }

    fun persist(next: Map<String, EnvironmentOverrides.Entry>) {
        EnvironmentOverrides.saveGlobal(prefs, next)
        map = next.toList().sortedBy { it.first }
        try {
            WawonaNative.nativeApplyEnvironmentOverrides(
                EnvironmentOverrides.jniPayload(prefs, null)
            )
        } catch (_: Throwable) {
        }
    }

    SettingsSectionHeader("Env Vars", Icons.Filled.List, accent)
    Text(
        "Windows-style overrides for vars Wawona injects (TERM, WAYLAND_DISPLAY, VK_*, …). " +
            "Machine Settings can override these. Applies on next Start.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(bottom = 8.dp).testTag(WawonaTestTags.SETTINGS_ENVIRONMENT),
    )
    SettingsGroup(accent) {
        if (map.isEmpty()) {
            Text(
                "No global overrides (Wawona defaults).",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(12.dp),
            )
        } else {
            map.forEach { (name, entry) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(name, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
                        Text(
                            if (entry.action == "unset") "(unset)" else (entry.value ?: ""),
                            fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    TextButton(onClick = {
                        isNew = false
                        editName = name
                        editValue = entry.value ?: ""
                        showEditor = true
                    }) { Text("Edit") }
                    TextButton(onClick = {
                        val next = EnvironmentOverrides.loadGlobal(prefs)
                        next.remove(name)
                        persist(next)
                    }) { Text("Reset") }
                }
            }
        }
    }
    Row(modifier = Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = {
            isNew = true
            editName = ""
            editValue = ""
            showEditor = true
        }) { Text("New") }
        OutlinedButton(onClick = {
            val next = EnvironmentOverrides.loadGlobal(prefs)
            EnvironmentOverrides.resetManaged(next)
            persist(next)
        }) { Text("Reset Wawona-managed") }
        OutlinedButton(onClick = { persist(emptyMap()) }) { Text("Reset All") }
    }

    if (showEditor) {
        AlertDialog(
            onDismissRequest = { showEditor = false },
            title = { Text(if (isNew) "New Variable" else "Edit Variable") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editName,
                        onValueChange = { editName = it },
                        label = { Text("Name") },
                        enabled = isNew,
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = editValue,
                        onValueChange = { editValue = it },
                        label = { Text("Value") },
                        singleLine = true,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val name = editName.trim()
                    if (name.isNotEmpty()) {
                        val next = EnvironmentOverrides.loadGlobal(prefs)
                        next[name] = EnvironmentOverrides.Entry.set(editValue)
                        persist(next)
                    }
                    showEditor = false
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { showEditor = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun AdvancedSection(prefs: SharedPreferences) {
    SettingsSectionHeader("Advanced", Icons.Filled.Tune, SettingsTab.ADVANCED.accentColor)
    SettingsGroup(SettingsTab.ADVANCED.accentColor) {
        SettingsSwitchItem(prefs, "nestedCompositorsSupport", "Nested Compositors",
            "Support nested Wayland compositors", Icons.Filled.Layers, default = true,
            iconTint = SettingsTab.ADVANCED.accentColor)
        SettingsDropdownItem(
            prefs,
            "compositorBackend",
            "Display Backend",
            "How bundled clients and nested compositors present. Wayland runs them nested inside Wawona; DRM/KMS runs them against wwn-iland's userspace display stack.",
            Icons.Filled.Monitor,
            "auto",
            listOf("auto", "wayland", "drm"),
            iconTint = SettingsTab.ADVANCED.accentColor,
            optionLabels = mapOf(
                "auto" to "Auto",
                "wayland" to "Wayland (nested)",
                "drm" to "DRM/KMS (wwn-iland)",
            ),
        )
        SettingsSwitchItem(prefs, "multipleClients", "Multiple Clients",
            "Allow multiple Wayland clients", Icons.Filled.Group, default = true,
            iconTint = SettingsTab.ADVANCED.accentColor)
        SettingsSwitchItem(prefs, "westonSimpleSHMEnabled", "Enable Weston Simple SHM",
            "Start weston-simple-shm on launch", Icons.Filled.PlayArrow, default = false,
            iconTint = SettingsTab.ADVANCED.accentColor)
        SettingsSwitchItem(prefs, "westonEnabled", "Enable Native Weston",
            "Start native weston compositor", Icons.Filled.Monitor, default = false,
            iconTint = SettingsTab.ADVANCED.accentColor)
        SettingsSwitchItem(prefs, "westonTerminalEnabled", "Enable Weston Terminal",
            "Start native weston-terminal client", Icons.Filled.Terminal, default = false,
            iconTint = SettingsTab.ADVANCED.accentColor)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DesktopSection(prefs: SharedPreferences, context: Context, accent: Color) {
    var enabled by remember { mutableStateOf(DesktopReplacement.isEnabled(prefs)) }
    val selectedMachineId = DesktopReplacement.desktopMachineId(prefs)
    val profiles = remember { MachineProfileStore.loadProfiles(prefs) }
    val nativeMachines = remember(profiles) { DesktopReplacement.eligibleMachines(profiles) }
    var isHome by remember { mutableStateOf(DesktopReplacement.isWawonaHome(context)) }
    var appBridgeEnabled by remember { mutableStateOf(DesktopReplacement.isAppBridgeEnabled(prefs)) }
    var powerModeEnabled by remember { mutableStateOf(DesktopReplacement.isPowerModeEnabled(prefs)) }
    val openChoice = LocalOpenSettingsChoice.current

    SettingsSectionHeader("Desktop Replacement", Icons.Filled.DesktopMac, accent)

    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = accent.copy(alpha = 0.12f),
    ) {
        Text(
            "Turn Wawona into an Android Launcher: one native machine becomes your " +
                "Wayland desktop, and an app drawer lets you open both Android apps and " +
                "the Wayland clients from Machine Configuration. Only a Native machine " +
                "can be the desktop. VM, container, and network (waypipe/SSH) machines " +
                "are not eligible.\n\n" +
                "Unlike macOS Desktop Replacement, Android does not require SIP changes or " +
                "Recovery-mode steps. Set Wawona as your Home app below.",
            Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodySmall,
        )
    }

    SettingsGroup(accent) {
        Surface(
            onClick = {
                enabled = !enabled
                DesktopReplacement.setEnabled(prefs, enabled)
            },
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.45f),
        ) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Apps, null, Modifier.size(24.dp), tint = accent)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Enable Desktop Replacement",
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis)
                    }
                }
                Spacer(Modifier.width(16.dp))
                Switch(checked = enabled, onCheckedChange = {
                    enabled = it
                    DesktopReplacement.setEnabled(prefs, it)
                })
            }
        }
    }

    if (enabled) {
        SettingsSectionHeader("Desktop Machine", Icons.Filled.Computer, accent)
        if (nativeMachines.isEmpty()) {
            Surface(
                Modifier.fillMaxWidth().padding(vertical = 4.dp),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.4f),
            ) {
                Text(
                    "No Native machine profiles found. Create a Native machine in " +
                        "Machine Configuration first, then select it here.",
                    Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        } else {
            val selectedProfile = nativeMachines.firstOrNull { it.id == selectedMachineId }
            SettingsGroup(accent) {
                val displayName = selectedProfile?.name?.ifBlank { "Unnamed Machine" }
                    ?: "Select a native machine"
                Surface(
                    onClick = {
                        openChoice(
                            SettingsChoiceSpec(
                                key = DesktopReplacement.KEY_MACHINE_ID,
                                title = "Desktop Machine",
                                options = nativeMachines.map { it.id },
                                optionLabels = nativeMachines.associate { machine ->
                                    machine.id to machine.name.ifBlank { "Unnamed Machine" }
                                },
                                default = selectedMachineId ?: "",
                                persist = { p, id -> DesktopReplacement.setDesktopMachineId(p, id) },
                            )
                        )
                    },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    shape = RoundedCornerShape(16.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "Desktop Machine",
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            displayName,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.width(4.dp))
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = "Show choices",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        SettingsSectionHeader("Android Home", Icons.Filled.Home, accent)
        SettingsGroup(accent) {
            Row(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (isHome) Icons.Filled.CheckCircle else Icons.Filled.Info,
                    null,
                    Modifier.size(22.dp),
                    tint = if (isHome) Color(0xFF34D399) else accent,
                )
                Spacer(Modifier.width(12.dp))
                Text(
                    if (isHome) "Wawona is your current Home app."
                    else "Wawona is not the current Home app.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
            }
            OutlinedButton(
                onClick = {
                    val intent = DesktopReplacement.homeRoleRequestIntent(context)
                    if (intent != null) {
                        try {
                            context.startActivity(intent)
                        } catch (e: Exception) {
                            Toast.makeText(context, "Unable to open Home settings: ${e.message}", Toast.LENGTH_LONG).show()
                        }
                    }
                    isHome = DesktopReplacement.isWawonaHome(context)
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Text(if (isHome) "Change Default Home App" else "Set Wawona as Home App")
            }
        }

        // ── Wawona Swinging Bridge ──────────────────────────────────────────────
        SettingsSectionHeader("Wawona Swinging Bridge", Icons.Filled.Apps, accent)

        Surface(
            Modifier.fillMaxWidth().padding(vertical = 4.dp),
            shape = RoundedCornerShape(16.dp),
            color = accent.copy(alpha = 0.12f),
        ) {
            Text(
                "Render native Android apps as windows inside the nested Wayland " +
                    "desktop (waypipe-rs mirror). Requires a local nested Weston " +
                    "desktop machine.\n\n" +
                    "Rootless / baseline (Play-safe): own Wawona surfaces + consented " +
                    "MediaProjection mirroring. No SIP, no root.\n\n" +
                    "Power Mode (Shizuku or root): embed any installed app with " +
                    "privileged input. Auto-falls back to rootless if Shizuku/root " +
                    "is unavailable. Not Play-compliant.",
                Modifier.padding(14.dp),
                style = MaterialTheme.typography.bodySmall,
            )
        }

        val appBridgeEligible = remember(profiles) {
            DesktopReplacement.appBridgeEligibleMachines(profiles)
        }
        val selectedEligible = appBridgeEligible.any { it.id == selectedMachineId }

        SettingsGroup(accent) {
            Surface(
                onClick = {
                    val next = !appBridgeEnabled
                    appBridgeEnabled = next
                    DesktopReplacement.setAppBridgeEnabled(prefs, next)
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.45f),
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Apps, null, Modifier.size(24.dp), tint = accent)
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f)) {
                            Text("Enable App Bridge",
                                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis)
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    Switch(
                        checked = appBridgeEnabled,
                        enabled = selectedEligible,
                        onCheckedChange = {
                            appBridgeEnabled = it
                            DesktopReplacement.setAppBridgeEnabled(prefs, it)
                        },
                    )
                }
            }
        }

        if (!selectedEligible) {
            Surface(
                Modifier.fillMaxWidth().padding(vertical = 4.dp),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.4f),
            ) {
                Text(
                    "Select a nested-Weston desktop machine above to enable the App " +
                        "Bridge. Plain Weston clients (weston-terminal, simple-shm, " +
                        "foot) and remote/VM/container machines are not eligible.",
                    Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        if (appBridgeEnabled) {
            val power = remember { AnowawPowerController(context) }
            SettingsGroup(accent) {
                Surface(
                    onClick = {
                        if (power.isAvailable()) {
                            val next = !powerModeEnabled
                            powerModeEnabled = next
                            DesktopReplacement.setPowerModeEnabled(prefs, next)
                        } else {
                            Toast.makeText(context, power.statusDescription(), Toast.LENGTH_LONG).show()
                        }
                    },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    shape = RoundedCornerShape(16.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.45f),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Bolt, null, Modifier.size(24.dp), tint = accent)
                            Spacer(Modifier.width(16.dp))
                            Column(Modifier.weight(1f)) {
                                Text("Power Mode (Shizuku / root)",
                                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium))
                                Spacer(Modifier.height(4.dp))
                                Text("Embed any installed app. Not Play-compliant. " +
                                    power.statusDescription(),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Spacer(Modifier.width(16.dp))
                        Switch(
                            checked = powerModeEnabled,
                            enabled = power.isAvailable(),
                            onCheckedChange = {
                                powerModeEnabled = it
                                DesktopReplacement.setPowerModeEnabled(prefs, it)
                            },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LockscreenSection(prefs: SharedPreferences, accent: Color) {
    var enabled by remember { mutableStateOf(LockscreenReplacement.isEnabled(prefs)) }
    val selectedMachineId = LockscreenReplacement.lockscreenMachineId(prefs)
    val profiles = remember { MachineProfileStore.loadProfiles(prefs) }
    val lockMachines = remember(profiles) { LockscreenReplacement.eligibleMachines(profiles) }
    val openChoice = LocalOpenSettingsChoice.current

    SettingsSectionHeader("Lockscreen Replacement", Icons.Filled.Lock, accent)
    Surface(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = accent.copy(alpha = 0.12f),
    ) {
        Text(
            "Run a local greeter/lock machine (gtkgreet, gtklock, …) before the " +
                "Desktop Replacement session. Unlock resumes the configured desktop " +
                "machine when Desktop Replacement is enabled. macOS + Android only.",
            Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodySmall,
        )
    }
    SettingsGroup(accent) {
        Surface(
            onClick = {
                enabled = !enabled
                LockscreenReplacement.setEnabled(prefs, enabled)
            },
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.45f),
        ) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "Enable Lockscreen Replacement",
                        style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Switch(checked = enabled, onCheckedChange = {
                    enabled = it
                    LockscreenReplacement.setEnabled(prefs, it)
                })
            }
        }
    }
    if (enabled) {
        if (lockMachines.isEmpty()) {
            Text(
                "No greeter/lock Native machines found. Create one with gtkgreet or gtklock.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        } else {
            val selected = lockMachines.firstOrNull { it.id == selectedMachineId }
            SettingsGroup(accent) {
                Surface(
                    onClick = {
                        openChoice(
                            SettingsChoiceSpec(
                                key = LockscreenReplacement.KEY_MACHINE_ID,
                                title = "Lockscreen Machine",
                                options = lockMachines.map { it.id },
                                optionLabels = lockMachines.associate { it.id to it.name },
                                default = selectedMachineId ?: "",
                                persist = { p, id ->
                                    LockscreenReplacement.setLockscreenMachineId(p, id)
                                },
                            )
                        )
                    },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    shape = RoundedCornerShape(16.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "Lockscreen Machine",
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            selected?.name ?: "Select lockscreen machine",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.width(4.dp))
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = "Show choices",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun InputSection(prefs: SharedPreferences) {
    SettingsSectionHeader("Input", Icons.Filled.Keyboard, SettingsTab.INPUT.accentColor)
    SettingsGroup(SettingsTab.INPUT.accentColor) {
        var showVirtualCursor by remember {
            mutableStateOf(prefs.getBoolean("renderMacOSPointer", false))
        }
        SettingsSwitchItem(
            prefs,
            "renderMacOSPointer",
            "Show Virtual Cursor",
            "Show/hide the virtual cursor used in touchpad mode.",
            Icons.Filled.Mouse,
            default = false,
            iconTint = SettingsTab.INPUT.accentColor,
            onCheckedChange = { showVirtualCursor = it },
        )
        SettingsDropdownItem(
            prefs,
            "nestedCompositorCursor",
            "Nested Compositor Cursor",
            "When nested compositors run, grab the virtual pointer or the host cursor. Requires Show Virtual Cursor.",
            Icons.Filled.Mouse,
            "virtual",
            listOf("virtual", "host"),
            iconTint = SettingsTab.INPUT.accentColor,
            enabled = showVirtualCursor,
            optionLabels = mapOf(
                "virtual" to "Virtual Pointer",
                "host" to "Host Cursor",
            ),
        )
        SettingsSwitchItem(prefs, "touchpadMode", "Touchpad Mode",
            "1-finger = pointer, tap = click, 2-finger drag = scroll. When off, use direct touch (multi-touch)",
            Icons.Filled.TouchApp, default = false, iconTint = SettingsTab.INPUT.accentColor)
        SettingsSwitchItem(
            prefs,
            "resizeDisplayForVirtualKeyboard",
            "Resize Display for Virtual Keyboard",
            "Shrink the Wayland output by host IME + Wawona extra keyboard height (issue #83)",
            Icons.Filled.Keyboard,
            default = true,
            iconTint = SettingsTab.INPUT.accentColor,
        )
        SettingsSwitchItem(prefs, "enableTextAssist", "Enable Text Assist",
            "Autocorrect, text suggestions, smart punctuation, swipe-to-type, and text replacements via the native keyboard",
            Icons.Filled.Spellcheck, default = false, iconTint = SettingsTab.INPUT.accentColor)
        SettingsSwitchItem(prefs, "enableDictation", "Enable Dictation",
            "Voice dictation input. Spoken text is transcribed and sent to the focused Wayland client",
            Icons.Filled.Mic, default = false, iconTint = SettingsTab.INPUT.accentColor)
    }
}

@Composable
private fun ConnectionSection(prefs: SharedPreferences, localIp: String?, context: Context, accent: Color) {
    SettingsSectionHeader("Network", Icons.Filled.Computer, accent)
    SettingsInfoRow(
        title = "Local IP Address",
        value = localIp ?: "Not available",
        description = "",
        icon = Icons.Filled.Info
    )

    SettingsTextInputItem(prefs, "waypipeDisplay", "Wayland Display",
        "Display socket name (e.g., wayland-0)", Icons.Filled.DesktopWindows,
        "wayland-0", KeyboardType.Text, revertToDefaultOnEmpty = true)

    val androidSocketPath = remember { "${context.cacheDir.absolutePath}/waypipe" }
    SettingsTextInputItem(prefs, "waypipeSocket", "Socket Path",
        "Unix socket path (set by platform)", Icons.Filled.Folder,
        androidSocketPath, KeyboardType.Text, readOnly = true)
}

@Composable
private fun LocalShellSection(context: Context, accent: Color) {
    var statusMessage by remember { mutableStateOf<String?>(null) }

    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        LocalShellRootfs.importFile(context, uri, null)
            .onSuccess { file ->
                statusMessage = "Imported ${file.name} → home/"
                Toast.makeText(context, statusMessage, Toast.LENGTH_LONG).show()
            }
            .onFailure { e ->
                statusMessage = "Import failed: ${e.message}"
                Toast.makeText(context, statusMessage, Toast.LENGTH_LONG).show()
            }
    }

    SettingsSectionHeader("Local Shell", Icons.Filled.Folder, accent)

    SettingsGroup(accent) {
        if (LocalShellCapability.ImportFile in LocalShellRootfs.capabilities()) {
            OutlinedButton(
                onClick = { importLauncher.launch(arrayOf("*/*")) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
            ) { Text("Import File to Home", maxLines = 2) }
        }

        if (LocalShellCapability.ResetDotfiles in LocalShellRootfs.capabilities()) {
            OutlinedButton(
                onClick = {
                    LocalShellRootfs.refreshShellDotfiles(context)
                        .onSuccess {
                            Toast.makeText(context, "Shell dotfiles refreshed", Toast.LENGTH_SHORT).show()
                        }
                        .onFailure { e ->
                            Toast.makeText(context, "Failed: ${e.message}", Toast.LENGTH_LONG).show()
                        }
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
            ) { Text("Reset Shell Dotfiles", maxLines = 2) }
        }

        if (LocalShellCapability.ReinstallSystemTree in LocalShellRootfs.capabilities()) {
            OutlinedButton(
                onClick = {
                    LocalShellRootfs.reinstallSystemTree(context)
                        .onSuccess {
                            Toast.makeText(context, "System tree reset", Toast.LENGTH_SHORT).show()
                        }
                        .onFailure { e ->
                            Toast.makeText(context, "Failed: ${e.message}", Toast.LENGTH_LONG).show()
                        }
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
            ) { Text("Reset System Tree", maxLines = 2) }
        }
    }

    statusMessage?.let { msg ->
        Text(msg, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun WaypipeSection(prefs: SharedPreferences, context: Context, accent: Color) {
    SettingsSectionHeader("Transport", Icons.Filled.Wifi, accent)
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
    SettingsSectionHeader("Remote Execution", Icons.Filled.PlayArrow, accent)
    SettingsTextInputItem(prefs, "waypipeRemoteCommand", "Remote Command",
        "Application to run remotely (e.g., weston-simple-shm)", Icons.Filled.PlayArrow, "", KeyboardType.Text)
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
            Text("Waypipe & SSH Logs", style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f))
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Show logs",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
            Text("Advanced Waypipe Options", style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f))
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Advanced Waypipe Options",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (showAdvanced) {
        AdvancedWaypipeDialog(prefs) { showAdvanced = false }
    }
}

@Composable
private fun SSHSection(prefs: SharedPreferences, accent: Color) {
    SettingsSectionHeader("Secure Shell", Icons.Filled.Lock, accent)
    SettingsSwitchItem(prefs, "waypipeSSHEnabled", "Enable SSH",
        "Use SSH transport for waypipe connections", Icons.Filled.Lock, default = true, iconTint = accent)

    SettingsInfoRow(
        title = "SSH Library",
        value = "OpenSSH",
        description = "OpenSSH portable client (wwn-ssh) for terminal + waypipe",
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
    SettingsSectionHeader("Connection", Icons.Filled.Computer, accent)
    SettingsTextInputItem(prefs, "waypipeSSHHost", "SSH Host",
        "IP or hostname (use IP on Android; SSH config aliases like \"ssh\" don't resolve)",
        Icons.Filled.Computer, "", KeyboardType.Text)
    SettingsTextInputItem(prefs, "waypipeSSHUser", "SSH User",
        "SSH username", Icons.Filled.Person, "", KeyboardType.Text)

    // Auth method
    SettingsSectionHeader("Authentication", Icons.Filled.VpnKey, accent)
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
        SettingsDropdownItem(prefs, "sshKeyType", "Key Type",
            "Algorithm for Generate Key", Icons.Filled.VpnKey, "ed25519",
            listOf("ed25519", "ecdsa", "rsa"))
        SettingsTextInputItem(prefs, "sshKeyPath", "Private Key Path",
            "Path to SSH private key (synced to waypipeSSHKeyPath)", Icons.Filled.Key,
            "", KeyboardType.Text)
        SettingsTextInputItem(prefs, "sshKeyPassphrase", "Key Passphrase",
            "Passphrase for encrypted private key (leave empty if none)", Icons.Filled.Password,
            "", KeyboardType.Password)
    }

    Spacer(Modifier.height(12.dp))

    // Test buttons -- read prefs FRESH at click time (not cached at composition)
    SettingsSectionHeader("Diagnostics", Icons.Filled.NetworkCheck, accent)
    val scope = rememberCoroutineScope()
    var pingResult by remember { mutableStateOf<String?>(null) }
    var sshResult by remember { mutableStateOf<String?>(null) }
    var keygenResult by remember { mutableStateOf<String?>(null) }
    var isPinging by remember { mutableStateOf(false) }
    var isSshTesting by remember { mutableStateOf(false) }
    var isKeygen by remember { mutableStateOf(false) }
    val ctxGen = LocalContext.current

    if (authMethod.value != "password") {
        val gpgImportLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.GetContent()
        ) { uri: Uri? ->
            if (uri == null) return@rememberLauncherForActivityResult
            scope.launch {
                keygenResult = withContext(Dispatchers.IO) {
                    try {
                        androidImportGpgSshKey(ctxGen, prefs, uri)
                    } catch (e: Exception) {
                        "FAIL: ${e.message}"
                    }
                }
            }
        }
        OutlinedButton(
            onClick = {
                isKeygen = true
                keygenResult = null
                scope.launch {
                    keygenResult = withContext(Dispatchers.IO) {
                        try {
                            androidGenerateSshKey(ctxGen, prefs)
                        } catch (e: Exception) {
                            "FAIL: ${e.message}"
                        }
                    }
                    isKeygen = false
                }
            },
            enabled = !isKeygen,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
        ) {
            Icon(Icons.Filled.Key, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (isKeygen) "Generating…" else "Generate Key")
        }
        OutlinedButton(
            onClick = { gpgImportLauncher.launch("*/*") },
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
        ) {
            Icon(Icons.Filled.Upload, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("Import GPG SSH Key")
        }
        Text(
            "Import OpenSSH private keys from `gpg --export-ssh-key` (or id_*). " +
                "Generate Key supports ed25519 / ecdsa / rsa; passphrase optional.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 4.dp)
        )
        keygenResult?.let { TestResultCard(it, ctxGen) }
    }

    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(
            onClick = {
                val host = prefs.getString("waypipeSSHHost", "") ?: ""
                val port = (prefs.getString("waypipeSSHPort", "22") ?: "22").toIntOrNull() ?: 22
                if (host.isBlank()) { pingResult = "FAIL: SSH Host is empty"; return@OutlinedButton }
                isPinging = true; pingResult = null
                scope.launch {
                    pingResult = withContext(Dispatchers.IO) {
                        try { WawonaNative.nativeTestPing(host, port, 5000) }
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
                val port = (prefs.getString("waypipeSSHPort", "22") ?: "22").toIntOrNull() ?: 22
                val keyPath = prefs.getString("waypipeSSHKeyPath", null)
                    ?: prefs.getString("sshKeyPath", "") ?: ""
                val auth = prefs.getString("sshAuthMethod", "password") ?: "password"
                val authMethodInt = if (auth == "publickey" || auth == "1") 1 else 0
                if (host.isBlank()) { sshResult = "FAIL: SSH Host is empty"; return@OutlinedButton }
                if (user.isBlank()) { sshResult = "FAIL: SSH User is empty"; return@OutlinedButton }
                isSshTesting = true; sshResult = null
                scope.launch {
                    sshResult = withContext(Dispatchers.IO) {
                        try {
                            WawonaNative.nativeTestSSH(
                                host, user, pass, port, keyPath, authMethodInt
                            )
                        } catch (e: Exception) { "FAIL: ${e.message}" }
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
        AndroidView(
            modifier = Modifier.size(100.dp),
            factory = { ctx ->
                ImageView(ctx).apply {
                    setImageDrawable(context.packageManager.getApplicationIcon(context.applicationInfo))
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    contentDescription = "Wawona"
                }
            },
        )
        Spacer(Modifier.height(16.dp))
        Text("Wawona",
            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold),
            color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(4.dp))
        Text("Version $version",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = { uriHandler.openUri("https://wawona.io") },
            modifier = Modifier.fillMaxWidth().testTag("wwn.settings.aboutWebsite"),
            shape = RoundedCornerShape(12.dp)
        ) { Text("https://wawona.io") }
        Spacer(Modifier.height(8.dp))
        val hostOs = remember {
            "Android ${Build.VERSION.RELEASE} (${Build.MODEL})"
        }
        val installChannel = remember { androidInstallChannel(context) }
        val versionBare = remember {
            if (version.startsWith("v")) version.drop(1) else version
        }
        OutlinedButton(
            onClick = {
                copyWawonaBugDiagnostics(
                    context,
                    version,
                    hostOs,
                    installChannel,
                    machineOnly = false,
                )
            },
            modifier = Modifier.fillMaxWidth().testTag("wwn.settings.copyRecentLogs"),
            shape = RoundedCornerShape(12.dp)
        ) { Text("Copy Recent Logs") }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = {
                openWawonaGithubBugReport(
                    context,
                    uriHandler,
                    versionBare,
                    hostOs,
                    installChannel,
                )
            },
            modifier = Modifier.fillMaxWidth().testTag("wwn.settings.reportBug"),
            shape = RoundedCornerShape(12.dp)
        ) { Text("Report a Bug on GitHub") }
        Spacer(Modifier.height(8.dp))
        Text("A Wayland Compositor for macOS, iOS & Android",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        Text("Author",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        OutlinedButton(
            onClick = { uriHandler.openUri("https://aspauldingcode.com") },
            modifier = Modifier.fillMaxWidth().testTag("wwn.settings.aboutAuthor"),
            shape = RoundedCornerShape(12.dp)
        ) { Text("Alex Spaulding") }
        Spacer(Modifier.height(16.dp))
        OutlinedButton(
            onClick = { uriHandler.openUri("https://github.com/wawona/wawona") },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) { Text("Source Code") }
        Spacer(Modifier.height(12.dp))
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
    val context = LocalContext.current
    val packages = remember {
        runCatching {
            val json = context.assets.open("SettingsDependencies.json")
                .bufferedReader().use { it.readText() }
            val arr = org.json.JSONObject(json).getJSONArray("packages")
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Triple(o.optString("name"), o.optString("version"), o.optString("role"))
            }
        }.getOrDefault(emptyList())
    }
    if (packages.isEmpty()) {
        SettingsInfoRow(
            title = "Dependencies",
            value = "unavailable",
            description = "SettingsDependencies.json missing from this Android build.",
            icon = Icons.Filled.Inventory2
        )
    } else {
        packages.forEach { (name, version, role) ->
            AboutDependencyRow(name, version, role)
        }
    }
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
    var showDetail by remember { mutableStateOf(false) }
    val body = listOf(description, value).filter { it.isNotBlank() }.joinToString("\n\n")
    Surface(
        onClick = { showDetail = true },
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
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
                Text(
                    title,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Clip
                )
                if (value.isNotBlank()) {
                    Text(
                        value.replace('\n', ' ').replace(Regex(" +"), " ").trim(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        overflow = TextOverflow.Clip
                    )
                }
            }
        }
    }
    if (showDetail) {
        AlertDialog(
            onDismissRequest = { showDetail = false },
            title = { Text(title) },
            text = { Text(body.ifEmpty { title }) },
            confirmButton = {
                TextButton(onClick = { showDetail = false }) { Text("OK") }
            }
        )
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
private fun SettingsGroup(
    accent: Color = MaterialTheme.colorScheme.primary,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(16.dp))
            .border(
                1.dp,
                accent.copy(alpha = 0.35f),
                RoundedCornerShape(16.dp),
            )
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(6.dp),
        content = content,
    )
}

@Composable
fun SettingsSectionHeader(title: String, icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = tint)
        Spacer(Modifier.width(8.dp))
        Text(title,
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.SemiBold, letterSpacing = (-0.01).sp),
            color = tint)
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
                Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
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
    icon: ImageVector, default: Boolean, enabled: Boolean = true,
    iconTint: Color = MaterialTheme.colorScheme.primary,
    onCheckedChange: ((Boolean) -> Unit)? = null,
) {
    var checked by remember { mutableStateOf(prefs.getBoolean(key, default)) }
    LaunchedEffect(key) {
        if (enabled) checked = prefs.getBoolean(key, default)
        else { checked = default; prefs.edit().putBoolean(key, default).apply() }
    }
    fun commit(next: Boolean) {
        checked = next
        prefs.edit().putBoolean(key, next).apply()
        onCheckedChange?.invoke(next)
    }
    Surface(
        onClick = { if (enabled) commit(!checked) },
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .border(
                1.dp,
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = if (enabled) 0.28f else 0.16f),
                RoundedCornerShape(16.dp),
            ),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = if (enabled) 0.45f else 0.25f)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(24.dp),
                    tint = iconTint.copy(alpha = if (enabled) 0.9f else 0.4f))
                Spacer(Modifier.width(16.dp))
                Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
            }
            Spacer(Modifier.width(16.dp))
            Switch(checked = checked, onCheckedChange = {
                if (enabled) commit(it)
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
                Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
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
                Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
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
                Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
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

@Composable
private fun SettingsChoiceList(
    spec: SettingsChoiceSpec,
    prefs: SharedPreferences,
    onPicked: () -> Unit,
) {
    val selected = prefs.getString(spec.key, spec.default) ?: spec.default
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        spec.options.forEach { option ->
            val label = spec.optionLabels[option] ?: option
            Surface(
                onClick = {
                    val persist = spec.persist
                    if (persist != null) {
                        persist(prefs, option)
                    } else {
                        prefs.edit().putString(spec.key, option).apply()
                    }
                    onPicked()
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.45f),
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (option == selected) {
                        Icon(
                            Icons.Filled.Check,
                            contentDescription = "Selected",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDropdownItem(
    prefs: SharedPreferences, key: String, title: String, description: String,
    icon: ImageVector, default: String, options: List<String>,
    iconTint: Color = MaterialTheme.colorScheme.primary,
    enabled: Boolean = true,
    optionLabels: Map<String, String> = emptyMap(),
) {
    var selectedOption by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    LaunchedEffect(key) { selectedOption = prefs.getString(key, default) ?: default }
    val displayValue = optionLabels[selectedOption] ?: selectedOption
    val openChoice = LocalOpenSettingsChoice.current
    Surface(
        onClick = {
            if (enabled) {
                openChoice(
                    SettingsChoiceSpec(
                        key = key,
                        title = title,
                        options = options,
                        optionLabels = optionLabels,
                        default = default,
                    )
                )
            }
        },
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (enabled) 0.4f else 0.22f)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, null, Modifier.size(24.dp),
                tint = iconTint.copy(alpha = if (enabled) 0.9f else 0.4f))
            Spacer(Modifier.width(16.dp))
            Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.6f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f))
            Text(
                displayValue,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (enabled) 1f else 0.6f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(4.dp))
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Show choices",
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (enabled) 0.9f else 0.4f),
            )
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

private fun androidImportGpgSshKey(
    context: Context,
    prefs: SharedPreferences,
    uri: Uri
): String {
    val sshDir = File(context.filesDir, "ssh")
    if (!sshDir.exists()) sshDir.mkdirs()
    val name = uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { null } ?: "id_gpg_ssh"
    var dest = File(sshDir, name)
    if (dest.exists()) {
        dest = File(sshDir, "${name}_${System.currentTimeMillis()}")
    }
    context.contentResolver.openInputStream(uri)?.use { input ->
        dest.outputStream().use { output -> input.copyTo(output) }
    } ?: return "FAIL: could not read selected file"
    val text = dest.readText()
    if (!text.contains("PRIVATE KEY") && !text.contains("OPENSSH PRIVATE KEY")) {
        dest.delete()
        return "FAIL: not an OpenSSH/PEM private key (use gpg --export-ssh-key)"
    }
    dest.setReadable(false, false)
    dest.setWritable(false, false)
    dest.setReadable(true, true)
    dest.setWritable(true, true)
    prefs.edit()
        .putString("sshKeyPath", dest.absolutePath)
        .putString("waypipeSSHKeyPath", dest.absolutePath)
        .putString("sshAuthMethod", "publickey")
        .apply()
    return "OK: Imported GPG/OpenSSH key → ${dest.absolutePath}"
}

private fun androidGenerateSshKey(context: Context, prefs: SharedPreferences): String {
    val keyType = prefs.getString("sshKeyType", "ed25519") ?: "ed25519"
    val type = when (keyType) {
        "ecdsa", "rsa", "ed25519" -> keyType
        else -> "ed25519"
    }
    val sshDir = File(context.filesDir, "ssh")
    if (!sshDir.exists()) sshDir.mkdirs()
    var keyFile = File(sshDir, "id_$type")
    if (keyFile.exists()) {
        keyFile = File(sshDir, "id_${type}_${System.currentTimeMillis()}")
    }
    val nativeDir = context.applicationInfo.nativeLibraryDir
    val keygen = File(nativeDir, "libssh_keygen_bin.so")
    if (!keygen.exists()) {
        return "FAIL: ssh-keygen not found at ${keygen.absolutePath}"
    }
    val pass = prefs.getString("sshKeyPassphrase", "") ?: ""
    val pb = ProcessBuilder(
        keygen.absolutePath, "-t", type, "-f", keyFile.absolutePath, "-N", pass, "-q"
    )
    pb.redirectErrorStream(true)
    val proc = pb.start()
    val out = proc.inputStream.bufferedReader().readText()
    val code = proc.waitFor()
    if (code != 0) {
        return "FAIL: ssh-keygen exited $code\n$out"
    }
    prefs.edit()
        .putString("sshKeyPath", keyFile.absolutePath)
        .putString("waypipeSSHKeyPath", keyFile.absolutePath)
        .putString("sshAuthMethod", "publickey")
        .apply()
    val pub = File(keyFile.absolutePath + ".pub")
    val pubText = if (pub.exists()) pub.readText().trim() else ""
    return "OK: Generated ${keyFile.absolutePath}\n$pubText"
}

private fun androidInstallChannel(context: Context): String {
    return try {
        val pm = context.packageManager
        val installer = if (Build.VERSION.SDK_INT >= 30) {
            pm.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            pm.getInstallerPackageName(context.packageName)
        }
        when (installer) {
            "com.android.vending", "com.google.android.feedback" ->
                "Play Store (Beta)"
            null, "", "com.google.android.packageinstaller",
            "com.android.packageinstaller" -> "Sideload APK"
            else -> "Other"
        }
    } catch (_: Exception) {
        "Other"
    }
}

private fun wawonaBugDiagnostics(
    version: String,
    hostOs: String,
    installChannel: String,
    machineOnly: Boolean,
): String {
    val dump = try {
        WawonaNative.nativeLogRingDump(null)
    } catch (_: UnsatisfiedLinkError) {
        "(log ring unavailable)"
    } catch (_: Exception) {
        "(log ring unavailable)"
    }
    val logs = if (dump.isBlank()) "(no recent Wawona logs)" else dump
    val machine = if (machineOnly) {
        "(machine filter requested; Android uses the process log ring)"
    } else {
        "(process log ring)"
    }
    return buildString {
        append("### Wawona diagnostics\n")
        append("Wawona: $version\n")
        append("Host: $hostOs\n")
        append("Install: $installChannel\n")
        append("\n### Active machine\n")
        append(machine)
        append("\n\n### Logs\n```\n")
        append(logs)
        append("\n```\n")
    }
}

private fun copyWawonaBugDiagnostics(
    context: Context,
    version: String,
    hostOs: String,
    installChannel: String,
    machineOnly: Boolean,
) {
    val text = wawonaBugDiagnostics(version, hostOs, installChannel, machineOnly)
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Wawona diagnostics", text))
    Toast.makeText(context, "Copied recent logs", Toast.LENGTH_SHORT).show()
}

private fun openWawonaGithubBugReport(
    context: Context,
    uriHandler: UriHandler,
    versionBare: String,
    hostOs: String,
    installChannel: String,
) {
    val report = wawonaBugDiagnostics(
        if (versionBare.startsWith("v")) versionBare else "v$versionBare",
        hostOs,
        installChannel,
        machineOnly = false,
    )
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Wawona diagnostics", report))
    val url = try {
        WawonaNative.nativeGithubBugReportUrl(
            "Android",
            installChannel,
            versionBare,
            hostOs,
            report,
        )
    } catch (_: UnsatisfiedLinkError) {
        "https://github.com/Wawona/Wawona/issues/new?template=bug.yml&platform=Android"
    } catch (_: Exception) {
        "https://github.com/Wawona/Wawona/issues/new?template=bug.yml&platform=Android"
    }
    try {
        uriHandler.openUri(url)
        Toast.makeText(
            context,
            "Copied logs and opened the GitHub bug form",
            Toast.LENGTH_SHORT,
        ).show()
    } catch (_: Exception) {
        Toast.makeText(context, "Copied logs. Open GitHub to paste them.", Toast.LENGTH_LONG)
            .show()
    }
}
