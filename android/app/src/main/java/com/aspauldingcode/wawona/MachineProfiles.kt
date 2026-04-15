package com.aspauldingcode.wawona

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class MachineType(val value: String) {
    NATIVE("native"),
    SSH_WAYPIPE("ssh_waypipe"),
    SSH_TERMINAL("ssh_terminal"),
    VM("virtual_machine"),
    CONTAINER("container");

    companion object {
        fun fromValue(value: String): MachineType =
            entries.firstOrNull { it.value == value } ?: SSH_WAYPIPE
    }
}

enum class MachineStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    DEGRADED,
    ERROR
}

data class MachineCapabilities(
    val launchSupported: Boolean,
    val isStub: Boolean,
    val label: String
)

data class VirtualMachineSettings(
    val provider: String = "utm-se",
    val vmIdentifier: String = "",
    val vsockPort: String = "",
    val notes: String = ""
)

data class ContainerSettings(
    val runtime: String = "docker",
    val containerRef: String = "",
    val entryCommand: String = "",
    val notes: String = ""
)

data class MachineProfile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val type: MachineType,
    val sshEnabled: Boolean = true,
    val sshHost: String = "",
    val sshUser: String = "",
    val sshPassword: String = "",
    val sshBinary: String = "ssh",
    val sshAuthMethod: String = "password",
    val sshKeyPath: String = "",
    val sshKeyPassphrase: String = "",
    val remoteCommand: String = "",
    val customScript: String = "",
    val vmSubtype: String = "qemu",
    val containerSubtype: String = "docker",
    val waypipeCompress: String = "lz4",
    val waypipeThreads: String = "0",
    val waypipeVideo: String = "none",
    val waypipeDebug: Boolean = false,
    val waypipeOneshot: Boolean = false,
    val waypipeDisableGpu: Boolean = false,
    val waypipeLoginShell: Boolean = false,
    val waypipeTitlePrefix: String = "",
    val waypipeSecCtx: String = "",
    val settingsOverrides: JSONObject = JSONObject(),
    val vmSettings: VirtualMachineSettings = VirtualMachineSettings(),
    val containerSettings: ContainerSettings = ContainerSettings(),
    val favorite: Boolean = false,
    val createdAtMs: Long = System.currentTimeMillis(),
    val updatedAtMs: Long = System.currentTimeMillis()
) {
    fun capabilities(): MachineCapabilities = when (type) {
        MachineType.NATIVE -> MachineCapabilities(
            launchSupported = true,
            isStub = false,
            label = "Local"
        )
        MachineType.SSH_WAYPIPE -> MachineCapabilities(
            launchSupported = true,
            isStub = false,
            label = "Ready"
        )
        MachineType.SSH_TERMINAL -> MachineCapabilities(
            launchSupported = true,
            isStub = false,
            label = "Ready"
        )
        MachineType.VM -> MachineCapabilities(
            launchSupported = false,
            isStub = true,
            label = "Stub (UTM SE integration pending)"
        )
        MachineType.CONTAINER -> MachineCapabilities(
            launchSupported = false,
            isStub = true,
            label = "Stub (runtime integration pending)"
        )
    }
}

object MachineProfileStore {
    private const val KEY_PROFILES_JSON = "wawona.machineProfiles.v1"
    private const val KEY_ACTIVE_MACHINE_ID = "wawona.activeMachineId.v1"
    private const val KEY_MIGRATED = "wawona.machineProfilesMigrated.v1"
    private val EXCLUDED_PREF_KEYS = setOf(
        KEY_PROFILES_JSON,
        KEY_ACTIVE_MACHINE_ID,
        KEY_MIGRATED
    )

    fun loadProfiles(prefs: SharedPreferences): List<MachineProfile> {
        migrateFromLegacyPrefs(prefs)
        val raw = prefs.getString(KEY_PROFILES_JSON, null) ?: return emptyList()
        return parseProfiles(raw)
    }

    fun saveProfiles(prefs: SharedPreferences, profiles: List<MachineProfile>) {
        val arr = JSONArray()
        profiles.forEach { arr.put(serializeProfile(it)) }
        prefs.edit().putString(KEY_PROFILES_JSON, arr.toString()).apply()
    }

