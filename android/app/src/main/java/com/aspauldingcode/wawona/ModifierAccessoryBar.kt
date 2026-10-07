package com.aspauldingcode.wawona

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs

object LinuxKey {
    const val ESC = 1
    const val KEY_1 = 2
    const val KEY_2 = 3
    const val KEY_3 = 4
    const val KEY_4 = 5
    const val KEY_5 = 6
    const val KEY_6 = 7
    const val KEY_7 = 8
    const val KEY_8 = 9
    const val KEY_9 = 10
    const val KEY_0 = 11
    const val GRAVE = 41
    const val TAB = 15
    const val BACKSPACE = 14
    const val SLASH = 53
    const val MINUS = 12
    const val EQUAL = 13
    const val ENTER = 28
    const val SPACE = 57
    const val LEFTBRACE = 26
    const val RIGHTBRACE = 27
    const val BACKSLASH = 43
    const val SEMICOLON = 39
    const val APOSTROPHE = 40
    const val COMMA = 51
    const val DOT = 52
    const val HOME = 102
    const val UP = 103
    const val END = 107
    const val PAGEUP = 104
    const val LEFTSHIFT = 42
    const val LEFTCTRL = 29
    const val LEFTALT = 56
    const val LEFTMETA = 125
    const val LEFT = 105
    const val DOWN = 108
    const val RIGHT = 106
    const val PAGEDOWN = 109
}

data class LinuxKeyMapping(
    val keycode: Int,
    val needsShift: Boolean = false
)

object ModifierState {
    var shiftActive by mutableStateOf(false)
    var ctrlActive by mutableStateOf(false)
    var altActive by mutableStateOf(false)
    var superActive by mutableStateOf(false)
    var shiftLocked by mutableStateOf(false)
    var ctrlLocked by mutableStateOf(false)
    var altLocked by mutableStateOf(false)
    var superLocked by mutableStateOf(false)

    fun hasActiveModifiers(): Boolean = shiftActive || ctrlActive || altActive || superActive

    fun clearStickyModifiers() {
        if (shiftActive && !shiftLocked) shiftActive = false
        if (ctrlActive && !ctrlLocked) ctrlActive = false
        if (altActive && !altLocked) altActive = false
        if (superActive && !superLocked) superActive = false
    }

    fun clearAllModifiers() {
        shiftActive = false
        ctrlActive = false
        altActive = false
        superActive = false
        shiftLocked = false
        ctrlLocked = false
        altLocked = false
        superLocked = false
    }

    // Best-effort sync from native keyboard modifier stream.
    fun syncShiftFromNative(active: Boolean, locked: Boolean = false) {
        shiftActive = active || locked
        shiftLocked = locked
    }
}

private object XkbMod {
    const val SHIFT = 1 shl 0
    const val CTRL = 1 shl 2
    const val ALT = 1 shl 3
    const val LOGO = 1 shl 6
}

private const val DOUBLE_TAP_THRESHOLD_MS = 400L

/** Terminal fallback only. Printable text is TI v3 (host-keymap-bridge). */
fun controlToLinuxKeycode(ch: Char): LinuxKeyMapping? {
    return when (ch) {
        '\n', '\r' -> LinuxKeyMapping(LinuxKey.ENTER)
        '\t' -> LinuxKeyMapping(LinuxKey.TAB)
        '\u0008', '\u007f' -> LinuxKeyMapping(LinuxKey.BACKSPACE)
        else -> null
    }
}

