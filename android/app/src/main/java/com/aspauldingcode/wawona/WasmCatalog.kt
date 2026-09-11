package com.aspauldingcode.wawona

import android.content.Context
import android.net.Uri
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Mode A wasm catalog only (`https://repo.wawona.io/wasm/v1`).
 * Never APT, `/jailbreak/`, or `/termux/`.
 */
data class WasmCatalogPackage(
    val name: String,
    val version: String,
    val digest: String,
    val url: String,
    val summary: String,
)

object WasmCatalog {
    const val CATALOG_BASE = "https://repo.wawona.io/wasm/v1"
    const val INDEX_URL = "$CATALOG_BASE/index.json"
    const val DEFAULT_COMMAND = "wasm hello-wasi-gui"
    const val DEFAULT_PACKAGE = "hello-wasi-gui"

    fun isAllowedCatalogUrl(url: String): Boolean {
        val lower = url.lowercase()
        if (lower.contains("/jailbreak/") || lower.contains("/termux/")) return false
        if (lower.contains("/packages") && !lower.contains("/wasm/")) return false
        if (lower.endsWith(".deb")) return false
        return lower.startsWith(CATALOG_BASE) || lower.contains("/wasm/v1") || lower.contains("/wasm/")
    }

    fun modulesDir(context: Context): File =
        File(context.filesDir, "Wawona/wasm-modules").apply { mkdirs() }

    fun listLocalModules(context: Context): List<File> {
        val dir = modulesDir(context)
        return dir.listFiles { file -> file.isFile && file.name.endsWith(".wasm", ignoreCase = true) }
            ?.sortedBy { it.name.lowercase() }
            ?: emptyList()
    }

    fun search(query: String): List<WasmCatalogPackage> {
        val q = query.trim().lowercase()
        return fetchIndex().filter { pkg ->
            q.isEmpty() ||
                pkg.name.lowercase().contains(q) ||
                pkg.summary.lowercase().contains(q)
        }
    }

    fun fetchIndex(): List<WasmCatalogPackage> {
        if (!isAllowedCatalogUrl(INDEX_URL)) {
            throw IllegalStateException("Wasm catalog only. Refusing a non /wasm/v1 URL.")
        }
        val body = httpGet(INDEX_URL)
        val root = JSONObject(body)
        val packages = root.optJSONArray("packages") ?: return emptyList()
        val out = ArrayList<WasmCatalogPackage>(packages.length())
        for (i in 0 until packages.length()) {
            val obj = packages.optJSONObject(i) ?: continue
            val name = obj.optString("name").trim()
            if (name.isEmpty()) continue
            out.add(
                WasmCatalogPackage(
                    name = name,
                    version = obj.optString("version"),
                    digest = obj.optString("digest"),
                    url = obj.optString("url"),
                    summary = obj.optString("summary"),
                )
            )
        }
        return out
    }

    fun download(context: Context, pkg: WasmCatalogPackage): File {
        val urlString = when {
            pkg.url.startsWith("https://") || pkg.url.startsWith("http://") -> pkg.url
            else -> "$CATALOG_BASE/${pkg.url.trimStart('/')}"
        }
        if (!isAllowedCatalogUrl(urlString)) {
            throw IllegalStateException("Wasm catalog only. Refusing a non /wasm/v1 URL.")
        }
        val bytes = httpGetBytes(urlString)
        if (bytes.size < 4 ||
            bytes[0] != 0x00.toByte() ||
            bytes[1] != 0x61.toByte() ||
            bytes[2] != 0x73.toByte() ||
            bytes[3] != 0x6d.toByte()
        ) {
            throw IllegalStateException("Download is not a Wasm module")
        }
        val dest = File(modulesDir(context), "${pkg.name}.wasm")
        dest.writeBytes(bytes)
        return dest
    }

    fun importUri(context: Context, uri: Uri): File {
        val hinted = uri.lastPathSegment?.substringAfterLast('/') ?: "imported.wasm"
        val destName = if (hinted.endsWith(".wasm", ignoreCase = true)) hinted else "$hinted.wasm"
        val dest = File(modulesDir(context), destName)
        context.contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Could not read the selected file")
        val bytes = dest.readBytes()
        if (bytes.size < 4 ||
            bytes[0] != 0x00.toByte() ||
            bytes[1] != 0x61.toByte() ||
            bytes[2] != 0x73.toByte() ||
            bytes[3] != 0x6d.toByte()
        ) {
            dest.delete()
            throw IllegalStateException("Selected file is not a Wasm module")
        }
        return dest
    }

    private fun httpGet(url: String): String = String(httpGetBytes(url), Charsets.UTF_8)

    private fun httpGetBytes(url: String): ByteArray {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = false
            requestMethod = "GET"
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) {
                throw IllegalStateException("Wasm catalog HTTP $code")
            }
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }
}
