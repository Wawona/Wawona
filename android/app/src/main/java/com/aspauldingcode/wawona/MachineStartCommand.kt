package com.aspauldingcode.wawona

import android.content.SharedPreferences
import java.io.File

/**
 * Formats the machine Start command as a shell-like `$ argv` banner so
 * Wawona Terminal matches typing the same CLI by hand.
 */
object MachineStartCommand {
    fun argvBanner(prefs: SharedPreferences, profile: MachineProfile, wasmPath: String? = null): String {
        val cmd = resolvedArgv(prefs, profile, wasmPath)
        return buildString {
            append("$ ")
            append(cmd)
            append('\n')
        }
    }

    fun resolvedArgv(
        prefs: SharedPreferences,
        profile: MachineProfile,
        wasmPath: String? = null,
    ): String {
        return when (profile.type) {
            MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> waypipeArgv(prefs, profile)
            MachineType.WASM -> {
                val path = wasmPath
                    ?: profile.runtimeOverrides.optString("wasmModulePath", "").ifBlank { null }
                    ?: profile.runtimeOverrides.optString("wasmPackage", "").ifBlank { null }
                    ?: "hello-wasi-gui.wasm"
                "wpm run $path"
            }
            MachineType.NATIVE -> {
                val (kind, useSsh) = NativeShellSession.from(profile)
                val bundled = NativeShellSession.migrateClientId(
                    profile.runtimeOverrides.optString("bundledAppID", "").trim()
                        .ifBlank { profile.nativeLauncher }
                )
                when {
                    kind == NativeShellKind.WAYPIPE ||
                        profile.runtimeOverrides.optBoolean("waypipeEnabled", false) ->
                        waypipeArgv(prefs, profile)
                    bundled == "wawona-wasm" || kind == NativeShellKind.WASM -> {
                        val path = wasmPath
                            ?: profile.runtimeOverrides.optString("wasmModulePath", "").ifBlank { null }
                            ?: "hello-wasi-gui.wasm"
                        "wpm run $path"
                    }
                    useSsh || profile.sshEnabled -> {
                        val host = MachineInputSanitizer.sanitizeHost(profile.sshHost)
                        val user = profile.sshUser.trim()
                        val port = profile.sshPort.takeIf { it > 0 } ?: 22
                        val remote = profile.remoteCommand.trim().ifBlank {
                            prefs.getString("waypipeRemoteCommand", "")?.trim().orEmpty()
                        }.ifBlank { "bash -l" }
                        buildString {
                            append("ssh")
                            if (port != 22) append(" -p $port")
                            append(' ')
                            if (user.isNotEmpty()) append("$user@")
                            append(host.ifBlank { "host" })
                            append(' ')
                            append(shellQuote(remote))
                        }
                    }
                    else -> {
                        val custom = profile.runtimeOverrides.optString("NativeCustomCommand", "")
                            .trim()
                            .ifBlank {
                                profile.runtimeOverrides.optString("nativeCustomCommand", "").trim()
                            }
                        custom.ifBlank { "wawona-shell" }
                    }
                }
            }
            MachineType.VM -> "relay vm start ${profile.name.ifBlank { profile.id }}"
            MachineType.CONTAINER -> "relay container start ${profile.name.ifBlank { profile.id }}"
        }
    }

    fun waypipeArgv(prefs: SharedPreferences, profile: MachineProfile): String {
        val sshOn = prefs.getBoolean("waypipeSSHEnabled", profile.sshEnabled)
        val host = MachineInputSanitizer.sanitizeHost(
            prefs.getString("waypipeSSHHost", profile.sshHost) ?: profile.sshHost
        )
        val port = MachineInputSanitizer.normalizePort(
            prefs.getString("waypipeSSHPort", profile.sshPort.toString())
                ?: profile.sshPort.toString()
        )
        val user = (prefs.getString("waypipeSSHUser", profile.sshUser) ?: profile.sshUser).trim()
        val remote = (prefs.getString("waypipeRemoteCommand", profile.remoteCommand)
            ?: profile.remoteCommand).trim().ifBlank { "weston-simple-shm" }
        val compress = prefs.getString("waypipeCompress", profile.waypipeCompress)
            ?: profile.waypipeCompress
        return waypipeArgv(
            sshOn = sshOn,
            host = host,
            port = port,
            user = user,
            remote = remote,
            compress = compress,
        )
    }

    /** Pure argv formatter (unit-testable; no Android prefs). */
    fun waypipeArgv(
        sshOn: Boolean,
        host: String,
        port: Int,
        user: String,
        remote: String,
        compress: String,
    ): String {
        val parts = mutableListOf("waypipe")
        if (compress.isNotBlank() && compress != "none") {
            parts += listOf("-c", compress)
        }
        if (sshOn) {
            parts += "ssh"
            if (port != 22) parts += listOf("-p", port.toString())
            val target = buildString {
                if (user.isNotEmpty()) append("$user@")
                append(host.ifBlank { "host" })
            }
            parts += target
        }
        parts += remote
        return parts.joinToString(" ") { shellQuote(it) }
    }

    fun shellQuoteForTest(s: String): String = shellQuote(s)

    fun waypipeStderrPath(cacheDir: File): File =
        File(cacheDir, "wawona-runtime/waypipe-stderr.log")

    private fun shellQuote(s: String): String {
        if (s.isEmpty()) return "''"
        if (s.all { it.isLetterOrDigit() || it in "-_./:@" }) return s
        return "'" + s.replace("'", "'\\''") + "'"
    }
}
