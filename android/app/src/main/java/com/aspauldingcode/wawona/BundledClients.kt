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
 */
data class BundledClientOption(
    val id: String,
    val name: String,
    val description: String,
    val icon: ImageVector,
)

object BundledClients {
    val all: List<BundledClientOption> = listOf(
        BundledClientOption("weston-terminal", "Weston Terminal", "Terminal emulator. Uses host cursor", Icons.Filled.Terminal),
        BundledClientOption("weston-simple-shm", "Weston Simple SHM", "Minimal shared-memory Wayland client", Icons.Filled.Dashboard),
        BundledClientOption("wawona-wasm", "Wawona Runtime (.wasm)", "Wayland WASI module from the filesystem (Wawona Runtime)", Icons.Filled.Apps),
        BundledClientOption("weston", "Weston", "Wayland reference compositor (nested compositor)", Icons.Filled.ViewModule),
        BundledClientOption("niri", "Niri", "Scrollable-tiling compositor (nested compositor)", Icons.Filled.ViewColumn),
        BundledClientOption("foot", "Foot Terminal", "Lightweight Wayland terminal emulator", Icons.Filled.Create),
        BundledClientOption("weston-flower", "Weston Flower", "Animated cairo demo (toytoolkit)", Icons.Filled.Eco),
        BundledClientOption("kmscube", "KMS Cube", "Spinning GL cube via iland + ANGLE (userland KMS)", Icons.Filled.ViewInAr),
        BundledClientOption("opengl-cube", "OpenGL Cube", "GLES cube via Wayland-EGL (ANGLE)", Icons.Filled.ViewInAr),
        BundledClientOption("vkcube", "Vulkan Cube", "Vulkan API smoke test", Icons.Filled.ViewInAr),
        BundledClientOption("weston-simple-egl", "Weston Simple EGL", "Wayland EGL demo client", Icons.Filled.Cloud),
        BundledClientOption("weston-smoke", "Weston Smoke", "Smoke particle cairo demo", Icons.Filled.Cloud),
        BundledClientOption("weston-clickdot", "Weston Clickdot", "Pointer click visualization demo", Icons.Filled.TouchApp),
        BundledClientOption("weston-eventdemo", "Weston Event Demo", "Input event logging demo", Icons.Filled.Apps),
        BundledClientOption("weston-resizor", "Weston Resizor", "Interactive resize demo", Icons.Filled.OpenWith),
        BundledClientOption("weston-cliptest", "Weston Cliptest", "Clipping region demo", Icons.Filled.Crop),
        BundledClientOption("weston-transformed", "Weston Transformed", "Buffer transform demo", Icons.Filled.Rotate90DegreesCcw),
        BundledClientOption("weston-stacking", "Weston Stacking", "Subsurface stacking demo", Icons.Filled.Layers),
        BundledClientOption("weston-dnd", "Weston DnD", "Drag-and-drop demo", Icons.Filled.ContentCut),
        BundledClientOption("weston-image", "Weston Image", "PNG image loader demo", Icons.Filled.Image),
        BundledClientOption("weston-scaler", "Weston Scaler", "Viewport scaler demo", Icons.Filled.ArrowUpward),
        BundledClientOption("weston-editor", "Weston Editor", "Text editor demo", Icons.Filled.Edit),
        BundledClientOption("weston-constraints", "Weston Constraints", "Pointer constraints demo", Icons.Filled.StackedBarChart),
    )

    fun labelFor(id: String): String = all.firstOrNull { it.id == id }?.name ?: id
}
