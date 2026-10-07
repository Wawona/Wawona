package com.aspauldingcode.wawona

import android.content.SharedPreferences

object WawonaSettings {
    private const val DEFAULT_TCP_PORT = 1234

    fun apply(prefs: SharedPreferences, profile: MachineProfile? = null) {
        val decorations = readDecorationPrefs(prefs)
        val graphics = readGraphicsPrefs(prefs)
        WawonaNative.nativeSetTouchPointerEmulation(
            prefs.getBoolean("touchPointerEmulation", false)
        )
        WawonaNative.nativeApplySettings(
            decorations.forceServerSideDecorations,
            decorations.autoScale,
            decorations.renderingBackend,
            decorations.respectSafeArea,
            decorations.renderMacOSPointer,
            decorations.swapCmdAsCtrl,
            decorations.universalClipboard,
            decorations.colorOperations,
            decorations.nestedCompositorsSupport,
            decorations.useMetal4ForNested,
            decorations.multipleClients,
            decorations.waypipeRSSupport,
            decorations.enableTCPListener,
            decorations.tcpPort,
            graphics.vulkanDriver,
            graphics.openglDriver,
            graphics.compositorBackend
        )
        try {
            WawonaNative.nativeApplyEnvironmentOverrides(
                EnvironmentOverrides.jniPayload(prefs, profile)
            )
        } catch (_: UnsatisfiedLinkError) {
            // Older native libs without the symbol. Ignore until rebuild.
        } catch (_: NoSuchMethodError) {
            // Older native libs without the symbol. Ignore until rebuild.
        }
    }

    private data class DecorationPrefs(
        val forceServerSideDecorations: Boolean,
        val autoScale: Boolean,
        val renderingBackend: Int,
        val respectSafeArea: Boolean,
        val renderMacOSPointer: Boolean,
        val swapCmdAsCtrl: Boolean,
        val universalClipboard: Boolean,
        val colorOperations: Boolean,
        val nestedCompositorsSupport: Boolean,
        val useMetal4ForNested: Boolean,
        val multipleClients: Boolean,
        val waypipeRSSupport: Boolean,
        val enableTCPListener: Boolean,
        val tcpPort: Int,
    )

    private data class GraphicsPrefs(
        val vulkanDriver: String,
        val openglDriver: String,
        val compositorBackend: String,
    )

    private fun readDecorationPrefs(prefs: SharedPreferences): DecorationPrefs {
        // Default off: weston-family clients draw CSD unless Force SSD is enabled.
        val forceServerSideDecorations =
            prefs.getBoolean("forceServerSideDecorations", false)
        // Auto Scale (Android) maps to autoRetinaScaling for native compatibility.
        val autoScale = if (prefs.contains("autoScale")) {
            prefs.getBoolean("autoScale", true)
        } else {
            prefs.getBoolean("autoRetinaScaling", true)
        }
        val tcpPort = try {
            prefs.getString("tcpPort", DEFAULT_TCP_PORT.toString())?.toInt()
                ?: DEFAULT_TCP_PORT
        } catch (_: NumberFormatException) {
            DEFAULT_TCP_PORT
        }
        return DecorationPrefs(
            forceServerSideDecorations = forceServerSideDecorations,
            autoScale = autoScale,
            renderingBackend = prefs.getInt("renderingBackend", 0),
            respectSafeArea = prefs.getBoolean("respectSafeArea", true),
            renderMacOSPointer = prefs.getBoolean("renderMacOSPointer", false),
            swapCmdAsCtrl = false,
            universalClipboard = prefs.getBoolean("universalClipboard", true),
            colorOperations = prefs.getBoolean("colorOperations", true) ||
                prefs.getBoolean("colorSyncSupport", false),
            nestedCompositorsSupport = prefs.getBoolean("nestedCompositorsSupport", true),
            useMetal4ForNested = false,
            multipleClients = prefs.getBoolean("multipleClients", true),
            waypipeRSSupport = true,
            enableTCPListener = false,
            tcpPort = tcpPort,
        )
    }

    private fun readGraphicsPrefs(prefs: SharedPreferences): GraphicsPrefs {
        val storedVulkanDriver =
            (prefs.getString("vulkanDriver", "system") ?: "system").lowercase()
        val vulkanDriver =
            storedVulkanDriver
                .takeIf { it in setOf("none", "system", "swiftshader") }
                ?: "system"
        if (storedVulkanDriver != vulkanDriver) {
            prefs.edit().putString("vulkanDriver", "System").apply()
        }
        val openglDriver =
            (prefs.getString("openglDriver", "angle") ?: "angle")
                .lowercase()
                .takeIf { it in setOf("none", "system", "angle") }
                ?: "angle"
        val compositorBackend =
            (prefs.getString("compositorBackend", "auto") ?: "auto")
                .lowercase()
                .takeIf { it in setOf("auto", "wayland", "drm") }
                ?: "auto"
        return GraphicsPrefs(vulkanDriver, openglDriver, compositorBackend)
    }
}