@Composable
fun ModifierAccessoryBar(
    modifier: Modifier = Modifier,
    keyboardExpanded: Boolean,
    onToggleKeyboardExpanded: () -> Unit,
    onCollapseToPipByDrag: () -> Unit
) {
    var pressTimestamp by remember { mutableStateOf(0) }

    var lastModShiftTap by remember { mutableLongStateOf(0L) }
    var lastModCtrlTap by remember { mutableLongStateOf(0L) }
    var lastModAltTap by remember { mutableLongStateOf(0L) }
    var lastModSuperTap by remember { mutableLongStateOf(0L) }

    fun nextTimestamp(): Int {
        val now = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        if (now > pressTimestamp) {
            pressTimestamp = now
        } else {
            pressTimestamp += 1
        }
        return pressTimestamp
    }

    fun handleModifierTap(
        active: Boolean,
        locked: Boolean,
        lastTap: Long,
        onActive: (Boolean) -> Unit,
        onLocked: (Boolean) -> Unit,
        onLastTap: (Long) -> Unit
    ) {
        val now = System.currentTimeMillis()
        val elapsed = now - lastTap
        onLastTap(now)

        when {
            locked -> {
                onActive(false)
                onLocked(false)
            }
            active && elapsed < DOUBLE_TAP_THRESHOLD_MS -> {
                onLocked(true)
            }
            active -> {
                onActive(false)
                onLocked(false)
            }
            else -> {
                onActive(true)
                onLocked(false)
            }
        }
    }

    fun sendAccessoryKey(keycode: Int) {
        val ts = nextTimestamp()
        var mods = 0
        if (ModifierState.shiftActive) {
            mods = mods or XkbMod.SHIFT
            WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, true, ts)
        }
        if (ModifierState.ctrlActive) {
            mods = mods or XkbMod.CTRL
            WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, true, ts)
        }
        if (ModifierState.altActive) {
            mods = mods or XkbMod.ALT
            WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, true, ts)
        }
        if (ModifierState.superActive) {
            mods = mods or XkbMod.LOGO
            WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, true, ts)
        }
        if (mods != 0) {
            WawonaNative.nativeInjectModifiers(mods, 0, 0, 0)
        }
        WawonaNative.nativeInjectKey(keycode, true, ts)
        WawonaNative.nativeInjectKey(keycode, false, ts)
        if (ModifierState.shiftActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, false, ts)
        if (ModifierState.ctrlActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, false, ts)
        if (ModifierState.altActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, false, ts)
        if (ModifierState.superActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, false, ts)
        if (mods != 0) WawonaNative.nativeInjectModifiers(0, 0, 0, 0)
        ModifierState.clearStickyModifiers()
    }

    val context = LocalContext.current
    val layout = remember { ToolbarLayoutStore(context.applicationContext) }
    var showSettings by remember { mutableStateOf(false) }
    var arrowsOpen by remember { mutableStateOf(false) }
    var revealedDrawers by remember { mutableStateOf(if (layout.drawerOpenByDefault) 1 else 0) }
    var cycleIndex by remember { mutableStateOf(0) }
    val scheme = MaterialTheme.colorScheme
    val barBg = scheme.surfaceContainer
    val keyInactive = scheme.surfaceVariant
    val keySticky = scheme.primary.copy(alpha = 0.6f)
    val keyLocked = scheme.primary.copy(alpha = 0.85f)
    val keyText = scheme.onSurface
    var trayDragX by remember { mutableStateOf(0f) }
    var trayDragY by remember { mutableStateOf(0f) }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = {
                        trayDragX = 0f
                        trayDragY = 0f
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        trayDragX += dragAmount.x
                        trayDragY += dragAmount.y
                    },
                    onDragEnd = {
                        if (abs(trayDragX) > 28f || abs(trayDragY) > 28f) {
                            onCollapseToPipByDrag()
                        }
                        trayDragX = 0f
                        trayDragY = 0f
                    },
                    onDragCancel = {
                        trayDragX = 0f
                        trayDragY = 0f
                    }
                )
            },
        color = barBg,
        contentColor = keyText
    ) {
        val rowMod = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 2.dp)
            .height(36.dp)

        fun pressId(id: String) {
            val custom = layout.custom(id)
            if (custom != null) {
                WawonaNative.nativeCommitText(custom.text)
                return
            }
            val spec = ToolbarCatalog.spec(id)
            when (spec.kind) {
                ToolbarKeyKind.KEY -> sendAccessoryKey(spec.keycode)
                ToolbarKeyKind.SHIFTED -> {
                    val wasShift = ModifierState.shiftActive
                    ModifierState.shiftActive = true
                    sendAccessoryKey(spec.keycode)
                    if (!wasShift && !ModifierState.shiftLocked) ModifierState.shiftActive = false
                }
                ToolbarKeyKind.MOD -> when (spec.mod) {
                    "shift" -> handleModifierTap(
                        ModifierState.shiftActive, ModifierState.shiftLocked, lastModShiftTap,
                        { ModifierState.shiftActive = it },
                        { ModifierState.shiftLocked = it },
                        { lastModShiftTap = it }
                    )
                    "ctrl" -> handleModifierTap(
                        ModifierState.ctrlActive, ModifierState.ctrlLocked, lastModCtrlTap,
                        { ModifierState.ctrlActive = it },
                        { ModifierState.ctrlLocked = it },
                        { lastModCtrlTap = it }
                    )
                    "alt" -> handleModifierTap(
                        ModifierState.altActive, ModifierState.altLocked, lastModAltTap,
                        { ModifierState.altActive = it },
                        { ModifierState.altLocked = it },
                        { lastModAltTap = it }
                    )
                    "super" -> handleModifierTap(
                        ModifierState.superActive, ModifierState.superLocked, lastModSuperTap,
                        { ModifierState.superActive = it },
                        { ModifierState.superLocked = it },
                        { lastModSuperTap = it }
                    )
                }
                ToolbarKeyKind.ACTION -> when (id) {
                    "dismiss" -> if (keyboardExpanded) onToggleKeyboardExpanded()
                    "toolbarSettings" -> showSettings = true
                    "arrowDrawerToggle" -> arrowsOpen = !arrowsOpen
                    "drawerToggle" -> {
                        val count = layout.drawers.size
                        if (layout.drawerToggleMode == "cycle" && count > 1) {
                            if (revealedDrawers == 0) {
                                revealedDrawers = 1
                                cycleIndex = 0
                            } else {
                                cycleIndex = (cycleIndex + 1) % count
                                if (cycleIndex == 0) revealedDrawers = 0
                            }
                        } else if (revealedDrawers >= count) {
                            revealedDrawers = 0
                        } else {
                            revealedDrawers += 1
                        }
                    }
                    "paste" -> {
                        val clip = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        val data = clip?.primaryClip
                        val text = if (data != null && data.itemCount > 0) {
                            data.getItemAt(0).coerceToText(context)?.toString()
                        } else {
                            null
                        }
                        if (!text.isNullOrEmpty()) WawonaNative.nativeCommitText(text)
                    }
                }
            }
        }

        if (showSettings) {
            ToolbarCustomizeDialog(
                layout = layout,
                onDismiss = { showSettings = false },
            )
        }

        Column(modifier = Modifier.fillMaxWidth()) {
            if (arrowsOpen) {
                ToolbarKeyRow(
                    listOf("arrowLeft", "arrowDown", "arrowUp", "arrowRight"),
                    rowMod, keyInactive, keySticky, keyLocked, keyText, layout,
                ) { pressId(it) }
            }
            val drawerRows = if (layout.drawerToggleMode == "cycle" && revealedDrawers > 0) {
                listOf(layout.drawers.getOrElse(cycleIndex) { emptyList() })
            } else {
                layout.drawers.take(revealedDrawers)
            }
            drawerRows.forEach { row ->
                ToolbarKeyRow(row, rowMod, keyInactive, keySticky, keyLocked, keyText, layout) {
                    pressId(it)
                }
            }
            ToolbarKeyRow(
                layout.main, rowMod, keyInactive, keySticky, keyLocked, keyText, layout,
                trailing = {
                    AccessoryKey(
                        if (keyboardExpanded) "IME" else "IME",
                        keyInactive,
                        keyText,
                        onClick = onToggleKeyboardExpanded,
                        modifier = Modifier
                            .width(48.dp)
                            .pointerInput(keyboardExpanded) {
                                var dragDistanceY = 0f
                                detectDragGestures(
                                    onDragStart = { dragDistanceY = 0f },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragDistanceY += dragAmount.y
                                    },
                                    onDragEnd = {
                                        if (!keyboardExpanded && abs(dragDistanceY) > 28f) {
                                            onCollapseToPipByDrag()
                                        }
                                    },
                                    onDragCancel = { dragDistanceY = 0f }
                                )
                            },
                    )
                },
            ) { pressId(it) }
        }
    }
}

