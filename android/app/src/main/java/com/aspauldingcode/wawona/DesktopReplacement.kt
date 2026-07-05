package com.aspauldingcode.wawona

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.mutableIntStateOf

/**
 * Desktop Replacement mode.
 *
 * When enabled, Wawona behaves like an Android *Launcher* (HOME app): a single
 * user-selected [MachineType.NATIVE] machine is auto-connected to become the
 * "desktop" (a nested Wayland desktop such as `weston` + `desktop-shell.so`),
 * and an [AppDrawer] exposes both installed Android apps and the other
 * configured Wayland clients.
 *
 * This is the Android counterpart to the macOS wwn-iland "Mode B"
 * SkyLight/WindowServer replacement. On Android the DRM/KMS present path
 * (wwn-iland `android/`) targets the launcher surface instead of an OS daemon,
 * which is why the desktop machine is constrained to a locally-ported native
 * client — never a VM, waypipe/network, or container machine.
 */
object DesktopReplacement {
    /** Whether Wawona should act as a desktop/home replacement. */
    const val KEY_ENABLED = "wawona.desktop.enabled"

    /** Machine profile id chosen to be the desktop. MUST be [MachineType.NATIVE]. */
    const val KEY_MACHINE_ID = "wawona.desktop.machineId"

    fun isEnabled(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_ENABLED, false)

    fun setEnabled(prefs: SharedPreferences, enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun desktopMachineId(prefs: SharedPreferences): String? =
        prefs.getString(KEY_MACHINE_ID, null)?.takeIf { it.isNotBlank() }

    fun setDesktopMachineId(prefs: SharedPreferences, machineId: String?) {
        prefs.edit().apply {
            if (machineId.isNullOrBlank()) remove(KEY_MACHINE_ID)
            else putString(KEY_MACHINE_ID, machineId)
        }.apply()
    }

    /** A native machine profile is the only kind eligible to be the desktop. */
    fun isEligible(profile: MachineProfile): Boolean = profile.type == MachineType.NATIVE

    fun eligibleMachines(profiles: List<MachineProfile>): List<MachineProfile> =
        profiles.filter { isEligible(it) }

    /**
     * Resolve the configured desktop machine, if desktop mode is fully set up.
     * Returns null when disabled, unset, missing, or the referenced machine is
     * no longer a native machine.
     */
    fun resolveDesktopMachine(
        prefs: SharedPreferences,
        profiles: List<MachineProfile>,
    ): MachineProfile? {
        if (!isEnabled(prefs)) return null
        val id = desktopMachineId(prefs) ?: return null
        return profiles.firstOrNull { it.id == id && isEligible(it) }
    }

    /** True when desktop mode is enabled but not yet pointed at a valid native machine. */
    fun needsConfiguration(
        prefs: SharedPreferences,
        profiles: List<MachineProfile>,
    ): Boolean = isEnabled(prefs) && resolveDesktopMachine(prefs, profiles) == null

    // ── HOME role helpers ────────────────────────────────────────────────

    /** Whether Wawona currently holds the Android HOME (launcher) role. */
    fun isWawonaHome(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = context.getSystemService(RoleManager::class.java)
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_HOME)) {
                return rm.isRoleHeld(RoleManager.ROLE_HOME)
            }
        }
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        @Suppress("DEPRECATION")
        val resolved = context.packageManager.resolveActivity(intent, 0)
        return resolved?.activityInfo?.packageName == context.packageName
    }

    /**
     * Build an intent that lets the user make Wawona the default HOME app.
     * Uses [RoleManager] on API 29+ (returns a request intent to start for
     * result) and falls back to the system Home-settings screen otherwise.
     */
    fun homeRoleRequestIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = context.getSystemService(RoleManager::class.java)
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_HOME) && !rm.isRoleHeld(RoleManager.ROLE_HOME)) {
                return rm.createRequestRoleIntent(RoleManager.ROLE_HOME)
            }
        }
        return Intent(Settings.ACTION_HOME_SETTINGS)
    }
}

/**
 * Signals a HOME-button press (or launcher relaunch) from [MainActivity.onNewIntent]
 * to the running Compose tree, so the app drawer / desktop can react.
 */
object HomeIntentBus {
    /** Incremented every time the activity is re-entered via a HOME/launcher intent. */
    val homeTick = mutableIntStateOf(0)

    fun signalHome() {
        homeTick.intValue += 1
    }
}
