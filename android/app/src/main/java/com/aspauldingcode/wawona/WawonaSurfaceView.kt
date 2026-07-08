package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
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

private const val TAP_MOVEMENT_PX = 12f
private const val TAP_DURATION_MS = 300L
private const val TOUCHPAD_SENSITIVITY = 1.5f
private const val SCROLL_SENSITIVITY = 12f
private const val DRAG_ARM_SHOW_MS = 500L
private const val DRAG_ENGAGE_MS = 1000L

/**
 * A SurfaceView subclass that supports Android IME input (including emoji).
 *
 * Touchpad mode mirrors iOS: relative pointer with a persistent virtual
 * cursor, tap-to-click at the cursor, two-finger scroll/tap, and a
 * press-and-hold radial dial for click-drag.
 */
class WawonaSurfaceView(context: Context) : SurfaceView(context) {

    private val prefs = context.getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var touchpadOverlay: TouchpadOverlayView? = null

    private var lastSyncedLayoutW = 0
    private var lastSyncedLayoutH = 0

    // Direct-touch scroll tracking
    private var directScrollLastX = 0f
    private var directScrollLastY = 0f

    // Touchpad virtual pointer (view coordinates, persists across gestures)
    private var virtualPointerX = 0f
    private var virtualPointerY = 0f
    private var pointerInitialized = false
    private var pointerEntered = false
    private var activeFingerCount = 0
    private var maxFingerCount = 0
    private var scrollActive = false
    private var totalMovement = 0f
    private var gestureStartTime = 0L
    private var prevTouchX = 0f
    private var prevTouchY = 0f
    private var prevScrollCenterX = 0f
    private var prevScrollCenterY = 0f
    private var twoFingerDownTime = 0L
    private var twoFingerCenterX = 0f
    private var twoFingerCenterY = 0f
    private var dragging = false
    private var dragGeneration = 0
    private var engageDragRunnable: Runnable? = null
    private var radialAnimator: Runnable? = null
    private var radialAnimStartMs = 0L

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        when (key) {
            "touchpadMode", "renderMacOSPointer" -> {
                post { updateOverlayCursorVisibility() }
            }
        }
    }

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        contentDescription =
            "Wayland application surface. Touch interacts directly with the application."
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        prefs.registerOnSharedPreferenceChangeListener(prefListener)
    }

    override fun onDetachedFromWindow() {
        prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        cancelDragArm()
        super.onDetachedFromWindow()
    }

    fun bindTouchpadOverlay(overlay: TouchpadOverlayView) {
        touchpadOverlay = overlay
        updateOverlayCursorVisibility()
    }

    private fun touchpadModeEnabled(): Boolean = prefs.getBoolean("touchpadMode", false)

    private fun virtualPointerEnabled(): Boolean =
        prefs.getBoolean("renderMacOSPointer", false)

    private fun ensureVirtualPointer() {
        if (!pointerInitialized && width > 0 && height > 0) {
            virtualPointerX = width / 2f
            virtualPointerY = height / 2f
            pointerInitialized = true
            touchpadOverlay?.setCursorPosition(virtualPointerX, virtualPointerY)
        }
    }

    private fun updateOverlayCursorVisibility() {
        val show = touchpadModeEnabled() && virtualPointerEnabled()
        touchpadOverlay?.setCursorVisible(show)
        if (show) {
            touchpadOverlay?.setCursorPosition(virtualPointerX, virtualPointerY)
        } else {
            touchpadOverlay?.setRadialDial(false)
        }
    }

    private fun clampPointer() {
        if (width <= 0 || height <= 0) return
        virtualPointerX = virtualPointerX.coerceIn(0f, width.toFloat())
        virtualPointerY = virtualPointerY.coerceIn(0f, height.toFloat())
    }

    private fun syncPointer(ts: Int) {
        if (!pointerEntered) {
            WawonaNative.nativePointerEnter(virtualPointerX.toDouble(), virtualPointerY.toDouble(), ts)
            pointerEntered = true
        } else {
            WawonaNative.nativePointerMotion(virtualPointerX.toDouble(), virtualPointerY.toDouble(), ts)
        }
    }

    private fun leavePointer(ts: Int) {
        if (pointerEntered) {
            WawonaNative.nativePointerLeave(ts)
            pointerEntered = false
        }
    }

    private fun clickAtPointer(button: Int, ts: Int) {
        syncPointer(ts)
        WawonaNative.nativePointerButton(button, 1, ts)
        WawonaNative.nativePointerButton(button, 0, ts + 1)
    }

    private fun cancelDragArm() {
        dragGeneration++
        radialAnimator?.let { mainHandler.removeCallbacks(it) }
        engageDragRunnable?.let { mainHandler.removeCallbacks(it) }
        radialAnimator = null
        engageDragRunnable = null
        touchpadOverlay?.setRadialDial(false)
    }

    private fun scheduleDragArm() {
        cancelDragArm()
        val gen = dragGeneration
        radialAnimStartMs = System.currentTimeMillis()
        radialAnimator = object : Runnable {
            override fun run() {
                if (gen != dragGeneration || activeFingerCount != 1 || scrollActive || dragging) return
                if (totalMovement >= TAP_MOVEMENT_PX) return
                val elapsed = System.currentTimeMillis() - radialAnimStartMs
                if (elapsed < DRAG_ARM_SHOW_MS) {
                    mainHandler.postDelayed(this, 16)
                    return
                }
                val progress =
                    ((elapsed - DRAG_ARM_SHOW_MS).toFloat() / (DRAG_ENGAGE_MS - DRAG_ARM_SHOW_MS))
                        .coerceIn(0f, 1f)
                touchpadOverlay?.setRadialDial(true, progress)
                if (elapsed < DRAG_ENGAGE_MS) {
                    mainHandler.postDelayed(this, 16)
                }
            }
        }
        mainHandler.post(radialAnimator!!)
        engageDragRunnable = Runnable {
            if (gen != dragGeneration || activeFingerCount != 1 || scrollActive || dragging) return@Runnable
            if (totalMovement >= TAP_MOVEMENT_PX) return@Runnable
            dragging = true
            touchpadOverlay?.setRadialDial(false)
            syncPointer((System.currentTimeMillis() % Int.MAX_VALUE).toInt())
            WawonaNative.nativePointerButton(
                BTN_LEFT,
                1,
                (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            )
        }
        mainHandler.postDelayed(engageDragRunnable!!, DRAG_ENGAGE_MS)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val w = right - left
        val h = bottom - top
        if (w <= 0 || h <= 0) return
        ensureVirtualPointer()
        updateOverlayCursorVisibility()
        if (w == lastSyncedLayoutW && h == lastSyncedLayoutH) return
        lastSyncedLayoutW = w
        lastSyncedLayoutH = h
        try {
            WawonaNative.nativeSyncOutputSize(w, h)
            WawonaSettings.apply(prefs)
        } catch (_: Exception) {
        }
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
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
        if (touchpadModeEnabled()) {
            return handleTouchpadMode(event, ts)
        }

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val idx = event.actionIndex
                WawonaNative.nativeTouchDown(event.getPointerId(idx), event.getX(idx), event.getY(idx), ts)
                WawonaNative.nativeTouchFrame()
                directScrollLastX = event.getX(idx)
                directScrollLastY = event.getY(idx)
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
                if (event.pointerCount == 1) {
                    val dx = event.getX(0) - directScrollLastX
                    val dy = event.getY(0) - directScrollLastY
                    directScrollLastX = event.getX(0)
                    directScrollLastY = event.getY(0)
                    if (dy != 0f) WawonaNative.nativePointerAxis(0, -dy, ts)
                    if (dx != 0f) WawonaNative.nativePointerAxis(1, -dx, ts)
                }
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
            MotionEvent.ACTION_CANCEL -> WawonaNative.nativeTouchCancel()
        }
        return true
    }

    private fun handleTouchpadMode(event: MotionEvent, ts: Int): Boolean {
        ensureVirtualPointer()
        updateOverlayCursorVisibility()

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                activeFingerCount = 1
                maxFingerCount = 1
                scrollActive = false
                totalMovement = 0f
                gestureStartTime = event.eventTime
                prevTouchX = event.getX(0)
                prevTouchY = event.getY(0)
                dragging = false
                scheduleDragArm()
                syncPointer(ts)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                activeFingerCount = event.pointerCount
                if (activeFingerCount > maxFingerCount) maxFingerCount = activeFingerCount
                if (activeFingerCount >= 2) {
                    cancelDragArm()
                    prevScrollCenterX = (event.getX(0) + event.getX(1)) / 2f
                    prevScrollCenterY = (event.getY(0) + event.getY(1)) / 2f
                    twoFingerCenterX = prevScrollCenterX
                    twoFingerCenterY = prevScrollCenterY
                    twoFingerDownTime = event.eventTime
                    syncPointer(ts)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                when {
                    event.pointerCount >= 2 -> {
                        scrollActive = true
                        cancelDragArm()
                        val cx = (event.getX(0) + event.getX(1)) / 2f
                        val cy = (event.getY(0) + event.getY(1)) / 2f
                        val dx = (cx - prevScrollCenterX) * SCROLL_SENSITIVITY
                        val dy = (cy - prevScrollCenterY) * SCROLL_SENSITIVITY
                        prevScrollCenterX = cx
                        prevScrollCenterY = cy
                        totalMovement += kotlin.math.abs(dx) + kotlin.math.abs(dy)
                        syncPointer(ts)
                        if (kotlin.math.abs(dy) > 0.5f) {
                            WawonaNative.nativePointerAxis(0, -dy, ts)
                        }
                        if (kotlin.math.abs(dx) > 0.5f) {
                            WawonaNative.nativePointerAxis(1, dx, ts)
                        }
                    }
                    event.pointerCount == 1 -> {
                        val x = event.getX(0)
                        val y = event.getY(0)
                        val dx = (x - prevTouchX) * TOUCHPAD_SENSITIVITY
                        val dy = (y - prevTouchY) * TOUCHPAD_SENSITIVITY
                        prevTouchX = x
                        prevTouchY = y
                        totalMovement += kotlin.math.abs(dx) + kotlin.math.abs(dy)
                        if (!dragging && totalMovement >= TAP_MOVEMENT_PX) {
                            cancelDragArm()
                        }
                        virtualPointerX += dx
                        virtualPointerY += dy
                        clampPointer()
                        touchpadOverlay?.setCursorPosition(virtualPointerX, virtualPointerY)
                        syncPointer(ts)
                    }
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                activeFingerCount = event.pointerCount - 1
            }
            MotionEvent.ACTION_UP -> {
                val remaining = 0
                val gestureEnding = remaining <= 0
                val duration = event.eventTime - gestureStartTime
                val lowMovement = totalMovement < TAP_MOVEMENT_PX
                val shortTap = lowMovement && duration < TAP_DURATION_MS

                if (dragging) {
                    syncPointer(ts)
                    WawonaNative.nativePointerButton(BTN_LEFT, 0, ts)
                    dragging = false
                } else if (gestureEnding && !scrollActive && lowMovement && shortTap && maxFingerCount >= 2) {
                    clickAtPointer(BTN_RIGHT, ts)
                } else if (gestureEnding && !scrollActive && shortTap && maxFingerCount <= 1) {
                    clickAtPointer(BTN_LEFT, ts)
                }

                cancelDragArm()
                if (gestureEnding) {
                    scrollActive = false
                    maxFingerCount = 0
                    // Keep pointer entered between gestures (matches iOS touchpad).
                }
                activeFingerCount = 0
            }
            MotionEvent.ACTION_CANCEL -> {
                if (dragging) {
                    WawonaNative.nativePointerButton(
                        BTN_LEFT,
                        0,
                        (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                    )
                    dragging = false
                }
                cancelDragArm()
                scrollActive = false
                activeFingerCount = 0
                maxFingerCount = 0
                leavePointer(ts)
            }
        }
        return true
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> {
                ModifierState.syncShiftFromNative(active = true, locked = ModifierState.shiftLocked)
            }
            KeyEvent.KEYCODE_CAPS_LOCK -> {
                val lockNow = !ModifierState.shiftLocked
                ModifierState.syncShiftFromNative(active = lockNow, locked = lockNow)
            }
        }
        WawonaNative.nativeKeyEvent(keyCode, 1, (event.eventTime % Int.MAX_VALUE).toInt())
        if (!isModifierKeyCode(keyCode)) {
            val hardwareShiftHeld = event.isShiftPressed ||
                (event.metaState and KeyEvent.META_SHIFT_ON) != 0
            if (!hardwareShiftHeld || ModifierState.shiftLocked) {
                ModifierState.clearStickyModifiers()
            }
        }
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> {
                if (!ModifierState.shiftLocked) {
                    ModifierState.syncShiftFromNative(active = false, locked = false)
                }
            }
        }
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
        if (event.action == MotionEvent.ACTION_SCROLL &&
            event.source and InputDevice.SOURCE_CLASS_POINTER != 0
        ) {
            val vscroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
            val hscroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
            val ts = (event.eventTime % Int.MAX_VALUE).toInt()
            if (vscroll != 0f) WawonaNative.nativePointerAxis(0, vscroll, ts)
            if (hscroll != 0f) WawonaNative.nativePointerAxis(1, hscroll, ts)
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: android.graphics.Rect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        WawonaNative.nativeKeyboardFocus(gainFocus)
    }
}
