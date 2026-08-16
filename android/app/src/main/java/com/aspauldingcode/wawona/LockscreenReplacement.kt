package com.aspauldingcode.wawona

import android.content.SharedPreferences

/**
 * Lockscreen Replacement (macOS + Android only. Never iOS family).
 *
 * Parallel to [DesktopReplacement]: user picks a local Native greeter/lock
 * machine (gtkgreet / gtklock / similar) that runs before the desktop session.
 * Unlock handoff resumes the configured Desktop Replacement machine when set.
 *
 * Issue #103 follow-up; gated off the iOS/iPadOS/tvOS/watchOS/visionOS product
 * surface by platform packaging (this module is Android-only).
 */
object LockscreenReplacement {
    const val KEY_ENABLED = "wawona.lockscreen.enabled"
    const val KEY_MACHINE_ID = "wawona.lockscreen.machineId"

    fun isEnabled(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_ENABLED, false)

    fun setEnabled(prefs: SharedPreferences, enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun lockscreenMachineId(prefs: SharedPreferences): String? =
        prefs.getString(KEY_MACHINE_ID, null)?.takeIf { it.isNotBlank() }

    fun setLockscreenMachineId(prefs: SharedPreferences, machineId: String?) {
        prefs.edit().apply {
            if (machineId.isNullOrBlank()) remove(KEY_MACHINE_ID)
            else putString(KEY_MACHINE_ID, machineId)
        }.apply()
    }

    /** Greeter/lock clients: local Native only (never SSH/VM/container). */
    fun isEligible(profile: MachineProfile): Boolean {
        if (profile.type != MachineType.NATIVE) return false
        val launcher = profile.nativeLauncher.lowercase()
        return launcher.contains("gtkgreet") ||
            launcher.contains("gtklock") ||
            launcher.contains("greetd") ||
            launcher.contains("wlgreet") ||
            launcher.contains("lock")
    }

    fun eligibleMachines(profiles: List<MachineProfile>): List<MachineProfile> =
        profiles.filter { isEligible(it) }

    fun resolveLockscreenMachine(
        prefs: SharedPreferences,
        profiles: List<MachineProfile>,
    ): MachineProfile? {
        if (!isEnabled(prefs)) return null
        val id = lockscreenMachineId(prefs) ?: return null
        return profiles.firstOrNull { it.id == id && isEligible(it) }
    }
}
