package com.aspauldingcode.wawona

import android.content.Context
import java.io.File
import java.io.FileOutputStream

/**
 * Extracts the bundled zsh share tree from APK assets into the app files dir so
 * weston-terminal can resolve completion/functions via fpath.
 */
object WawonaShellRootfs {
    private const val MARKER = ".installed"

    fun ensureInstalled(context: Context): File {
        val root = File(context.filesDir, "wawona-rootfs")
        val marker = File(root, MARKER)
        if (marker.exists()) {
            return root
        }

        val shareZsh = File(root, "usr/share/zsh")
        shareZsh.mkdirs()
        copyAssetDir(context, "zsh", shareZsh)

        val home = File(root, "home")
        home.mkdirs()

        val binDir = File(root, "usr/bin")
        binDir.mkdirs()

        marker.writeText("ok")
        WLog.d("SHELL", "Shell rootfs installed at ${root.absolutePath}")
        return root
    }

    private fun copyAssetDir(context: Context, assetPath: String, dest: File) {
        val assets = context.assets.list(assetPath) ?: return
        if (assets.isEmpty()) {
            context.assets.open(assetPath).use { input ->
                dest.parentFile?.mkdirs()
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            }
            return
        }
        dest.mkdirs()
        for (name in assets) {
            val childAsset = if (assetPath.isEmpty()) name else "$assetPath/$name"
            copyAssetDir(context, childAsset, File(dest, name))
        }
    }
}
