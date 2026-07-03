package com.aspauldingcode.wawona

import android.content.Context
import android.net.Uri
import android.os.Build
import java.io.File
import java.io.FileOutputStream

/**
 * Cross-platform Local Shell / WWN-ROOTFS contract (Android implementation).
 * Mirrors [WWNRootfsProvider] on Apple and host-shell info on desktop.
 */
enum class LocalShellCapability {
    Settings,
    BrowseUserFiles,
    ImportFile,
    ResetDotfiles,
    ReinstallSystemTree,
}

data class LocalShellSnapshot(
    val mode: String,
    val platformLabel: String,
    val filesRoot: String,
    val home: String,
    val systemRoot: String,
    val bundleTemplateVersion: String,
    val appliedTemplateVersion: String,
    val filesHint: String,
    val shellPath: String? = null,
) {
    val templateStatus: String
        get() = if (mode == "host") {
            "host shell"
        } else {
            val applied = appliedTemplateVersion.ifEmpty { "—" }
            "bundle v$bundleTemplateVersion / installed v$applied"
        }
}

object LocalShellRootfs {
    private const val TEMPLATE_VERSION = "1"
    private const val APPLIED_MARKER = ".template-version-applied"

    fun capabilities(): Set<LocalShellCapability> = setOf(
        LocalShellCapability.Settings,
        LocalShellCapability.BrowseUserFiles,
        LocalShellCapability.ImportFile,
        LocalShellCapability.ResetDotfiles,
        LocalShellCapability.ReinstallSystemTree,
    )

    fun prepareUserAccess(context: Context) {
        val home = homeDir(context)
        home.mkdirs()
        listOf(".config", ".cache", ".local/share", ".local/state").forEach { rel ->
            File(home, rel).mkdirs()
        }
        val readme = File(filesRoot(context), "README.txt")
        if (!readme.exists()) {
            readme.writeText(
                """
                Wawona Local Shell — Android

                home/     Shell HOME (\$HOME). Edit dotfiles, add scripts.
                Browse:  Android/data/<package>/files/wawona-rootfs/
                         or use Settings → Local Shell → Browse / Import.

                System etc/ and usr/ are under the same wawona-rootfs tree.
                """.trimIndent()
            )
        }
    }

    fun snapshot(context: Context): LocalShellSnapshot {
        prepareUserAccess(context)
        val root = WawonaShellRootfs.ensureInstalled(context)
        val applied = File(root, APPLIED_MARKER).takeIf { it.exists() }?.readText()?.trim().orEmpty()
        return LocalShellSnapshot(
            mode = "bundled",
            platformLabel = "Android ${Build.VERSION.RELEASE}",
            filesRoot = filesRoot(context).absolutePath,
            home = homeDir(context).absolutePath,
            systemRoot = root.absolutePath,
            bundleTemplateVersion = TEMPLATE_VERSION,
            appliedTemplateVersion = applied,
            filesHint = "Files app → Android → Wawona → wawona-rootfs, or use Import below.",
            shellPath = System.getenv("SHELL"),
        )
    }

    fun filesRoot(context: Context): File = File(context.filesDir, "wawona-rootfs")

    fun homeDir(context: Context): File = File(filesRoot(context), "home")

    fun refreshShellDotfiles(context: Context): Result<Unit> = runCatching {
        prepareUserAccess(context)
        WawonaShellRootfs.ensureInstalled(context)
        // Dotfile templates ship when added to assets; for now ensure home exists.
        homeDir(context).mkdirs()
    }

    fun reinstallSystemTree(context: Context): Result<Unit> = runCatching {
        val root = filesRoot(context)
        root.deleteRecursively()
        WawonaShellRootfs.ensureInstalled(context)
        File(root, APPLIED_MARKER).writeText(TEMPLATE_VERSION)
        prepareUserAccess(context)
    }

    fun importFile(context: Context, sourceUri: Uri, displayName: String?): Result<File> =
        runCatching {
            prepareUserAccess(context)
            val home = homeDir(context)
            var name = displayName?.substringAfterLast('/')?.ifBlank { null } ?: "imported-file"
            var dest = File(home, name)
            if (dest.exists()) {
                val stem = name.substringBeforeLast('.', name)
                val ext = name.substringAfterLast('.', "")
                val suffix = java.util.UUID.randomUUID().toString().take(8)
                name = if (ext.isNotEmpty()) "$stem-$suffix.$ext" else "$stem-$suffix"
                dest = File(home, name)
            }
            context.contentResolver.openInputStream(sourceUri)?.use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            } ?: error("Could not read selected file")
            dest
        }
}