@Composable
private fun ToolbarKeyRow(
    ids: List<String>,
    rowMod: Modifier,
    inactive: Color,
    sticky: Color,
    locked: Color,
    textColor: Color,
    layout: ToolbarLayoutStore,
    trailing: (@Composable () -> Unit)? = null,
    onPress: (String) -> Unit,
) {
    Row(
        modifier = rowMod.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ids.forEach { id ->
            val custom = layout.custom(id)
            val spec = ToolbarCatalog.spec(id)
            val label = custom?.label ?: spec.label
            val active = when (spec.mod) {
                "shift" -> ModifierState.shiftActive
                "ctrl" -> ModifierState.ctrlActive
                "alt" -> ModifierState.altActive
                "super" -> ModifierState.superActive
                else -> false
            }
            val isLocked = when (spec.mod) {
                "shift" -> ModifierState.shiftLocked
                "ctrl" -> ModifierState.ctrlLocked
                "alt" -> ModifierState.altLocked
                "super" -> ModifierState.superLocked
                else -> false
            }
            val bg = when {
                isLocked -> locked
                active -> sticky
                else -> inactive
            }
            AccessoryKey(
                label, bg, textColor,
                onClick = { onPress(id) },
                modifier = Modifier.width(52.dp),
            )
        }
        trailing?.invoke()
    }
}

