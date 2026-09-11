package com.aspauldingcode.wawona.anowaw

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * anowaW **power mode** (non-Play): unlocks arbitrary third-party app embedding
 * by borrowing shell (`uid=2000`) privileges through Shizuku (or root).
 *
 * Why this is needed: a normal app can create a [android.hardware.display.VirtualDisplay]
 * and launch *its own* activities onto it, but launching *another* app's
 * activity onto a virtual display (`ActivityOptions.setLaunchDisplayId`) throws
 * `SecurityException` unless the caller holds `INTERNAL_SYSTEM_WINDOW` /
 * `ADD_TRUSTED_DISPLAY`. Those are signature/privileged permissions no Play app
 * can hold — but the shell user effectively can, which is exactly how scrcpy's
 * `--new-display` launches arbitrary apps. Power mode routes the display
 * creation, activity launch, and input injection through a privileged Shizuku
 * user-service so the same works on-device.
 *
 * This tier is gated behind an explicit opt-in toggle in Settings (see the
 * `wawona.anowaW.powerMode` pref) and is clearly labeled as sideload/F-Droid
 * only. When Shizuku is unavailable the controller reports [isAvailable] = false
 * and the UI must fall back to the baseline tier.
 *
 * NOTE: Shizuku is an optional dependency. The reflection-based calls below keep
 * wwn-anowaW compilable without the Shizuku AIDL on the classpath; the Wawona
 * app provides the actual `dev.rikka.shizuku:api` binding and the AIDL
 * `IAnowawPrivileged` user-service implementation.
 */
class AnowawPowerController(private val context: Context) {

    companion object {
        private const val TAG = "anowaW"
        private const val SHIZUKU_MANAGER = "moe.shizuku.manager"
    }

    /** True when a privileged backend (Shizuku running + permission granted, or
     * root) is available to service trusted-display / arbitrary-launch requests. */
    fun isAvailable(): Boolean = shizukuReady() || rootReady()

    /** Human-readable status for the Settings screen. */
    fun statusDescription(): String = when {
        shizukuReady() -> "Shizuku connected — arbitrary app embedding available"
        rootReady() -> "Root available — arbitrary app embedding available"
        isShizukuInstalled() -> "Shizuku installed but not authorized"
        else -> "Shizuku not installed — power mode unavailable"
    }

    /**
     * Create a *trusted* virtual display via the privileged backend so
     * third-party activities may be launched onto it, and return its display id.
     * The [surface] is the same [android.view.Surface] anowaW captures from
     * (backed by an ImageReader in [AnowawBridge]).
     *
     * Implemented by the privileged user-service using:
     *   DisplayManagerGlobal.createVirtualDisplay(..., VIRTUAL_DISPLAY_FLAG_TRUSTED)
     * which requires ADD_TRUSTED_DISPLAY — held by the shell uid.
     */
    fun createTrustedDisplay(
        name: String,
        width: Int,
        height: Int,
        densityDpi: Int,
        surface: android.view.Surface,
    ): Int {
        return privileged()?.createTrustedDisplay(name, width, height, densityDpi, surface)
            ?: android.view.Display.INVALID_DISPLAY
    }

    /**
     * Launch [packageName]/[activity] onto [displayId] using privileged
     * `ActivityOptions.setLaunchDisplayId` (bypasses the SecurityException a
     * normal caller would hit for a third-party target).
     */
    fun launchAppOnDisplay(packageName: String, activity: String?, displayId: Int): Boolean {
        val intent = if (activity != null) {
            Intent().apply {
                component = ComponentName(packageName, activity)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } else {
            context.packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            } ?: return false
        }
        return privileged()?.startActivityOnDisplay(intent, displayId) ?: false
    }

    /**
     * Inject a decoded [AnowawInputEvent] into the target display via the
     * privileged `InputManager.injectInputEvent` path (shell can inject to any
     * window / display). Wired as [AnowawBridge.inputSink] in power mode.
     */
    fun injectInput(ev: AnowawInputEvent, displayId: Int) {
        privileged()?.injectInput(
            ev.kind, ev.code, ev.value, ev.x, ev.y, ev.timeMs, displayId
        )
    }

    fun shutdown() {
        privileged()?.let { runCatching { it.destroy() } }
        binder = null
    }

    // ── Privileged backend plumbing (Shizuku user-service / root) ────────────

    private var binder: IAnowawPrivileged? = null

    private fun privileged(): IAnowawPrivileged? {
        binder?.let { return it }
        binder = when {
            shizukuReady() -> AnowawShizukuBinder.bind(context)
            rootReady() -> AnowawRootBinder.bind(context)
            else -> null
        }
        if (binder == null) Log.w(TAG, "no privileged backend available for power mode")
        return binder
    }

    private fun isShizukuInstalled(): Boolean =
        runCatching {
            context.packageManager.getPackageInfo(SHIZUKU_MANAGER, 0); true
        }.getOrDefault(false)

    private fun shizukuReady(): Boolean = AnowawShizukuBinder.isReady()
    private fun rootReady(): Boolean = AnowawRootBinder.isReady()
}

/**
 * Interface implemented by the privileged user-service (runs as the shell uid
 * under Shizuku, or as root). The concrete AIDL stub + implementation live in
 * the Wawona app; wwn-anowaW only defines the contract so the controller and the
 * capture pipeline stay decoupled from the privilege mechanism.
 */
interface IAnowawPrivileged {
    fun createTrustedDisplay(name: String, width: Int, height: Int, densityDpi: Int, surface: android.view.Surface): Int
    fun startActivityOnDisplay(intent: Intent, displayId: Int): Boolean
    fun injectInput(kind: Int, code: Int, value: Int, x: Double, y: Double, timeMs: Int, displayId: Int)
    fun destroy()
}

/**
 * Placeholder binders resolved at runtime by the Wawona app, which supplies the
 * real Shizuku/root user-service. Kept here so wwn-anowaW compiles standalone;
 * the app overrides [factory] during init.
 */
object AnowawShizukuBinder {
    var factory: ((Context) -> IAnowawPrivileged?)? = null
    var readyProbe: (() -> Boolean)? = null
    fun isReady(): Boolean = readyProbe?.invoke() ?: false
    fun bind(context: Context): IAnowawPrivileged? = factory?.invoke(context)
}

object AnowawRootBinder {
    var factory: ((Context) -> IAnowawPrivileged?)? = null
    var readyProbe: (() -> Boolean)? = null
    fun isReady(): Boolean = readyProbe?.invoke() ?: false
    fun bind(context: Context): IAnowawPrivileged? = factory?.invoke(context)
}
