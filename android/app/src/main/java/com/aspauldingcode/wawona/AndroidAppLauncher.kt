package com.aspauldingcode.wawona

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Drawable

/**
 * Enumerates and launches installed Android apps.
 *
 * Used by [AppDrawer] when Wawona runs as a desktop/home replacement: alongside
 * the ported Wayland clients from Machine Configuration, the user can still open
 * ordinary Android apps, reinforcing the "we built a Wayland desktop for
 * Android" experience while staying Play-Store compliant (no privileged APIs,
 * only the documented launcher-query + `startActivity` flow).
 */
data class AndroidApp(
    val packageName: String,
    val label: String,
    val icon: Drawable?,
)

object AndroidAppLauncher {
    /**
     * Query all launchable Android apps (activities in the LAUNCHER category),
     * excluding Wawona itself, sorted alphabetically by label.
     */
    fun installedApps(context: Context): List<AndroidApp> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = try {
            pm.queryIntentActivities(intent, 0)
        } catch (_: Exception) {
            emptyList()
        }
        val self = context.packageName
        return resolved
            .asSequence()
            .mapNotNull { info ->
                val activity = info.activityInfo ?: return@mapNotNull null
                val pkg = activity.packageName
                if (pkg == self) return@mapNotNull null
                val label = try {
                    info.loadLabel(pm)?.toString()
                } catch (_: Exception) {
                    null
                } ?: pkg
                val icon = try {
                    info.loadIcon(pm)
                } catch (_: Exception) {
                    null
                }
                AndroidApp(packageName = pkg, label = label, icon = icon)
            }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
            .toList()
    }

    /** Launch an installed Android app by package name. Returns false if unlaunchable. */
    fun launch(context: Context, packageName: String): Boolean {
        val pm = context.packageManager
        val launch = try {
            pm.getLaunchIntentForPackage(packageName)
        } catch (_: Exception) {
            null
        } ?: return false
        return try {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launch)
            true
        } catch (_: Exception) {
            false
        }
    }
}
