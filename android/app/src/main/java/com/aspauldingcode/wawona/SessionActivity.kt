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
import android.widget.FrameLayout
import java.util.UUID

/**
 * One optional Android host task for one Wayland toplevel.
 *
 * MainActivity remains Wawona's single-task HOME surface. Every Android 7+
 * machine launch gets a separate task; Android decides whether that task is
 * fullscreen, split, freeform, or on an external display. The native claim is
 * reserved before client launch, then atomically bound to the first toplevel.
 */
class SessionActivity : Activity(), SurfaceHolder.Callback {
    private var hostId = 0L
    private lateinit var surfaceView: WawonaSurfaceView
    private val resizeHandler = Handler(Looper.getMainLooper())
    private var pendingResize: Runnable? = null
    private var pendingResizeAttempts = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hostId = savedInstanceState?.getLong(EXTRA_HOST_ID)
            ?: intent.getLongExtra(EXTRA_HOST_ID, newHostId())
        title = intent.getStringExtra(EXTRA_TITLE) ?: getString(R.string.app_name)

        surfaceView = WawonaSurfaceView(this)
        surfaceView.holder.addCallback(this)
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
    }

    override fun onPause() {
        WawonaNative.nativeSetHostWindowFocused(hostToken(), false)
        super.onPause()
    }

    override fun onDestroy() {
        pendingResize?.let(resizeHandler::removeCallbacks)
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
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean) {
        super.onMultiWindowModeChanged(isInMultiWindowMode)
        scheduleResize()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        WawonaNative.nativeSetSurface(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        scheduleResize(width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        pendingResize?.let(resizeHandler::removeCallbacks)
        pendingResize = null
        WawonaNative.nativeDestroySurface()
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
