package com.aspauldingcode.wawona

import android.content.SharedPreferences
import org.json.JSONObject

object SessionExitSettings {
    fun resolvedShakeEnabled(prefs: SharedPreferences, profile: MachineProfile?): Boolean {
        val global = prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true)
        val merged = profile?.let { SettingsOverrides.merge(it) }
        return SettingsOverrides.readBool(merged, "shakeToCloseEnabled", global)
    }

    fun resolvedSwipeBackEnabled(prefs: SharedPreferences, profile: MachineProfile?): Boolean {
        val global = prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true)
        val merged = profile?.let { SettingsOverrides.merge(it) }
        return SettingsOverrides.readBool(merged, "swipeBackToCloseEnabled", global)
    }

    fun isThumbnailEnabled(prefs: SharedPreferences, profile: MachineProfile?): Boolean {
        val merged = profile?.let { SettingsOverrides.merge(it) }
        return SettingsOverrides.readBool(merged, "machineThumbnailEnabledOverride", true)
    }
}
