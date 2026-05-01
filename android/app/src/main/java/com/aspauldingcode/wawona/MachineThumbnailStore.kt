package com.aspauldingcode.wawona

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.resume

object MachineThumbnailStore {
    private const val DIR_NAME = "machine-thumbnails"
    private const val MAX_WIDTH = 640
    private const val PNG_QUALITY = 92

    private fun fileFor(context: Context, machineId: String): File {
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return File(dir, "$machineId.png")
    }

    suspend fun captureFromWindow(context: Context, window: Window?, machineId: String): Boolean {
        if (window == null || machineId.isBlank()) return false
        return withContext(Dispatchers.Main) {
            try {
                val decor = window.decorView ?: return@withContext false
                val width = decor.width
                val height = decor.height
                if (width <= 0 || height <= 0) return@withContext false

                val source = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val copyResult = suspendCancellableCoroutine<Int> { cont ->
                    @Suppress("DEPRECATION")
                    PixelCopy.request(window, source, { result -> cont.resume(result) }, Handler(Looper.getMainLooper()))
                }
                if (copyResult != PixelCopy.SUCCESS) {
                    source.recycle()
                    return@withContext false
                }

                val scale = if (width > MAX_WIDTH) MAX_WIDTH.toFloat() / width.toFloat() else 1f
                val outBitmap = if (scale < 1f) {
                    Bitmap.createScaledBitmap(source, (width * scale).toInt(), (height * scale).toInt(), true)
                } else {
                    source
                }

                val output = fileFor(context, machineId)
                FileOutputStream(output).use { fos ->
                    outBitmap.compress(Bitmap.CompressFormat.PNG, PNG_QUALITY, fos)
                }

                if (outBitmap !== source) outBitmap.recycle()
                source.recycle()
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    fun load(context: Context, machineId: String): Bitmap? {
        val file = fileFor(context, machineId)
        if (!file.exists()) return null
        return BitmapFactory.decodeFile(file.absolutePath)
    }

    fun delete(context: Context, machineId: String) {
        fileFor(context, machineId).delete()
    }
}