    fun upsertProfile(prefs: SharedPreferences, profile: MachineProfile): List<MachineProfile> {
        val now = System.currentTimeMillis()
        val withTimestamp = profile.copy(updatedAtMs = now)
        val current = loadProfiles(prefs).toMutableList()
        val idx = current.indexOfFirst { it.id == withTimestamp.id }
        if (idx >= 0) {
            current[idx] = withTimestamp
        } else {
            current.add(withTimestamp.copy(createdAtMs = now))
        }
        saveProfiles(prefs, current)
        return current
    }

    fun deleteProfile(prefs: SharedPreferences, profileId: String): List<MachineProfile> {
        val filtered = loadProfiles(prefs).filterNot { it.id == profileId }
        saveProfiles(prefs, filtered)
        if (getActiveMachineId(prefs) == profileId) {
            setActiveMachineId(prefs, null)
        }
        return filtered
    }

    fun setActiveMachineId(prefs: SharedPreferences, machineId: String?) {
        prefs.edit().apply {
            if (machineId.isNullOrBlank()) remove(KEY_ACTIVE_MACHINE_ID) else putString(KEY_ACTIVE_MACHINE_ID, machineId)
        }.apply()
    }

    fun getActiveMachineId(prefs: SharedPreferences): String? =
        prefs.getString(KEY_ACTIVE_MACHINE_ID, null)

    fun applyMachineToPrefs(prefs: SharedPreferences, profile: MachineProfile) {
        applySettingsOverridesToPrefs(prefs, profile.settingsOverrides)
        prefs.edit()
            .putBoolean("waypipeSSHEnabled", profile.sshEnabled)
            .putString("waypipeSSHHost", profile.sshHost)
            .putString("waypipeSSHUser", profile.sshUser)
            .putString("waypipeSSHPassword", profile.sshPassword)
            .putString("waypipeSSHBinary", profile.sshBinary)
            .putString("waypipeSSHAuthMethod", profile.sshAuthMethod)
            .putString("waypipeSSHKeyPath", profile.sshKeyPath)
            .putString("waypipeSSHKeyPassphrase", profile.sshKeyPassphrase)
            .putString("waypipeRemoteCommand", profile.remoteCommand)
            .putString("waypipeCustomScript", profile.customScript)
            .putString("waypipeCompress", profile.waypipeCompress)
            .putString("waypipeThreads", profile.waypipeThreads)
            .putString("waypipeVideo", profile.waypipeVideo)
            .putBoolean("waypipeDebug", profile.waypipeDebug)
            .putBoolean("waypipeOneshot", profile.waypipeOneshot)
            .putBoolean("waypipeDisableGpu", profile.waypipeDisableGpu)
            .putBoolean("waypipeLoginShell", profile.waypipeLoginShell)
            .putString("waypipeTitlePrefix", profile.waypipeTitlePrefix)
            .putString("waypipeSecCtx", profile.waypipeSecCtx)
            .apply()
    }

    fun persistActiveMachineSettings(prefs: SharedPreferences): List<MachineProfile> {
        val activeId = getActiveMachineId(prefs) ?: return loadProfiles(prefs)
        val current = loadProfiles(prefs).toMutableList()
        val idx = current.indexOfFirst { it.id == activeId }
        if (idx < 0) {
            return current
        }
        val snapshot = captureSettingsOverridesFromPrefs(prefs)
        val updated = current[idx].copy(
            settingsOverrides = snapshot,
            updatedAtMs = System.currentTimeMillis()
        )
        current[idx] = updated
        saveProfiles(prefs, current)
        return current
    }

