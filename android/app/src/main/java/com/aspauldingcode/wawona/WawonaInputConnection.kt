package com.aspauldingcode.wawona

import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.CorrectionInfo
import android.view.inputmethod.CursorAnchorInfo
import android.view.inputmethod.InputConnection

/**
 * InputConnection that routes Android IME text (including emoji) to the
 * Wawona compositor via JNI → Rust → Wayland text-input-v3.
 *
 * The system IME calls commitText() for committed text (including emoji
 * selections), setComposingText() for pre-edit / composition, and
 * deleteSurroundingText() for backspace-like operations.
 *
 * When Text Assist is enabled, the IME also sends autocorrections via
 * commitCorrection() and richer composition sequences.
 *
 * Modifier integration: when ModifierState has active modifiers from the
 * accessory bar, commitText() converts mappable characters to key events
 * wrapped with modifier press/release — matching iOS insertText: behavior.
 * Sticky (one-shot) modifiers are cleared after the keypress.
 */
class WawonaInputConnection(
    private val view: View,
    fullEditor: Boolean
) : BaseInputConnection(view, fullEditor) {

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
        if (text == null || text.isEmpty()) return true
        WLog.d("INPUT", "commitText: \"$text\" cursorPos=$newCursorPosition")

        if (ModifierState.hasActiveModifiers()) {
            return commitTextWithModifiers(text.toString(), newCursorPosition)
        }

        WawonaNative.nativePreeditText("", 0, 0)
        WawonaNative.nativeCommitText(text.toString())
        super.commitText(text, newCursorPosition)
        return true
    }

    /**
     * When accessory-bar modifiers are active, convert mappable characters to
     * key events wrapped with modifier key press/release (mirrors iOS
     * insertText: legacy key-event path). Unmappable text (emoji, CJK) falls
     * back to text-input-v3.
     *
     * Modifier state is driven entirely by injecting the modifier key
     * press/release — the Rust core's XKB state machine (update_key) handles
     * the depressed/latched/locked mask automatically.  We intentionally do
     * NOT call nativeInjectModifiers here to avoid mixing update_mask with
     * update_key, which xkbcommon explicitly warns against.
     */
    private fun commitTextWithModifiers(text: String, newCursorPosition: Int): Boolean {
        val ts = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()

        val allMappable = text.all { ch ->
            !Character.isHighSurrogate(ch) &&
            !Character.isLowSurrogate(ch) &&
            charToLinuxKeycode(ch) != null
        }

        if (!allMappable) {
            WLog.d("INPUT", "Modifiers active but text unmappable, committing via text-input-v3")
            WawonaNative.nativePreeditText("", 0, 0)
            WawonaNative.nativeCommitText(text)
            super.commitText(text, newCursorPosition)
            ModifierState.clearStickyModifiers()
            return true
        }

        WawonaNative.nativePreeditText("", 0, 0)

        if (ModifierState.shiftActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, true, ts)
        if (ModifierState.ctrlActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, true, ts)
        if (ModifierState.altActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, true, ts)
        if (ModifierState.superActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, true, ts)

        for (ch in text) {
            val mapping = charToLinuxKeycode(ch) ?: continue
            val extraShift = mapping.needsShift && !ModifierState.shiftActive
            if (extraShift)
                WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, true, ts)
            WawonaNative.nativeInjectKey(mapping.keycode, true, ts)
            WawonaNative.nativeInjectKey(mapping.keycode, false, ts)
            if (extraShift)
                WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, false, ts)
        }

        if (ModifierState.shiftActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTSHIFT, false, ts)
        if (ModifierState.ctrlActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTCTRL, false, ts)
        if (ModifierState.altActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTALT, false, ts)
        if (ModifierState.superActive)
            WawonaNative.nativeInjectKey(LinuxKey.LEFTMETA, false, ts)

        super.commitText(text, newCursorPosition)
        ModifierState.clearStickyModifiers()
        return true
    }

    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
        val str = text?.toString() ?: ""
        WLog.d("INPUT", "setComposingText: \"$str\" cursorPos=$newCursorPosition")
        WawonaNative.nativePreeditText(str, 0, str.length)
        super.setComposingText(text, newCursorPosition)
        return true
    }

    override fun finishComposingText(): Boolean {
        WLog.d("INPUT", "finishComposingText")
        WawonaNative.nativePreeditText("", 0, 0)
        super.finishComposingText()
        return true
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
        WLog.d("INPUT", "deleteSurroundingText: before=$beforeLength after=$afterLength")
        WawonaNative.nativeDeleteSurroundingText(beforeLength, afterLength)
        if (beforeLength > 0 || afterLength > 0) {
            val ts = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            repeat(beforeLength) {
                WawonaNative.nativeInjectKey(14, true, ts)   // KEY_BACKSPACE
                WawonaNative.nativeInjectKey(14, false, ts)
            }
            repeat(afterLength) {
                WawonaNative.nativeInjectKey(111, true, ts)   // KEY_DELETE (forward)
                WawonaNative.nativeInjectKey(111, false, ts)
            }
        }
        super.deleteSurroundingText(beforeLength, afterLength)
        ModifierState.clearStickyModifiers()
        return true
    }

    override fun sendKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DEL -> {
                    WLog.d("INPUT", "sendKeyEvent: backspace")
                    WawonaNative.nativeDeleteSurroundingText(1, 0)
                    val ts = (event.eventTime % Int.MAX_VALUE).toInt()
                    WawonaNative.nativeInjectKey(14, true, ts)
                    WawonaNative.nativeInjectKey(14, false, ts)
                    super.deleteSurroundingText(1, 0)
                    ModifierState.clearStickyModifiers()
                    return true
                }
                KeyEvent.KEYCODE_FORWARD_DEL -> {
                    WLog.d("INPUT", "sendKeyEvent: forward delete")
                    WawonaNative.nativeDeleteSurroundingText(0, 1)
                    val ts = (event.eventTime % Int.MAX_VALUE).toInt()
                    WawonaNative.nativeInjectKey(111, true, ts)
                    WawonaNative.nativeInjectKey(111, false, ts)
                    super.deleteSurroundingText(0, 1)
                    ModifierState.clearStickyModifiers()
                    return true
                }
            }
        } else if (event.action == KeyEvent.ACTION_UP) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> return true
            }
        }
        return super.sendKeyEvent(event)
    }

    override fun commitCorrection(correctionInfo: CorrectionInfo?): Boolean {
        if (correctionInfo == null) return true
        val oldText = correctionInfo.oldText?.toString() ?: return true
        val newText = correctionInfo.newText?.toString() ?: return true
        WLog.d("INPUT", "commitCorrection: \"$oldText\" -> \"$newText\" at offset=${correctionInfo.offset}")

        val deleteLen = oldText.length
        if (deleteLen > 0) {
            WawonaNative.nativeDeleteSurroundingText(deleteLen, 0)
            super.deleteSurroundingText(deleteLen, 0)
        }
        WawonaNative.nativeCommitText(newText)
        super.commitText(newText, 1)
        return true
    }

    override fun performEditorAction(editorAction: Int): Boolean {
        WLog.d("INPUT", "performEditorAction: $editorAction")
        return super.performEditorAction(editorAction)
    }

    override fun requestCursorUpdates(cursorUpdateMode: Int): Boolean {
        WLog.d("INPUT", "requestCursorUpdates: mode=$cursorUpdateMode")
        if (cursorUpdateMode and InputConnection.CURSOR_UPDATE_IMMEDIATE != 0) {
            reportCursorAnchorInfo()
        }
        return true
    }

    private fun reportCursorAnchorInfo() {
        val rect = IntArray(4)
        WawonaNative.nativeGetCursorRect(rect)
        val info = CursorAnchorInfo.Builder()
            .setInsertionMarkerLocation(
                rect[0].toFloat(),
                rect[1].toFloat(),
                (rect[1] + rect[3]).toFloat(),
                (rect[1] + rect[3]).toFloat(),
                CursorAnchorInfo.FLAG_HAS_VISIBLE_REGION
            )
            .build()
        val imm = view.context.getSystemService(
            android.content.Context.INPUT_METHOD_SERVICE
        ) as? android.view.inputmethod.InputMethodManager
        imm?.updateCursorAnchorInfo(view, info)
    }
}
