package com.aspauldingcode.wawona

import android.content.Context
import android.text.InputType
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection

/* Linux input button codes */
private const val BTN_LEFT = 0x110
private const val BTN_RIGHT = 0x111

/**
 * A SurfaceView subclass that supports Android IME input (including emoji).
 *
 * When focused, the system IME can send text via our WawonaInputConnection,
 * which routes committed text and composition to the Wawona compositor
 * through JNI -> Rust -> Wayland text-input-v3.
 *
 * When "Enable Text Assist" is on, the view configures the IME for
 * autocorrect, text suggestions, auto-capitalize, and swipe-to-type.
 * When "Enable Dictation" is also on, voice input flags are included.
 *
 * Touchpad mode: 1-finger = pointer, tap = click, 2-finger drag = scroll.
 */
class WawonaSurfaceView(context: Context) : SurfaceView(context) {

    private val prefs = context.getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)
    private var touchpadFirstDownX = 0f
    private var touchpadFirstDownY = 0f
    private var touchpadFirstDownTime = 0L
    private var touchpadTwoFingerCenterX = 0f
    private var touchpadTwoFingerCenterY = 0f
    private var touchpadTwoFingerDownTime = 0L
    private var touchpadHadTwoFingers = false
    private var touchpadLastX = 0f
    private var touchpadLastY = 0f
    private val tapThresholdPx = 10
    private val tapThresholdMs = 300L

    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        val prefs = context.getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)
        val textAssist = prefs.getBoolean("enableTextAssist", false)
        val dictation = prefs.getBoolean("enableDictation", false)

        if (textAssist) {
            outAttrs.inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_AUTO_CORRECT or
                InputType.TYPE_TEXT_FLAG_AUTO_COMPLETE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or
                EditorInfo.IME_ACTION_UNSPECIFIED
            if (dictation) {
                outAttrs.imeOptions = outAttrs.imeOptions or
                    EditorInfo.IME_FLAG_NO_EXTRACT_UI
            }
        } else {
            outAttrs.inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or
                EditorInfo.IME_FLAG_NO_EXTRACT_UI
        }

        return WawonaInputConnection(this, true)
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN && !hasFocus()) {
            requestFocus()
        }

        val ts = (event.eventTime % Int.MAX_VALUE).toInt()
        val touchpadMode = prefs.getBoolean("touchpadMode", false)

        if (touchpadMode) {
            return handleTouchpadMode(event, ts)
        }

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val idx = event.actionIndex
                WawonaNative.nativeTouchDown(event.getPointerId(idx), event.getX(idx), event.getY(idx), ts)
                WawonaNative.nativeTouchFrame()
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                val idx = event.actionIndex
                WawonaNative.nativeTouchDown(event.getPointerId(idx), event.getX(idx), event.getY(idx), ts)
                WawonaNative.nativeTouchFrame()
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    WawonaNative.nativeTouchMotion(event.getPointerId(i), event.getX(i), event.getY(i), ts)
                }
                WawonaNative.nativeTouchFrame()
            }
            MotionEvent.ACTION_UP -> {
                val idx = event.actionIndex
                WawonaNative.nativeTouchUp(event.getPointerId(idx), ts)
                WawonaNative.nativeTouchFrame()
            }
            MotionEvent.ACTION_POINTER_UP -> {
                val idx = event.actionIndex
                WawonaNative.nativeTouchUp(event.getPointerId(idx), ts)
                WawonaNative.nativeTouchFrame()
            }
            MotionEvent.ACTION_CANCEL -> {
                WawonaNative.nativeTouchCancel()
            }
        }
        return true
    }

    private fun handleTouchpadMode(event: MotionEvent, ts: Int): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchpadFirstDownX = event.getX(0)
                touchpadFirstDownY = event.getY(0)
                touchpadFirstDownTime = event.eventTime
                touchpadHadTwoFingers = false
                touchpadLastX = event.getX(0)
                touchpadLastY = event.getY(0)
                WawonaNative.nativePointerEnter(event.getX(0).toDouble(), event.getY(0).toDouble(), ts)
                WawonaNative.nativePointerMotion(event.getX(0).toDouble(), event.getY(0).toDouble(), ts)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.pointerCount == 2) {
                    touchpadHadTwoFingers = true
                    touchpadTwoFingerCenterX = (event.getX(0) + event.getX(1)) / 2f
                    touchpadTwoFingerCenterY = (event.getY(0) + event.getY(1)) / 2f
                    touchpadTwoFingerDownTime = event.eventTime
                    touchpadLastX = touchpadTwoFingerCenterX
                    touchpadLastY = touchpadTwoFingerCenterY
                }
            }
            MotionEvent.ACTION_MOVE -> {
                when (event.pointerCount) {
                    1 -> {
                        WawonaNative.nativePointerMotion(event.getX(0).toDouble(), event.getY(0).toDouble(), ts)
                    }
                    2 -> {
                        val vscroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
                        val hscroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
                        if (vscroll != 0f || hscroll != 0f) {
                            if (vscroll != 0f) WawonaNative.nativePointerAxis(0, vscroll, ts)
                            if (hscroll != 0f) WawonaNative.nativePointerAxis(1, hscroll, ts)
                        } else {
                            val cx = (event.getX(0) + event.getX(1)) / 2f
                            val cy = (event.getY(0) + event.getY(1)) / 2f
                            val dx = cx - touchpadLastX
                            val dy = cy - touchpadLastY
                            touchpadLastX = cx
                            touchpadLastY = cy
                            if (dx != 0f || dy != 0f) {
                                WawonaNative.nativePointerAxis(0, -dy, ts)
                                WawonaNative.nativePointerAxis(1, dx, ts)
                            }
                        }
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                WawonaNative.nativePointerLeave(ts)
                if (touchpadHadTwoFingers) {
                    val x = event.getX(0)
                    val y = event.getY(0)
                    val dx = kotlin.math.abs(x - touchpadTwoFingerCenterX)
                    val dy = kotlin.math.abs(y - touchpadTwoFingerCenterY)
                    val dt = event.eventTime - touchpadTwoFingerDownTime
                    if (dx <= tapThresholdPx && dy <= tapThresholdPx && dt <= tapThresholdMs) {
                        WawonaNative.nativePointerButton(BTN_RIGHT, 1, ts)
                        WawonaNative.nativePointerButton(BTN_RIGHT, 0, ts + 1)
                    }
                } else {
                    val x = event.getX(0)
                    val y = event.getY(0)
                    val dx = kotlin.math.abs(x - touchpadFirstDownX)
                    val dy = kotlin.math.abs(y - touchpadFirstDownY)
                    val dt = event.eventTime - touchpadFirstDownTime
                    if (dx <= tapThresholdPx && dy <= tapThresholdPx && dt <= tapThresholdMs) {
                        WawonaNative.nativePointerButton(BTN_LEFT, 1, ts)
                        WawonaNative.nativePointerButton(BTN_LEFT, 0, ts + 1)
                    }
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (event.pointerCount == 2) {
                    val idx = event.actionIndex
                    val remaining = if (idx == 0) 1 else 0
                    touchpadLastX = event.getX(remaining)
                    touchpadLastY = event.getY(remaining)
                }
            }
            MotionEvent.ACTION_CANCEL -> WawonaNative.nativePointerLeave(ts)
        }
        return true
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        WawonaNative.nativeKeyEvent(keyCode, 1, (event.eventTime % Int.MAX_VALUE).toInt())
        if (!isModifierKeyCode(keyCode)) {
            ModifierState.clearStickyModifiers()
        }
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        WawonaNative.nativeKeyEvent(keyCode, 0, (event.eventTime % Int.MAX_VALUE).toInt())
        return true
    }

    private fun isModifierKeyCode(keyCode: Int): Boolean = when (keyCode) {
        KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT,
        KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_CTRL_RIGHT,
        KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_ALT_RIGHT,
        KeyEvent.KEYCODE_META_LEFT, KeyEvent.KEYCODE_META_RIGHT -> true
        else -> false
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_SCROLL && event.source and InputDevice.SOURCE_CLASS_POINTER != 0) {
            val vscroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
            val hscroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
            val ts = (event.eventTime % Int.MAX_VALUE).toInt()
            if (vscroll != 0f) {
                WawonaNative.nativePointerAxis(0, vscroll, ts)
            }
            if (hscroll != 0f) {
                WawonaNative.nativePointerAxis(1, hscroll, ts)
            }
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: android.graphics.Rect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        WawonaNative.nativeKeyboardFocus(gainFocus)
    }
}