    private fun migrateFromLegacyPrefs(prefs: SharedPreferences) {
        val migrated = prefs.getBoolean(KEY_MIGRATED, false)
        val existing = prefs.getString(KEY_PROFILES_JSON, null)
        if (migrated || !existing.isNullOrBlank()) {
            return
        }

        val host = prefs.getString("waypipeSSHHost", "") ?: ""
        val user = prefs.getString("waypipeSSHUser", "") ?: ""
        val defaultName = if (host.isNotBlank()) "Migrated $host" else "Default Machine"
        val profile = MachineProfile(
            name = defaultName,
            type = MachineType.SSH_WAYPIPE,
            sshEnabled = prefs.getBoolean("waypipeSSHEnabled", true),
            sshHost = host,
            sshUser = user,
            sshPassword = prefs.getString("waypipeSSHPassword", "") ?: "",
            sshBinary = prefs.getString("waypipeSSHBinary", "ssh") ?: "ssh",
            sshAuthMethod = prefs.getString("waypipeSSHAuthMethod", "password") ?: "password",
            sshKeyPath = prefs.getString("waypipeSSHKeyPath", "") ?: "",
            sshKeyPassphrase = prefs.getString("waypipeSSHKeyPassphrase", "") ?: "",
            remoteCommand = prefs.getString("waypipeRemoteCommand", "") ?: "",
            customScript = prefs.getString("waypipeCustomScript", "") ?: "",
            waypipeCompress = prefs.getString("waypipeCompress", "lz4") ?: "lz4",
            waypipeThreads = prefs.getString("waypipeThreads", "0") ?: "0",
            waypipeVideo = prefs.getString("waypipeVideo", "none") ?: "none",
            waypipeDebug = prefs.getBoolean("waypipeDebug", false),
            waypipeOneshot = prefs.getBoolean("waypipeOneshot", false),
            waypipeDisableGpu = prefs.getBoolean("waypipeDisableGpu", false),
            waypipeLoginShell = prefs.getBoolean("waypipeLoginShell", false),
            waypipeTitlePrefix = prefs.getString("waypipeTitlePrefix", "") ?: "",
            waypipeSecCtx = prefs.getString("waypipeSecCtx", "") ?: "",
            settingsOverrides = captureSettingsOverridesFromPrefs(prefs)
        )
        saveProfiles(prefs, listOf(profile))
        setActiveMachineId(prefs, profile.id)
        prefs.edit().putBoolean(KEY_MIGRATED, true).apply()
    }

