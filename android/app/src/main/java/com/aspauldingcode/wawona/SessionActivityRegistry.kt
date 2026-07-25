package com.aspauldingcode.wawona

import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap

/** Process-local routing for optional Android freeform host tasks. */
object SessionActivityRegistry {
    private val hostForSession = ConcurrentHashMap<String, Long>()
    private val activityForWindow = ConcurrentHashMap<Long, WeakReference<SessionActivity>>()

    fun reserve(sessionId: String, hostId: Long) {
        hostForSession[sessionId] = hostId
    }

    fun release(sessionId: String) {
        hostForSession.remove(sessionId)
    }

    fun hasActiveSessions(): Boolean = hostForSession.isNotEmpty()

    fun claimed(windowId: Long, activity: SessionActivity) {
        if (windowId != 0L) activityForWindow[windowId] = WeakReference(activity)
    }

    fun release(activity: SessionActivity) {
        activityForWindow.entries.removeIf { (_, ref) -> ref.get() === activity || ref.get() == null }
    }

    fun park(windowId: Long) {
        activityForWindow.remove(windowId)?.get()?.moveTaskToBack(true)
    }

    fun focus(sessionId: String) {
        val hostId = hostForSession[sessionId] ?: return
        val windowId = WawonaNative.nativeGetWindowForHost(hostId)
        activityForWindow[windowId]?.get()?.moveHostTaskToFront()
    }
}
