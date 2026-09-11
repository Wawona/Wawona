package com.aspauldingcode.wawona

import android.view.KeyCharacterMap
import android.view.KeyEvent

/**
 * Dump the host [KeyCharacterMap] into HostKeymapBridge.
 *
 * Not a locale-to-RMLVO table. Wawona does not catalog languages.
 * Nested weston/niri still compile the trimmed us/evdev tree.
 */
object KeyboardLayouts {
    private const val COMBINING = KeyCharacterMap.COMBINING_ACCENT
    private const val COMBINING_MASK = KeyCharacterMap.COMBINING_ACCENT_MASK

    fun applyHostKeymap() {
        val kcm = try {
            KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD)
        } catch (_: Throwable) {
            KeyCharacterMap.load(KeyCharacterMap.BUILT_IN_KEYBOARD)
        }
        val ids = ArrayList<Int>(80)
        val levels = ArrayList<Int>(80 * 4)
        for (code in 0..84) {
            val none = decode(kcm.get(code, 0))
            val shift = decode(kcm.get(code, KeyEvent.META_SHIFT_ON))
            val alt = decode(kcm.get(code, KeyEvent.META_ALT_ON))
            val shiftAlt = decode(
                kcm.get(code, KeyEvent.META_SHIFT_ON or KeyEvent.META_ALT_ON)
            )
            if (none == 0 && shift == 0) {
                continue
            }
            ids.add(code)
            levels.add(none)
            levels.add(shift)
            levels.add(alt)
            levels.add(shiftAlt)
        }
        if (ids.isEmpty()) {
            WLog.w("XKB", "KeyCharacterMap dump empty; seat stays US fallback")
            return
        }
        WawonaNative.nativeApplyHostKeyLevels(
            ids.toIntArray(),
            levels.toIntArray(),
        )
        WLog.i("XKB", "host dump: applied ${ids.size} keys from KeyCharacterMap")
    }

    private fun decode(raw: Int): Int {
        if (raw == 0) {
            return 0
        }
        if ((raw and COMBINING) != 0) {
            return raw and COMBINING_MASK
        }
        return raw
    }
}
