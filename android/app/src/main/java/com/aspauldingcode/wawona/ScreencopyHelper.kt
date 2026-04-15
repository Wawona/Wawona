package com.aspauldingcode.wawona

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import java.nio.ByteBuffer

object ScreencopyHelper {
    suspend fun pollAndCapture(window: Window?) {
        if (window == null) return
        withContext(Dispatchers.Main) {
            pollOne(window, true)
            pollOne(window, false)
        }
    }
    private suspend fun pollOne(window: Window, screencopy: Boolean) {
        val whs = IntArray(3)
        val captureId = if (screencopy) {
            WawonaNative.nativeGetPendingScreencopy(whs)
        } else {
            WawonaNative.nativeGetPendingImageCopyCapture(whs)
        }
        if (captureId == 0L) return
        val width = whs[0]
        val height = whs[1]
        val dstStride = if (whs.size >= 3 && whs[2] > 0) whs[2] else width * 4
        if (width <= 0 || height <= 0) {
            if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
            else WawonaNative.nativeImageCopyCaptureFailed(captureId)
            return
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            val result = suspendCancellableCoroutine<Int> { cont ->
                @Suppress("DEPRECATION")
                PixelCopy.request(window, bitmap, { r -> cont.resume(r) }, Handler(Looper.getMainLooper()))
            }
            if (result == PixelCopy.SUCCESS) {
                val srcStride = bitmap.rowBytes
                val dstSize = dstStride * height
                val buf = ByteBuffer.allocate(bitmap.rowBytes * height)
                bitmap.copyPixelsToBuffer(buf)
                buf.rewind()
                val srcArr = ByteArray(buf.remaining())
                buf.get(srcArr)
                val dstArr = if (srcStride == dstStride) srcArr else {
                    val copyW = minOf(srcStride, dstStride)
                    ByteArray(dstSize).also { out ->
                        for (row in 0 until height) {
                            srcArr.copyInto(out, row * dstStride, row * srcStride, row * srcStride + copyW)
                        }
                    }
                }
                if (screencopy) WawonaNative.nativeScreencopyComplete(captureId, dstArr)
                else WawonaNative.nativeImageCopyCaptureComplete(captureId, dstArr)
            } else {
                if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
                else WawonaNative.nativeImageCopyCaptureFailed(captureId)
            }
        } catch (e: Exception) {
            WLog.e("SCREENCOPY", "PixelCopy failed: ''${e.message}")
            if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
            else WawonaNative.nativeImageCopyCaptureFailed(captureId)
        } finally {
            bitmap.recycle()
        }
    }
}
