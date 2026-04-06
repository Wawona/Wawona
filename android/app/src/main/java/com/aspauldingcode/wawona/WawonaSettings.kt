package com.aspauldingcode.wawona

import android.content.SharedPreferences

object WawonaSettings {
    fun apply(prefs: SharedPreferences) {
        // Android: CSD not supported; Force SSD is always on.
        val forceServerSideDecorations = true
        
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
        
        // Render macOS Pointer - not applicable on Android, always false
        val renderMacOSPointer = false
        
        // Swap CMD - not applicable on Android, always false
        val swapCmdAsCtrl = false
        
        val universalClipboard = prefs.getBoolean("universalClipboard", true)
        
        // Color Operations (renamed from ColorSync Support)
        val colorOperations = prefs.getBoolean("colorOperations", true) ||
                             prefs.getBoolean("colorSyncSupport", false)
        
        val nestedCompositorsSupport = prefs.getBoolean("nestedCompositorsSupport", true)
        
        // Use Metal 4 - removed, always false
        val useMetal4ForNested = false
        
        // Multiple Clients - disabled by default on Android
        val multipleClients = prefs.getBoolean("multipleClients", false)
        
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
        val vulkanDriver = (prefs.getString("vulkanDriver", "none") ?: "none").lowercase()
        val openglDriver = (prefs.getString("openglDriver", "none") ?: "none").lowercase()
        
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
            openglDriver
        )
    }
}
