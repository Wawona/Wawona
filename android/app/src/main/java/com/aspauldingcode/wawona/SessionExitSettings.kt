package com.aspauldingcode.wawona

import android.content.SharedPreferences
import org.json.JSONObject

object SessionExitSettings {
    fun resolvedShakeEnabled(prefs: SharedPreferences, profile: MachineProfile?): Boolean {
        val global = prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true)
        return readBoolOverride(profile?.settingsOverrides, "shakeToCloseEnabled", global)
    }

    fun resolvedSwipeBackEnabled(prefs: SharedPreferences, profile: MachineProfile?): Boolean {
        val global = prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true)
        return readBoolOverride(profile?.settingsOverrides, "swipeBackToCloseEnabled", global)
    }

    fun isThumbnailEnabled(prefs: SharedPreferences, profile: MachineProfile?): Boolean {
        return readBoolOverride(profile?.settingsOverrides, "machineThumbnailEnabledOverride", true)
    }

    private fun readBoolOverride(overrides: JSONObject?, key: String, globalDefault: Boolean): Boolean {
        if (overrides == null || !overrides.has(key)) return globalDefault
        return when (val raw = overrides.opt(key)) {
            is JSONObject -> when (raw.optString("type", "")) {
                "boolean" -> raw.optBoolean("value", globalDefault)
                else -> globalDefault
            }
            is Boolean -> raw
            else -> globalDefault
        }
    }
}
