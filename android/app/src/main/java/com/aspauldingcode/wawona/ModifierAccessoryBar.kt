package com.aspauldingcode.wawona

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
    var shiftActive: Boolean = false
    var ctrlActive: Boolean = false
    var altActive: Boolean = false
    var superActive: Boolean = false

    fun hasActiveModifiers(): Boolean = shiftActive || ctrlActive || altActive || superActive

    fun clearStickyModifiers() {
        shiftActive = false
        ctrlActive = false
        altActive = false
        superActive = false
    }
}

private object XkbMod {
    const val SHIFT = 1 shl 0
    const val CTRL = 1 shl 2
    const val ALT = 1 shl 3
    const val LOGO = 1 shl 6
}

private const val DOUBLE_TAP_THRESHOLD_MS = 400L

private val letterKeycodes = intArrayOf(
    30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
    49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44
)

fun charToLinuxKeycode(ch: Char): LinuxKeyMapping? {
    return when {
        ch in 'a'..'z' -> LinuxKeyMapping(letterKeycodes[ch - 'a'])
        ch in 'A'..'Z' -> LinuxKeyMapping(letterKeycodes[ch - 'A'], needsShift = true)
        ch in '1'..'9' -> LinuxKeyMapping(LinuxKey.KEY_1 + (ch - '1'))
        ch == '0' -> LinuxKeyMapping(LinuxKey.KEY_0)
        else -> when (ch) {
            ' ' -> LinuxKeyMapping(LinuxKey.SPACE)
            '\n', '\r' -> LinuxKeyMapping(LinuxKey.ENTER)
            '\t' -> LinuxKeyMapping(LinuxKey.TAB)
            '-' -> LinuxKeyMapping(LinuxKey.MINUS)
            '=' -> LinuxKeyMapping(LinuxKey.EQUAL)
            '[' -> LinuxKeyMapping(LinuxKey.LEFTBRACE)
            ']' -> LinuxKeyMapping(LinuxKey.RIGHTBRACE)
            '\\' -> LinuxKeyMapping(LinuxKey.BACKSLASH)
            ';' -> LinuxKeyMapping(LinuxKey.SEMICOLON)
            '\'' -> LinuxKeyMapping(LinuxKey.APOSTROPHE)
            '`' -> LinuxKeyMapping(LinuxKey.GRAVE)
            ',' -> LinuxKeyMapping(LinuxKey.COMMA)
            '.' -> LinuxKeyMapping(LinuxKey.DOT)
            '/' -> LinuxKeyMapping(LinuxKey.SLASH)
            '!' -> LinuxKeyMapping(LinuxKey.KEY_1, true)
            '@' -> LinuxKeyMapping(LinuxKey.KEY_2, true)
            '#' -> LinuxKeyMapping(LinuxKey.KEY_3, true)
            '$' -> LinuxKeyMapping(LinuxKey.KEY_4, true)
            '%' -> LinuxKeyMapping(LinuxKey.KEY_5, true)
            '^' -> LinuxKeyMapping(LinuxKey.KEY_6, true)
            '&' -> LinuxKeyMapping(LinuxKey.KEY_7, true)
            '*' -> LinuxKeyMapping(LinuxKey.KEY_8, true)
            '(' -> LinuxKeyMapping(LinuxKey.KEY_9, true)
            ')' -> LinuxKeyMapping(LinuxKey.KEY_0, true)
            '_' -> LinuxKeyMapping(LinuxKey.MINUS, true)
            '+' -> LinuxKeyMapping(LinuxKey.EQUAL, true)
            '{' -> LinuxKeyMapping(LinuxKey.LEFTBRACE, true)
            '}' -> LinuxKeyMapping(LinuxKey.RIGHTBRACE, true)
            '|' -> LinuxKeyMapping(LinuxKey.BACKSLASH, true)
            ':' -> LinuxKeyMapping(LinuxKey.SEMICOLON, true)
            '"' -> LinuxKeyMapping(LinuxKey.APOSTROPHE, true)
            '~' -> LinuxKeyMapping(LinuxKey.GRAVE, true)
            '<' -> LinuxKeyMapping(LinuxKey.COMMA, true)
            '>' -> LinuxKeyMapping(LinuxKey.DOT, true)
            '?' -> LinuxKeyMapping(LinuxKey.SLASH, true)
            else -> null
        }
    }
}