    private fun parseProfiles(raw: String): List<MachineProfile> = try {
        val arr = JSONArray(raw)
        buildList {
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                add(parseProfile(obj))
            }
        }
    } catch (_: Exception) {
        emptyList()
    }

    private fun serializeProfile(profile: MachineProfile): JSONObject = JSONObject().apply {
        put("id", profile.id)
        put("name", profile.name)
        put("type", profile.type.value)
        put("sshEnabled", profile.sshEnabled)
        put("sshHost", profile.sshHost)
        put("sshUser", profile.sshUser)
        put("sshPassword", profile.sshPassword)
        put("sshBinary", profile.sshBinary)
        put("sshAuthMethod", profile.sshAuthMethod)
        put("sshKeyPath", profile.sshKeyPath)
        put("sshKeyPassphrase", profile.sshKeyPassphrase)
        put("remoteCommand", profile.remoteCommand)
        put("customScript", profile.customScript)
        put("vmSubtype", profile.vmSubtype)
        put("containerSubtype", profile.containerSubtype)
        put("waypipeCompress", profile.waypipeCompress)
        put("waypipeThreads", profile.waypipeThreads)
        put("waypipeVideo", profile.waypipeVideo)
        put("waypipeDebug", profile.waypipeDebug)
        put("waypipeOneshot", profile.waypipeOneshot)
        put("waypipeDisableGpu", profile.waypipeDisableGpu)
        put("waypipeLoginShell", profile.waypipeLoginShell)
        put("waypipeTitlePrefix", profile.waypipeTitlePrefix)
        put("waypipeSecCtx", profile.waypipeSecCtx)
        put("settingsOverrides", profile.settingsOverrides)
        put("favorite", profile.favorite)
        put("createdAtMs", profile.createdAtMs)
        put("updatedAtMs", profile.updatedAtMs)
        put("vmSettings", JSONObject().apply {
            put("provider", profile.vmSettings.provider)
            put("vmIdentifier", profile.vmSettings.vmIdentifier)
            put("vsockPort", profile.vmSettings.vsockPort)
            put("notes", profile.vmSettings.notes)
        })
        put("containerSettings", JSONObject().apply {
            put("runtime", profile.containerSettings.runtime)
            put("containerRef", profile.containerSettings.containerRef)
            put("entryCommand", profile.containerSettings.entryCommand)
            put("notes", profile.containerSettings.notes)
        })
    }

    private fun parseProfile(obj: JSONObject): MachineProfile {
        val vmObj = obj.optJSONObject("vmSettings") ?: JSONObject()
        val containerObj = obj.optJSONObject("containerSettings") ?: JSONObject()
        return MachineProfile(
            id = obj.optString("id", UUID.randomUUID().toString()),
            name = obj.optString("name", "Unnamed Machine"),
            type = MachineType.fromValue(obj.optString("type", MachineType.SSH_WAYPIPE.value)),
            sshEnabled = obj.optBoolean("sshEnabled", true),
            sshHost = obj.optString("sshHost", ""),
            sshUser = obj.optString("sshUser", ""),
            sshPassword = obj.optString("sshPassword", ""),
            sshBinary = obj.optString("sshBinary", "ssh"),
            sshAuthMethod = obj.optString("sshAuthMethod", "password"),
            sshKeyPath = obj.optString("sshKeyPath", ""),
            sshKeyPassphrase = obj.optString("sshKeyPassphrase", ""),
            remoteCommand = obj.optString("remoteCommand", ""),
            customScript = obj.optString("customScript", ""),
            vmSubtype = obj.optString("vmSubtype", "qemu"),
            containerSubtype = obj.optString("containerSubtype", "docker"),
            waypipeCompress = obj.optString("waypipeCompress", "lz4"),
            waypipeThreads = obj.optString("waypipeThreads", "0"),
            waypipeVideo = obj.optString("waypipeVideo", "none"),
            waypipeDebug = obj.optBoolean("waypipeDebug", false),
            waypipeOneshot = obj.optBoolean("waypipeOneshot", false),
            waypipeDisableGpu = obj.optBoolean("waypipeDisableGpu", false),
            waypipeLoginShell = obj.optBoolean("waypipeLoginShell", false),
            waypipeTitlePrefix = obj.optString("waypipeTitlePrefix", ""),
            waypipeSecCtx = obj.optString("waypipeSecCtx", ""),
            settingsOverrides = obj.optJSONObject("settingsOverrides") ?: JSONObject(),
            vmSettings = VirtualMachineSettings(
                provider = vmObj.optString("provider", "utm-se"),
                vmIdentifier = vmObj.optString("vmIdentifier", ""),
                vsockPort = vmObj.optString("vsockPort", ""),
                notes = vmObj.optString("notes", "")
            ),
            containerSettings = ContainerSettings(
                runtime = containerObj.optString("runtime", "docker"),
                containerRef = containerObj.optString("containerRef", ""),
                entryCommand = containerObj.optString("entryCommand", ""),
                notes = containerObj.optString("notes", "")
            ),
            favorite = obj.optBoolean("favorite", false),
            createdAtMs = obj.optLong("createdAtMs", System.currentTimeMillis()),
            updatedAtMs = obj.optLong("updatedAtMs", System.currentTimeMillis())
        )
    }

    private fun captureSettingsOverridesFromPrefs(prefs: SharedPreferences): JSONObject {
        val snapshot = JSONObject()
        prefs.all.forEach { (key, value) ->
            if (key in EXCLUDED_PREF_KEYS || value == null) return@forEach
            val encoded = JSONObject()
            when (value) {
                is Boolean -> {
                    encoded.put("type", "boolean")
                    encoded.put("value", value)
                }
                is Int -> {
                    encoded.put("type", "int")
                    encoded.put("value", value)
                }
                is Long -> {
                    encoded.put("type", "long")
                    encoded.put("value", value)
                }
                is Float -> {
                    encoded.put("type", "float")
                    encoded.put("value", value.toDouble())
                }
                is String -> {
                    encoded.put("type", "string")
                    encoded.put("value", value)
                }
                else -> return@forEach
            }
            snapshot.put(key, encoded)
        }
        return snapshot
    }

    private fun applySettingsOverridesToPrefs(prefs: SharedPreferences, overrides: JSONObject) {
        if (overrides.length() == 0) return
        val editor = prefs.edit()
        val keys = overrides.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val encoded = overrides.optJSONObject(key) ?: continue
            when (encoded.optString("type", "string")) {
                "boolean" -> editor.putBoolean(key, encoded.optBoolean("value", false))
                "int" -> editor.putInt(key, encoded.optInt("value", 0))
                "long" -> editor.putLong(key, encoded.optLong("value", 0L))
                "float" -> editor.putFloat(key, encoded.optDouble("value", 0.0).toFloat())
                else -> editor.putString(key, encoded.optString("value", ""))
            }
        }
        editor.apply()
    }
}