@Composable
private fun ToolbarCustomizeDialog(
    layout: ToolbarLayoutStore,
    onDismiss: () -> Unit,
) {
    var label by remember { mutableStateOf("") }
    var text by remember { mutableStateOf("") }
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(12.dp)) {
            Column(
                modifier = Modifier
                    .heightIn(max = 520.dp)
                    .verticalScroll(rememberScrollState())
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text("Toolbar Keys", style = MaterialTheme.typography.titleMedium)
                Text("Main row", style = MaterialTheme.typography.labelLarge)
                layout.main.forEach { id ->
                    ToolbarEditLine(
                        title = layout.custom(id)?.label ?: ToolbarCatalog.spec(id).label,
                        onUp = { layout.move(id, "main", -1) },
                        onDown = { layout.move(id, "main", 1) },
                        onMove = { layout.moveTo(id, "main", "drawer0") },
                        moveLabel = "Drawer",
                        onHide = { layout.hide(id) },
                    )
                }
                layout.drawers.forEachIndexed { index, row ->
                    Text("Drawer ${index + 1}", style = MaterialTheme.typography.labelLarge)
                    row.forEach { id ->
                        ToolbarEditLine(
                            title = layout.custom(id)?.label ?: ToolbarCatalog.spec(id).label,
                            onUp = { layout.move(id, "drawer$index", -1) },
                            onDown = { layout.move(id, "drawer$index", 1) },
                            onMove = { layout.moveTo(id, "drawer$index", "main") },
                            moveLabel = "Main",
                            onHide = { layout.hide(id) },
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { layout.setDrawerRowCount(layout.drawers.size - 1) }) {
                        Text("Fewer rows")
                    }
                    Text("${layout.drawers.size}")
                    TextButton(onClick = { layout.setDrawerRowCount(layout.drawers.size + 1) }) {
                        Text("More rows")
                    }
                }
                TextButton(onClick = { layout.updateDrawerOpenByDefault(!layout.drawerOpenByDefault) }) {
                    Text(if (layout.drawerOpenByDefault) "Drawer starts open" else "Drawer starts closed")
                }
                TextButton(onClick = {
                    layout.updateDrawerToggleMode(if (layout.drawerToggleMode == "cycle") "stack" else "cycle")
                }) {
                    Text(if (layout.drawerToggleMode == "cycle") "More button: cycle" else "More button: stack")
                }
                OutlinedTextField(value = label, onValueChange = { label = it }, label = { Text("Custom label") })
                OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Text to send") })
                TextButton(onClick = {
                    layout.addCustom(label, text)
                    label = ""
                    text = ""
                }) { Text("Add custom key") }
                if (layout.hidden.isNotEmpty()) {
                    Text("Hidden", style = MaterialTheme.typography.labelLarge)
                    layout.hidden.forEach { id ->
                        TextButton(onClick = { layout.unhide(id) }) {
                            Text("Show ${layout.custom(id)?.label ?: ToolbarCatalog.spec(id).label}")
                        }
                    }
                }
                TextButton(onClick = { layout.reset() }) { Text("Reset to defaults") }
                TextButton(onClick = onDismiss) { Text("Done") }
            }
        }
    }
}

@Composable
private fun ToolbarEditLine(
    title: String,
    onUp: () -> Unit,
    onDown: () -> Unit,
    onMove: () -> Unit,
    moveLabel: String,
    onHide: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f), maxLines = 1)
        TextButton(onClick = onUp) { Text("Up") }
        TextButton(onClick = onDown) { Text("Down") }
        TextButton(onClick = onMove) { Text(moveLabel) }
        TextButton(onClick = onHide) { Text("Hide") }
    }
}

@Composable
private fun AccessoryKey(
    label: String,
    bgColor: Color,
    textColor: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    TextButton(
        onClick = onClick,
        modifier = modifier.height(32.dp).padding(0.dp),
        colors = ButtonDefaults.textButtonColors(
            containerColor = bgColor,
            contentColor = textColor
        ),
        contentPadding = PaddingValues(0.dp),
        shape = RoundedCornerShape(6.dp)
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            maxLines = 1
        )
    }
}