@Composable
fun ModifierAccessoryBar(
    modifier: Modifier = Modifier,
    onDismissKeyboard: () -> Unit
) {
    val ts = System.currentTimeMillis().toInt() and 0x7FFF_FFFF

    var modShiftActive by remember { mutableStateOf(false) }
    var modShiftLocked by remember { mutableStateOf(false) }
    var modCtrlActive by remember { mutableStateOf(false) }
    var modCtrlLocked by remember { mutableStateOf(false) }
    var modAltActive by remember { mutableStateOf(false) }
    var modAltLocked by remember { mutableStateOf(false) }
    var modSuperActive by remember { mutableStateOf(false) }
    var modSuperLocked by remember { mutableStateOf(false) }

    var lastModShiftTap by remember { mutableLongStateOf(0L) }
    var lastModCtrlTap by remember { mutableLongStateOf(0L) }
    var lastModAltTap by remember { mutableLongStateOf(0L) }
    var lastModSuperTap by remember { mutableLongStateOf(0L) }

    fun clearStickyModifiers() {
        if (modShiftActive && !modShiftLocked) modShiftActive = false
        if (modCtrlActive && !modCtrlLocked) modCtrlActive = false
        if (modAltActive && !modAltLocked) modAltActive = false
        if (modSuperActive && !modSuperLocked) modSuperActive = false
        ModifierState.shiftActive = modShiftActive
        ModifierState.ctrlActive = modCtrlActive
        ModifierState.altActive = modAltActive
        ModifierState.superActive = modSuperActive
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

        ModifierState.shiftActive = modShiftActive
        ModifierState.ctrlActive = modCtrlActive
        ModifierState.altActive = modAltActive
        ModifierState.superActive = modSuperActive
    }

    fun sendAccessoryKey(keycode: Int) {
        var mods = 0
        if (modShiftActive) {
            mods = mods or XkbMod.SHIFT
            WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, true, ts)
        }
        if (modCtrlActive) {
            mods = mods or XkbMod.CTRL
            WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, true, ts)
        }
        if (modAltActive) {
            mods = mods or XkbMod.ALT
            WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, true, ts)
        }
        if (modSuperActive) {
            mods = mods or XkbMod.LOGO
            WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, true, ts)
        }
        if (mods != 0) {
            WawonaNative.nativeInjectModifiers(mods, 0, 0, 0)
        }
        WawonaNative.nativeInjectKey(keycode, true, ts)
        WawonaNative.nativeInjectKey(keycode, false, ts)
        if (modShiftActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, false, ts)
        if (modCtrlActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, false, ts)
        if (modAltActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, false, ts)
        if (modSuperActive) WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, false, ts)
        if (mods != 0) WawonaNative.nativeInjectModifiers(0, 0, 0, 0)
        clearStickyModifiers()
    }

    val barBg = Color(0xFF1C1C1E)
    val keyInactive = Color(0xFF3A3A3C)
    val keySticky = Color(0xFF0A84FF).copy(alpha = 0.6f)
    val keyLocked = Color(0xFF0A84FF).copy(alpha = 0.85f)
    val keyText = Color.White

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = barBg,
        contentColor = keyText
    ) {
        val rowMod = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 2.dp)
            .height(36.dp)

        Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = rowMod,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            listOf(
                "ESC" to { sendAccessoryKey(LinuxKey.ESC) },
                "`" to { sendAccessoryKey(LinuxKey.GRAVE) },
                "TAB" to { sendAccessoryKey(LinuxKey.TAB) },
                "/" to { sendAccessoryKey(LinuxKey.SLASH) },
                "—" to { sendAccessoryKey(LinuxKey.MINUS) },
                "HOME" to { sendAccessoryKey(LinuxKey.HOME) },
                "↑" to { sendAccessoryKey(LinuxKey.UP) },
                "END" to { sendAccessoryKey(LinuxKey.END) },
                "PGUP" to { sendAccessoryKey(LinuxKey.PAGEUP) }
            ).forEach { (label, action) ->
                AccessoryKey(
                    label, keyInactive, keyText,
                    onClick = { action() },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        Row(
            modifier = rowMod,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AccessoryModKey(
                label = "⇧",
                active = modShiftActive,
                locked = modShiftLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modShiftActive, modShiftLocked, lastModShiftTap,
                    { modShiftActive = it },
                    { modShiftLocked = it },
                    { lastModShiftTap = it }
                )
            }
            AccessoryModKey(
                label = "CTRL",
                active = modCtrlActive,
                locked = modCtrlLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modCtrlActive, modCtrlLocked, lastModCtrlTap,
                    { modCtrlActive = it },
                    { modCtrlLocked = it },
                    { lastModCtrlTap = it }
                )
            }
            AccessoryModKey(
                label = "ALT",
                active = modAltActive,
                locked = modAltLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modAltActive, modAltLocked, lastModAltTap,
                    { modAltActive = it },
                    { modAltLocked = it },
                    { lastModAltTap = it }
                )
            }
            AccessoryModKey(
                label = "⌘",
                active = modSuperActive,
                locked = modSuperLocked,
                inactiveColor = keyInactive,
                stickyColor = keySticky,
                lockedColor = keyLocked
            ) {
                handleModifierTap(
                    modSuperActive, modSuperLocked, lastModSuperTap,
                    { modSuperActive = it },
                    { modSuperLocked = it },
                    { lastModSuperTap = it }
                )
            }
            listOf(
                "←" to LinuxKey.LEFT,
                "↓" to LinuxKey.DOWN,
                "→" to LinuxKey.RIGHT,
                "PGDN" to LinuxKey.PAGEDOWN
            ).forEach { (label, keycode) ->
                AccessoryKey(
                    label, keyInactive, keyText,
                    onClick = { sendAccessoryKey(keycode) },
                    modifier = Modifier.weight(1f)
                )
            }
            AccessoryKey(
                "⌨↓", keyInactive, keyText,
                onClick = onDismissKeyboard,
                modifier = Modifier.weight(1f)
            )
        }
        }
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

@Composable
private fun RowScope.AccessoryModKey(
    label: String,
    active: Boolean,
    locked: Boolean,
    inactiveColor: Color,
    stickyColor: Color,
    lockedColor: Color,
    onClick: () -> Unit
) {
    val bg = when {
        locked -> lockedColor
        active -> stickyColor
        else -> inactiveColor
    }
    val borderMod = if (locked) {
        Modifier.border(2.dp, Color(0xFF0A84FF), RoundedCornerShape(6.dp))
    } else {
        Modifier
    }
    Box(modifier = Modifier.weight(1f).then(borderMod)) {
        AccessoryKey(
            label, bg, Color.White,
            onClick = onClick,
            modifier = Modifier.fillMaxWidth()
        )
    }
}
