package com.aspauldingcode.wawona

import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Cross-platform machine override helpers. iOS/macOS store PascalCase keys in
 * settingsOverrides; Android historically used camelCase. runtimeOverrides holds
 * session-exit toggles on Apple platforms.
 */
object SettingsOverrides {
    private val BOOL_ALIASES = mapOf(
        "respectSafeArea" to listOf("respectSafeArea", "RespectSafeArea"),
        "renderMacOSPointer" to listOf("renderMacOSPointer", "RenderMacOSPointer"),
        "swipeBackToCloseEnabled" to listOf("swipeBackToCloseEnabled", "SwipeBackToCloseEnabled"),
        "shakeToCloseEnabled" to listOf("shakeToCloseEnabled", "ShakeToCloseEnabled"),
    )
    private val STRING_ALIASES = mapOf(
        "touchInputType" to listOf("touchInputType", "TouchInputType"),
    )

    fun merge(profile: MachineProfile): JSONObject {
        val merged = JSONObject(profile.settingsOverrides.toString())
        profile.runtimeOverrides.keys().forEach { key ->
            profile.runtimeOverrides.opt(key)?.let { merged.put(key, it) }
        }
        return merged
    }

    fun readBool(overrides: JSONObject?, canonicalKey: String, globalDefault: Boolean): Boolean {
        val keys = BOOL_ALIASES[canonicalKey] ?: listOf(canonicalKey)
        for (key in keys) {
            if (overrides == null || !overrides.has(key)) continue
            when (val raw = overrides.opt(key)) {
                is JSONObject -> when (raw.optString("type", "")) {
                    "boolean" -> return raw.optBoolean("value", globalDefault)
                }
                is Boolean -> return raw
            }
        }
        return globalDefault
    }

    fun readString(overrides: JSONObject?, canonicalKey: String, globalDefault: String): String {
        val keys = STRING_ALIASES[canonicalKey] ?: listOf(canonicalKey)
        for (key in keys) {
            if (overrides == null || !overrides.has(key)) continue
            when (val raw = overrides.opt(key)) {
                is JSONObject -> when (raw.optString("type", "")) {
                    "string" -> return raw.optString("value", globalDefault)
                }
                is String -> return raw
            }
        }
        return globalDefault
    }

    fun applyToPrefs(prefs: SharedPreferences, profile: MachineProfile) {
        val merged = merge(profile)
        if (merged.length() == 0) return
        val editor = prefs.edit()
        val keys = merged.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val encoded = merged.optJSONObject(key) ?: continue
            val canonical = BOOL_ALIASES.entries.firstOrNull { (_, aliases) -> key in aliases }?.key
                ?: STRING_ALIASES.entries.firstOrNull { (_, aliases) -> key in aliases }?.key
                ?: key
            when (encoded.optString("type", "string")) {
                "boolean" -> editor.putBoolean(canonical, encoded.optBoolean("value", false))
                "int" -> editor.putInt(canonical, encoded.optInt("value", 0))
                "long" -> editor.putLong(canonical, encoded.optLong("value", 0L))
                "float" -> editor.putFloat(canonical, encoded.optDouble("value", 0.0).toFloat())
                else -> editor.putString(canonical, encoded.optString("value", ""))
            }
        }
        editor.apply()
    }
}
