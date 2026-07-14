package com.aspauldingcode.wawona

import android.content.Context
import java.io.File
import java.io.FileOutputStream

/**
 * Extracts bundled share trees from APK assets into the app files dir:
 * zsh (shell fpath), xkeyboard-config (compositor keymaps), weston data
 * (CSD frame PNGs), and DejaVu fonts (fontconfig text rendering).
 */
object WawonaShellRootfs {
    // Bumped v5 -> v6: ship Freedesktop applications catalog
    // (share/applications + icons/hicolor) for nested-niri fuzzel Mod+D.
    //
    // Bumped v4 -> v5: earlier gradlegen-built APKs omitted assets/weston,
    // leaving toytoolkit CSD buttons with 1x1 placeholder icons instead of
    // the normal close/max/min glyphs and spacing.
    //
    // Bumped v3 -> v4: earlier gradlegen-built APKs shipped an empty
    // assets/xkb (no rules/evdev), so xkbcommon failed to resolve a keymap,
    // smithay's seat.add_keyboard() had nothing to fall back to, and the
    // seat ended up with zero keyboard capability — no key ever reached any
    // client. Bump the marker so devices with a stale (incomplete) rootfs
    // from before that fix get re-extracted instead of skipping install.
    private const val MARKER = ".installed-v6"

    fun ensureInstalled(context: Context): File {
        val root = File(context.filesDir, "wawona-rootfs")
        val marker = File(root, MARKER)
        if (marker.exists()) {
            return root
        }

        try {
            val shareZsh = File(root, "usr/share/zsh")
            shareZsh.mkdirs()
            copyAssetDir(context, "zsh", shareZsh)

            val shareXkb = File(root, "usr/share/X11/xkb")
            shareXkb.mkdirs()
            copyAssetDir(context, "xkb", shareXkb)

            val shareWeston = File(root, "usr/share/weston")
            shareWeston.mkdirs()
            copyAssetDir(context, "weston", shareWeston)

            val shareFonts = File(root, "usr/share/fonts")
            shareFonts.mkdirs()
            copyAssetDir(context, "fonts", shareFonts)

            // fuzzel Freedesktop catalog (issue #78)
            val shareApplications = File(root, "usr/share/applications")
            shareApplications.mkdirs()
            copyAssetDir(context, "applications", shareApplications)

            val shareIcons = File(root, "usr/share/icons")
            shareIcons.mkdirs()
            copyAssetDir(context, "icons", shareIcons)

            File(root, "home").mkdirs()
            File(root, "home/.local/share").mkdirs()
            File(root, "home/.cache").mkdirs()
            File(root, "usr/bin").mkdirs()

            marker.writeText("ok")
            WLog.d("SHELL", "Shell rootfs installed at ${root.absolutePath}")
        } catch (e: Exception) {
            WLog.e("SHELL", "Shell rootfs install failed: ${e.message}")
            throw e
        }
        return root
    }

    private fun copyAssetDir(context: Context, assetPath: String, dest: File) {
        val assets = context.assets.list(assetPath) ?: return
        if (assets.isEmpty()) {
            return
        }
        dest.mkdirs()
        for (name in assets) {
            val childAsset = if (assetPath.isEmpty()) name else "$assetPath/$name"
            val childDest = File(dest, name)
            val childAssets = context.assets.list(childAsset)
            if (childAssets != null && childAssets.isNotEmpty()) {
                copyAssetDir(context, childAsset, childDest)
            } else {
                childDest.parentFile?.mkdirs()
                context.assets.open(childAsset).use { input ->
                    FileOutputStream(childDest).use { output -> input.copyTo(output) }
                }
            }
        }
    }
}
