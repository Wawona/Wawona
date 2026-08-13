package com.aspauldingcode.wawona

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import java.util.UUID

/**
 * One optional Android host task for one Wayland toplevel.
 *
 * MainActivity remains Wawona's single-task HOME surface. Every Android 7+
 * machine launch gets a separate task; Android decides whether that task is
 * fullscreen, split, freeform, or on an external display. The native claim is
 * reserved before client launch, then atomically bound to the first toplevel.
 *
 * Soft OSK for terminals lives here (not in MainActivity): when a host task
 * owns the surface, Machines stays up and MainActivity's IME loop never runs
 * (issue #141).
 */
class SessionActivity : Activity(), SurfaceHolder.Callback {
    private var hostId = 0L
    private lateinit var surfaceView: WawonaSurfaceView
    private val resizeHandler = Handler(Looper.getMainLooper())
    private val imeHandler = Handler(Looper.getMainLooper())
    private var pendingResize: Runnable? = null
    private var pendingResizeAttempts = 0
    private var lastTextEntryWanted: Boolean? = null
    private var imePollActive = false

    private val imePollRunnable = object : Runnable {
        override fun run() {
            if (!imePollActive || isFinishing) return
            try {
                syncSoftKeyboard()
            } catch (e: Exception) {
                WLog.e("SESSION", "IME poll failed: ${e.message}")
            }
            imeHandler.postDelayed(this, IME_POLL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hostId = savedInstanceState?.getLong(EXTRA_HOST_ID)
            ?: intent.getLongExtra(EXTRA_HOST_ID, newHostId())
        title = intent.getStringExtra(EXTRA_TITLE) ?: getString(R.string.app_name)

        surfaceView = WawonaSurfaceView(this)
        surfaceView.holder.addCallback(this)
        SessionActivityRegistry.register(this, hostId)
        setContentView(
            FrameLayout(this).apply {
                addView(
                    surfaceView,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            },
        )
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putLong(EXTRA_HOST_ID, hostId)
        super.onSaveInstanceState(outState)
    }

    override fun onResume() {
        super.onResume()
        WawonaNative.nativeSetHostWindowFocused(hostToken(), true)
        scheduleResize()
        startImePoll()
    }

    override fun onPause() {
        stopImePoll()
        hideSoftKeyboard()
        WawonaNative.nativeSetHostWindowFocused(hostToken(), false)
        super.onPause()
    }

    override fun onDestroy() {
        pendingResize?.let(resizeHandler::removeCallbacks)
        stopImePoll()
        if (isFinishing) {
            WawonaNative.nativeCloseHostWindow(hostToken())
            WawonaNative.nativeReleaseHostWindow(hostToken())
        }
        SessionActivityRegistry.release(this)
        super.onDestroy()
    }

    fun moveHostTaskToFront() {
        val activityManager = getSystemService(ActivityManager::class.java)
        activityManager.appTasks
            .firstOrNull { it.taskInfo.taskId == taskId }
            ?.moveToFront()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        scheduleResize()
        // External keyboard attach/detach — re-evaluate soft OSK.
        lastTextEntryWanted = null
        syncSoftKeyboard()
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean) {
        super.onMultiWindowModeChanged(isInMultiWindowMode)
        scheduleResize()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        WawonaNative.nativeSetSurface(holder.surface)
        surfaceView.requestFocus()
        startImePoll()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        scheduleResize(width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        pendingResize?.let(resizeHandler::removeCallbacks)
        pendingResize = null
        // Pass the dying Surface so a newer host task's swapchain is not torn down (#141).
        WawonaNative.nativeDestroySurface(holder.surface)
    }

    private fun startImePoll() {
        if (imePollActive) return
        imePollActive = true
        lastTextEntryWanted = null
        imeHandler.removeCallbacks(imePollRunnable)
        imeHandler.post(imePollRunnable)
    }

    private fun stopImePoll() {
        imePollActive = false
        imeHandler.removeCallbacks(imePollRunnable)
    }

    private fun syncSoftKeyboard() {
        if (hasRealExternalKeyboard(resources.configuration)) {
            if (lastTextEntryWanted != false) {
                hideSoftKeyboard()
                lastTextEntryWanted = false
            }
            return
        }
        val wanted = try {
            WawonaNative.nativeTextEntryWanted()
        } catch (_: Exception) {
            false
        }
        if (lastTextEntryWanted != null && wanted == lastTextEntryWanted) return
        lastTextEntryWanted = wanted
        if (wanted) {
            surfaceView.restartInputForContentType()
            showSoftKeyboard()
        } else {
            hideSoftKeyboard()
        }
    }

    private fun showSoftKeyboard() {
        surfaceView.requestFocus()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(WindowInsets.Type.ime())
        }
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        // SHOW_IMPLICIT often no-ops when focus just moved to a SurfaceView.
        @Suppress("DEPRECATION")
        imm?.showSoftInput(surfaceView, InputMethodManager.SHOW_FORCED)
        // Retry once after focus settles (Gboard / Samsung keyboards).
        surfaceView.postDelayed({
            if (!isFinishing && lastTextEntryWanted == true) {
                imm?.showSoftInput(surfaceView, 0)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    window.insetsController?.show(WindowInsets.Type.ime())
                }
            }
        }, 120L)
    }

    private fun hideSoftKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(surfaceView.windowToken, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.hide(WindowInsets.Type.ime())
        }
    }

    private fun scheduleResize(
        width: Int = surfaceView.width,
        height: Int = surfaceView.height,
    ) {
        if (width <= 0 || height <= 0) return
        pendingResize?.let(resizeHandler::removeCallbacks)
        pendingResizeAttempts = 0
        val resize = object : Runnable {
            override fun run() {
                val windowId = WawonaNative.nativeGetWindowForHost(hostToken())
                if (windowId == 0L &&
                    pendingResizeAttempts++ < MAX_CLAIM_WAIT_ATTEMPTS
                ) {
                    resizeHandler.postDelayed(this, RESIZE_SETTLE_MS)
                    return
                }
                SessionActivityRegistry.claimed(windowId, this@SessionActivity)
                WawonaNative.nativeResizeHostWindow(hostToken(), width, height)
            }
        }
        pendingResize = resize
        resizeHandler.postDelayed(resize, RESIZE_SETTLE_MS)
    }

    private fun hostToken(): Long = hostId

    companion object {
        private const val EXTRA_HOST_ID = "com.aspauldingcode.wawona.extra.HOST_ID"
        private const val EXTRA_TITLE = "com.aspauldingcode.wawona.extra.TITLE"
        private const val RESIZE_SETTLE_MS = 200L
        private const val MAX_CLAIM_WAIT_ATTEMPTS = 10
        private const val IME_POLL_MS = 100L

        fun newHostId(): Long =
            UUID.randomUUID().mostSignificantBits and Long.MAX_VALUE

        fun createIntent(
            context: Context,
            hostId: Long,
            title: String,
        ): Intent = Intent(context, SessionActivity::class.java).apply {
            putExtra(EXTRA_HOST_ID, hostId)
            putExtra(EXTRA_TITLE, title)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                    Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT,
            )
        }

        fun supportsHostTask(): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
    }
}

/**
 * True only when a real external/physical keyboard is present.
 * Shared with MainActivity's gate (issue #82 / #141).
 */
internal fun hasRealExternalKeyboard(configuration: Configuration): Boolean {
    var external = false
    for (id in android.view.InputDevice.getDeviceIds()) {
        val device = android.view.InputDevice.getDevice(id) ?: continue
        if (device.isVirtual) continue
        val sources = device.sources
        val isFullKeyboard =
            (sources and android.view.InputDevice.SOURCE_KEYBOARD) ==
                android.view.InputDevice.SOURCE_KEYBOARD &&
                device.keyboardType == android.view.InputDevice.KEYBOARD_TYPE_ALPHABETIC
        if (isFullKeyboard && !device.name.contains("Virtual", ignoreCase = true)) {
            external = true
            break
        }
    }
    if (!external) return false
    return configuration.keyboard == Configuration.KEYBOARD_QWERTY &&
        configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO
}
