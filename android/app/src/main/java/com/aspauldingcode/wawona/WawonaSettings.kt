package com.aspauldingcode.wawona

import android.content.SharedPreferences

object WawonaSettings {
    fun apply(prefs: SharedPreferences, profile: MachineProfile? = null) {
        // Default off: weston-family clients draw CSD unless Force SSD is enabled.
        val forceServerSideDecorations =
            prefs.getBoolean("forceServerSideDecorations", false)
        
        // Auto Scale (Android) maps to autoRetinaScaling for native compatibility.
        // Primary key is "autoScale" (from the UI toggle); fall back to legacy
        // "autoRetinaScaling" only when the primary key was never written.
        val autoScale = if (prefs.contains("autoScale")) {
            prefs.getBoolean("autoScale", true)
        } else {
            prefs.getBoolean("autoRetinaScaling", true)
        }
        
        val renderingBackend = prefs.getInt("renderingBackend", 0)
        val respectSafeArea = prefs.getBoolean("respectSafeArea", true)
        
        // Android uses the same semantic toggle as iOS ("Show Virtual Pointer").
        val renderMacOSPointer = prefs.getBoolean("renderMacOSPointer", false)
        
        // Swap CMD - not applicable on Android, always false
        val swapCmdAsCtrl = false
        
        val universalClipboard = prefs.getBoolean("universalClipboard", true)
        
        // Color Operations (renamed from ColorSync Support)
        val colorOperations = prefs.getBoolean("colorOperations", true) ||
                             prefs.getBoolean("colorSyncSupport", false)
        
        val nestedCompositorsSupport = prefs.getBoolean("nestedCompositorsSupport", true)
        
        // Use Metal 4 - removed, always false
        val useMetal4ForNested = false
        
        // Multiple Clients — match iOS/macOS default (shared Rust core supports it).
        val multipleClients = prefs.getBoolean("multipleClients", true)
        
        // Waypipe RS Support - always enabled, always true
        val waypipeRSSupport = true
        
        // TCP Listener - removed, always false
        val enableTCPListener = false
        
        // TCP Port - no longer used but kept for compatibility
        val tcpPort = try { 
            prefs.getString("tcpPort", "1234")?.toInt() ?: 1234 
        } catch (e: Exception) { 
            1234 
        }

        // Text Assist / Dictation
        val enableTextAssist = prefs.getBoolean("enableTextAssist", false)
        val enableDictation = prefs.getBoolean("enableDictation", false)

        // Graphics Driver selection (Settings > Graphics > Drivers)
        // UI stores display strings (e.g. "SwiftShader"); normalize to lowercase for native
        val storedVulkanDriver =
            (prefs.getString("vulkanDriver", "system") ?: "system").lowercase()
        val vulkanDriver =
            storedVulkanDriver
                .takeIf { it in setOf("none", "system", "swiftshader") }
                ?: "system"
        if (storedVulkanDriver != vulkanDriver) {
            prefs.edit().putString("vulkanDriver", "System").apply()
        }
        /* Default ANGLE: iland GBM/KMS clients need the bundled Vulkan-backed
         * ANGLE slice; vendor "system" GLES remains selectable. */
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
        
        WawonaNative.nativeApplySettings(
            forceServerSideDecorations,
            autoScale,
            renderingBackend,
            respectSafeArea,
            renderMacOSPointer,
            swapCmdAsCtrl,
            universalClipboard,
            colorOperations,
            nestedCompositorsSupport,
            useMetal4ForNested,
            multipleClients,
            waypipeRSSupport,
            enableTCPListener,
            tcpPort,
            vulkanDriver,
            openglDriver,
            compositorBackend
        )
        try {
            WawonaNative.nativeApplyEnvironmentOverrides(
                EnvironmentOverrides.jniPayload(prefs, profile)
            )
        } catch (_: Throwable) {
            // Older native libs without the symbol — ignore until rebuild.
        }
    }
}
