package com.aspauldingcode.wawona

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Crop
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.OpenWith
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Rotate90DegreesCcw
import androidx.compose.material.icons.filled.StackedBarChart
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material.icons.filled.ViewInAr
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Canonical bundled client list. Keep in sync with iOS kBundledClients in WWNMachinesViewModel.swift.
 * Never add modeb-tty / igetty. Those are the Doorman console, not a machine.
 */
enum class BundledWaylandSoftwareKind(val sectionTitle: String) {
    COMPOSITOR("Compositors"),
    TERMINAL("Terminals"),
    GRAPHICS("Graphics"),
    DEMO("Demos"),
    OTHER("Other");

    companion object {
        fun forClientId(id: String): BundledWaylandSoftwareKind = when (id) {
            "weston", "niri" -> COMPOSITOR
            "weston-terminal", "foot", "wayland-terminal" -> TERMINAL
            "kmscube", "gbm-es2-demo", "opengl-cube", "vkcube", "weston-simple-egl" -> GRAPHICS
            "weston-simple-shm", "wawona-shell", "wawona-wasm", "custom" -> OTHER
            else -> if (id.startsWith("weston-")) DEMO else OTHER
        }
    }
}

data class BundledClientOption(
    val id: String,
    val name: String,
    val description: String,
    val icon: ImageVector,
) {
    val softwareKind: BundledWaylandSoftwareKind
        get() = BundledWaylandSoftwareKind.forClientId(id)
}

object BundledClients {
    val all: List<BundledClientOption> = listOf(
        BundledClientOption(
            "wawona-shell",
            "Native Shell",
            "zsh + uutils + fastfetch. Optional Wayland clients via wpm or apt",
            Icons.Filled.Terminal,
        ),
        BundledClientOption(
            "wawona-wasm",
            "Wawona Runtime (.wasm)",
            "Relay WASI Runtime. Pick a .wasm module or wpm package path",
            Icons.Filled.Apps,
        ),
    )

    fun labelFor(id: String): String = when (id) {
        "custom" -> "Custom Command (use Terminal)"
        else -> all.firstOrNull { it.id == id }?.name ?: id
    }

    /** Wayland picker groups: Compositors, then client types. Skips shell/wasm. */
    fun waylandPickerGroups(): List<Pair<BundledWaylandSoftwareKind, List<BundledClientOption>>> =
        BundledWaylandSoftwareKind.entries.mapNotNull { kind ->
            val group = all
                .filter { it.id != "wawona-shell" && it.id != "wawona-wasm" }
                .filter { it.softwareKind == kind }
                .sortedBy { it.name.lowercase() }
            if (group.isEmpty()) null else kind to group
        }

    /**
     * Optional clients found under Termux / jailbreak prefixes.
     * Store / Play never probe APT. See wawona-optional-software.
     */
    fun installedDebClients(): List<BundledClientOption> {
        val prefixes = listOf(
            "/data/data/com.termux/files/usr/bin",
            "/var/jb/usr/bin",
            "/usr/bin",
        )
        val ids = listOf(
            "weston", "niri", "foot", "weston-terminal", "weston-simple-shm",
            "weston-flower", "kmscube", "vkcube",
        )
        val out = mutableListOf<BundledClientOption>()
        for (prefix in prefixes) {
            for (id in ids) {
                val f = java.io.File(prefix, id)
                if (f.isFile && out.none { it.id == id }) {
                    out += BundledClientOption(
                        id,
                        labelFor(id),
                        "Installed deb: ${f.absolutePath}",
                        Icons.Filled.Apps,
                    )
                }
            }
        }
        return out
    }
}
