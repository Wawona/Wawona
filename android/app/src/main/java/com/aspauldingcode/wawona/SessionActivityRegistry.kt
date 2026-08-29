package com.aspauldingcode.wawona

import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap

/** Process-local routing for optional Android freeform host tasks. */
object SessionActivityRegistry {
    private val hostForSession = ConcurrentHashMap<String, Long>()
    private val activityForWindow = ConcurrentHashMap<Long, WeakReference<SessionActivity>>()
    private val activityForHost = ConcurrentHashMap<Long, WeakReference<SessionActivity>>()

    fun reserve(sessionId: String, hostId: Long) {
        hostForSession[sessionId] = hostId
    }

    fun release(sessionId: String) {
        hostForSession.remove(sessionId)
    }

    fun hasActiveSessions(): Boolean = hostForSession.isNotEmpty()

    fun claimed(windowId: Long, activity: SessionActivity) {
        if (windowId != 0L) activityForWindow[windowId] = WeakReference(activity)
        activityForHost[activityHostId(activity)] = WeakReference(activity)
    }

    fun register(activity: SessionActivity, hostId: Long) {
        activityForHost[hostId] = WeakReference(activity)
    }

    fun release(activity: SessionActivity) {
        activityForWindow.entries.removeIf { (_, ref) -> ref.get() === activity || ref.get() == null }
        activityForHost.entries.removeIf { (_, ref) -> ref.get() === activity || ref.get() == null }
    }

    fun park(windowId: Long) {
        activityForWindow.remove(windowId)?.get()?.moveTaskToBack(true)
    }

    fun focus(sessionId: String) {
        val hostId = hostForSession[sessionId] ?: return
        val windowId = WawonaNative.nativeGetWindowForHost(hostId)
        val activity = activityForWindow[windowId]?.get()
            ?: activityForHost[hostId]?.get()
        activity?.moveHostTaskToFront()
    }

    /**
     * Finish the host task for [sessionId] and release its native claim.
     * Call on Stop / Start-again so a stale SessionActivity cannot destroy
     * the next surface (#141).
     */
    fun finishSession(sessionId: String) {
        val hostId = hostForSession.remove(sessionId) ?: return
        finishHost(hostId)
    }

    /** Finish every tracked host task (e.g. before a fresh Start). */
    fun finishAllHosts() {
        val hosts = hostForSession.values.toSet() + activityForHost.keys
        hostForSession.clear()
        hosts.forEach { finishHost(it) }
    }

    private fun finishHost(hostId: Long) {
        val activity = activityForHost.remove(hostId)?.get()
        val windowId = runCatching { WawonaNative.nativeGetWindowForHost(hostId) }.getOrDefault(0L)
        if (windowId != 0L) {
            activityForWindow.remove(windowId)?.get()?.let { if (it !== activity) it.finish() }
        }
        try {
            WawonaNative.nativeCloseHostWindow(hostId)
            WawonaNative.nativeReleaseHostWindow(hostId)
        } catch (_: Exception) {
        }
        activity?.finish()
    }

    private fun activityHostId(activity: SessionActivity): Long {
        // Intent extra is the only stable id before claim; fall back 0.
        return activity.intent?.getLongExtra(
            "com.aspauldingcode.wawona.extra.HOST_ID",
            0L,
        ) ?: 0L
    }
}
