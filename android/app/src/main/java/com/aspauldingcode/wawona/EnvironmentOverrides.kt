package com.aspauldingcode.wawona

import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Global + per-machine environment overrides (#157 / #160).
 * Shape matches Apple: `{ "TERM": { "action": "set", "value": "xterm" }, "RUST_LOG": { "action": "unset" } }`
 */
object EnvironmentOverrides {
    const val GLOBAL_KEY = "wawona.pref.environment.v1"
    const val RUNTIME_ENV_KEY = "environment"

    /** Catalog names that Reset Wawona-managed clears (keep user extras). */
    val CATALOG_NAMES: Set<String> = setOf(
        "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "WAYLAND_SOCKET",
        "WAWONA_NESTED_WAYLAND_DISPLAY", "WAWONA_OUTPUT_SCALE",
        "NIRI_BACKEND", "NIRI_CONFIG", "WESTON_CONFIG_FILE",
        "WESTON_DATA_DIR", "WESTON_MODULE_DIR", "WESTON_BACKEND_DIR",
        "VK_DRIVER_FILES", "VK_ICD_FILENAMES", "WWN_VULKAN_LIBRARY",
        "WWN_VULKAN_LIBRARY_FALLBACKS", "WWN_VULKAN_DRIVER", "WWN_OPENGL_DRIVER",
        "WWN_DISABLE_VULKAN", "WWN_DISABLE_EGL", "ANGLE_DEFAULT_PLATFORM",
        "WWN_SWIFTSHADER_LIBRARY",
        "HOME", "USER", "LOGNAME", "SHELL", "WAWONA_SHELL", "WAWONA_ZSH_IN_PROCESS",
        "TERM", "PATH", "ZDOTDIR", "WAWONA_ROOTFS", "WAWONA_BUNDLE_ROOTFS",
        "WAWONA_FILES_DIR", "PROMPT", "PS1",
        "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_DATA_DIRS",
        "FONTCONFIG_FILE", "FONTCONFIG_PATH", "WAWONA_MONO_FONT", "WAWONA_SANS_FONT",
        "WAWONA_TERMINAL_FONT_SIZE", "XKB_CONFIG_ROOT", "XKB_DEFAULT_LAYOUT",
        "XKB_DEFAULT_VARIANT", "XCURSOR_PATH", "XCURSOR_THEME",
        "RUST_LOG", "RUST_BACKTRACE", "WAWONA_AUTO_CMD",
        "SSHPASS", "WAYPIPE_SSH_PASSWORD",
    )

    data class Entry(val action: String, val value: String?) {
        fun toJson(): JSONObject = JSONObject().apply {
            put("action", action)
            if (value != null) put("value", value)
        }

        companion object {
            fun set(value: String) = Entry("set", value)
            fun unset() = Entry("unset", null)
            fun fromJson(obj: JSONObject?): Entry? {
                if (obj == null) return null
                val action = obj.optString("action", "set")
                val value = if (obj.has("value")) obj.optString("value") else null
                return Entry(action, value)
            }
        }
    }

    fun loadGlobal(prefs: SharedPreferences): MutableMap<String, Entry> {
        val raw = prefs.getString(GLOBAL_KEY, null) ?: return mutableMapOf()
        return parseMap(raw)
    }

    fun saveGlobal(prefs: SharedPreferences, map: Map<String, Entry>) {
        if (map.isEmpty()) {
            prefs.edit().remove(GLOBAL_KEY).apply()
        } else {
            prefs.edit().putString(GLOBAL_KEY, encodeMap(map)).apply()
        }
    }

    fun loadMachine(profile: MachineProfile): MutableMap<String, Entry> {
        val env = profile.runtimeOverrides.optJSONObject(RUNTIME_ENV_KEY) ?: return mutableMapOf()
        val out = mutableMapOf<String, Entry>()
        env.keys().forEach { key ->
            Entry.fromJson(env.optJSONObject(key))?.let { out[key] = it }
        }
        return out
    }

    fun withMachineEnv(profile: MachineProfile, map: Map<String, Entry>): MachineProfile {
        val runtime = JSONObject(profile.runtimeOverrides.toString())
        if (map.isEmpty()) {
            runtime.remove(RUNTIME_ENV_KEY)
        } else {
            val env = JSONObject()
            map.forEach { (k, v) -> env.put(k, v.toJson()) }
            runtime.put(RUNTIME_ENV_KEY, env)
        }
        return profile.copy(runtimeOverrides = runtime, updatedAtMs = System.currentTimeMillis())
    }

    fun resetManaged(map: MutableMap<String, Entry>) {
        val keys = map.keys.filter { it in CATALOG_NAMES }.toList()
        keys.forEach { map.remove(it) }
    }

    fun mergedFlat(prefs: SharedPreferences, profile: MachineProfile?): Map<String, String> {
        val merged = loadGlobal(prefs)
        if (profile != null) {
            merged.putAll(loadMachine(profile))
        }
        val out = mutableMapOf<String, String>()
        merged.forEach { (name, entry) ->
            when (entry.action) {
                "unset" -> { /* skip — JNI will unset */ }
                else -> out[name] = entry.value ?: ""
            }
        }
        return out
    }

    fun mergedUnsetNames(prefs: SharedPreferences, profile: MachineProfile?): List<String> {
        val merged = loadGlobal(prefs)
        if (profile != null) {
            merged.putAll(loadMachine(profile))
        }
        return merged.filter { it.value.action == "unset" }.map { it.key }
    }

    /** JSON payload for JNI: `{ "set": { "TERM": "xterm" }, "unset": ["RUST_LOG"] }` */
    fun jniPayload(prefs: SharedPreferences, profile: MachineProfile?): String {
        val merged = loadGlobal(prefs)
        if (profile != null) {
            merged.putAll(loadMachine(profile))
        }
        val setObj = JSONObject()
        val unsetArr = org.json.JSONArray()
        merged.forEach { (name, entry) ->
            when (entry.action) {
                "unset" -> unsetArr.put(name)
                else -> setObj.put(name, entry.value ?: "")
            }
        }
        return JSONObject().put("set", setObj).put("unset", unsetArr).toString()
    }

    private fun parseMap(raw: String): MutableMap<String, Entry> {
        return try {
            val obj = JSONObject(raw)
            val out = mutableMapOf<String, Entry>()
            obj.keys().forEach { key ->
                Entry.fromJson(obj.optJSONObject(key))?.let { out[key] = it }
            }
            out
        } catch (_: Exception) {
            mutableMapOf()
        }
    }

    private fun encodeMap(map: Map<String, Entry>): String {
        val obj = JSONObject()
        map.forEach { (k, v) -> obj.put(k, v.toJson()) }
        return obj.toString()
    }
}
