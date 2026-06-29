package com.aspauldingcode.wawona

import android.content.Context
import java.io.File
import java.io.FileOutputStream

/**
 * Extracts bundled share trees from APK assets into the app files dir:
 * zsh (shell fpath) and xkeyboard-config (compositor keymaps).
 */
object WawonaShellRootfs {
    private const val MARKER = ".installed"

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

            File(root, "home").mkdirs()
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
