package com.aspauldingcode.wawona

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import com.aspauldingcode.wawona.anowaw.AnowawBridge
import com.aspauldingcode.wawona.anowaw.AnowawInputEvent
import com.aspauldingcode.wawona.anowaw.AnowawNative
import com.aspauldingcode.wawona.anowaw.AnowawPowerController

/**
 * App-side coordinator for the App Bridge (anowaW) on Android.
 *
 * Bridges the pure [AnowawBridge] core (in the wwn-anowaW `anowaw` package) to
 * Wawona's launcher/desktop lifecycle: it connects to the nested Weston socket
 * once the desktop machine is up, routes decoded Wayland input back into the
 * source apps (own-app dispatch in baseline, privileged InputManager in power
 * mode), and turns "open Android app" drawer taps into launch-into-desktop
 * actions.
 *
 * Privilege tiers (no SIP on Android):
 * - **Rootless / baseline** (power mode off, or Shizuku/root unavailable):
 *   MediaProjection / own-app VirtualDisplay only. Third-party apps are not
 *   embedded. waypipe-rs patches still carry mirrored surfaces into the
 *   nested Wayland desktop when the bridge is attached.
 * - **Root / Shizuku power mode** (prefs on + [AnowawPowerController] available):
 *   trusted VirtualDisplay, launch any package, privileged input inject, and
 *   the same waypipe-rs mirror path with full app→Wayland embedding.
 *
 * Power mode auto-falls back to baseline when Shizuku/root is unavailable at
 * attach time; Settings surfaces the reason via
 * [AnowawPowerController.statusDescription].
 */
object AnowawSession {
    private const val TAG = "anowaW"

    /**
     * Deterministic nested Weston socket name. MUST match the `--socket=` arg
     * passed to the nested compositor in android_jni.c (weston_thread_func) and
     * the macOS `kWWNAnowaWNestedSocket`.
     */
    const val NESTED_SOCKET = "wawona-nested"

    private var bridge: AnowawBridge? = null
    private var power: AnowawPowerController? = null
    private var powerMode = false
    // anowaW app handle -> backing virtual-display id, for input routing.
    private val displayForHandle = HashMap<Long, Int>()

    val isActive: Boolean get() = bridge != null

    /**
     * Attach the bridge to the running nested-Weston desktop. Idempotent. Call
     * after the desktop machine has connected and the compositor is up. Returns
     * true if the bridge is (now) active.
     */
    fun attach(context: Context, prefs: SharedPreferences): Boolean {
        if (bridge != null) return true
        if (!DesktopReplacement.isAppBridgeEnabled(prefs)) return false

        val wantPower = DesktopReplacement.isPowerModeEnabled(prefs)
        power = AnowawPowerController(context.applicationContext)
        powerMode = wantPower && (power?.isAvailable() == true)
        if (wantPower && !powerMode) {
            Log.w(
                TAG,
                "power mode requested but unavailable — falling back to rootless baseline: ${
                    power?.statusDescription()
                }",
            )
            // Keep the pref as the user's intent; runtime uses baseline until
            // Shizuku/root becomes available on a later attach.
        }

        val b = AnowawBridge.connect(context.applicationContext, NESTED_SOCKET)
        if (b == null) {
            Log.e(TAG, "failed to attach anowaW bridge to $NESTED_SOCKET")
            return false
        }
        b.inputSink = { ev -> routeInput(ev) }
        bridge = b
        Log.i(
            TAG,
            "anowaW attached tier=${if (powerMode) "power(root/Shizuku)" else "rootless/baseline"} " +
                "(waypipe-rs mirror active on nested socket $NESTED_SOCKET)",
        )
        return true
    }

    /**
     * Launch [app] as a window inside the desktop instead of full-screen. In
     * baseline this only works for Wawona-owned activities; third-party apps
     * require power mode. Falls back to a normal launch when the bridge is
     * inactive or the launch is disallowed.
     */
    fun launchAppIntoDesktop(context: Context, app: AndroidApp): Boolean {
        val b = bridge ?: return false
        val metrics = displayMetrics(context)
        val handle = b.createDisplay(
            packageName = app.packageName,
            title = app.label,
            width = metrics.widthPixels,
            height = metrics.heightPixels,
            densityDpi = metrics.densityDpi,
        )
        if (handle == 0L) return false
        val displayId = b.displayIdFor(handle)
        displayForHandle[handle] = displayId

        val launched = if (powerMode) {
            power?.launchAppOnDisplay(app.packageName, null, displayId) ?: false
        } else {
            // Baseline: only own-app activities may target a virtual display.
            if (app.packageName == context.packageName) {
                launchOwnActivityOnDisplay(context, displayId)
            } else {
                Log.w(TAG, "baseline tier cannot embed third-party ${app.packageName}; enable power mode")
                false
            }
        }
        if (!launched) b.closeApp(handle)
        return launched
    }

    private fun launchOwnActivityOnDisplay(context: Context, displayId: Int): Boolean {
        return try {
            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            }
            val opts = android.app.ActivityOptions.makeBasic().apply {
                launchDisplayId = displayId
            }
            context.startActivity(intent, opts.toBundle())
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "setLaunchDisplayId denied: ${e.message}")
            false
        }
    }

    private fun routeInput(ev: AnowawInputEvent) {
        if (powerMode) {
            val displayId = displayForHandle[ev.handle] ?: return
            power?.injectInput(ev, displayId)
        }
        // Baseline: own-app windows receive input directly from the framework
        // (they are real activities on the virtual display), so no re-injection
        // is required for the Play-safe tier.
    }

    fun detach() {
        bridge?.stop()
        bridge = null
        power?.shutdown()
        power = null
        displayForHandle.clear()
    }

    private fun displayMetrics(context: Context): DisplayMetrics {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        return metrics
    }
}
