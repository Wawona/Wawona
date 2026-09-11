package com.aspauldingcode.wawona.anowaw

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer

/**
 * anowaW Android bridge controller.
 *
 * Owns the single bridge thread (the Rust C ABI is thread-affine), the map of
 * bridged apps, and per-app capture pipelines. Two capture tiers exist:
 *
 *  * **Baseline (Play-safe)** — [AnowawProjectionService] mirrors the display
 *    via MediaProjection with per-session user consent, and own-app activities
 *    can be launched onto app-owned [VirtualDisplay]s. Third-party embedding is
 *    NOT possible here (Android throws SecurityException for
 *    setLaunchDisplayId on another app's activity).
 *  * **Power mode (Shizuku/root)** — see [AnowawPowerController]; unlocks
 *    trusted virtual displays + arbitrary app launch. Gated behind explicit
 *    opt-in and clearly labeled as non-Play.
 *
 * This class implements the common machinery both tiers share: bridge lifecycle,
 * ImageReader→ByteBuffer frame push, and input event polling → re-injection.
 */
class AnowawBridge private constructor(
    private val context: Context,
    private val socketName: String,
) {
    companion object {
        private const val TAG = "anowaW"
        private const val POLL_CAP = 256

        /** Connect the bridge to [socketName] (nested Weston, e.g. "wayland-1"). */
        fun connect(context: Context, socketName: String): AnowawBridge? {
            if (AnowawNative.nativeAbiVersion() != AnowawNative.ABI_VERSION) {
                Log.e(TAG, "ABI mismatch: ${AnowawNative.nativeAbiVersion()}")
                return null
            }
            val bridge = AnowawBridge(context.applicationContext, socketName)
            return if (bridge.startThread()) bridge else null
        }
    }

    private data class App(
        val handle: Long,
        val packageName: String,
        var virtualDisplay: VirtualDisplay? = null,
        var imageReader: ImageReader? = null,
        var surface: Surface? = null,
        var width: Int = 0,
        var height: Int = 0,
    )

    @Volatile private var corePtr: Long = 0L
    @Volatile private var running = false
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private val apps = HashMap<Long, App>()

    // Preallocated poll buffers, reused each pump (bridge thread only).
    private val pollHandles = LongArray(POLL_CAP)
    private val pollMeta = IntArray(POLL_CAP * 4)
    private val pollCoords = DoubleArray(POLL_CAP * 2)

    /** Callback invoked (on the bridge thread) for each decoded input event so
     * the tier-specific injector (own-app dispatch vs. privileged InputManager)
     * can re-inject it into the target app. */
    var inputSink: ((AnowawInputEvent) -> Unit)? = null

    private fun startThread(): Boolean {
        thread = HandlerThread("anowaw-bridge").also { it.start() }
        handler = Handler(thread.looper)
        var ok = false
        val latch = java.util.concurrent.CountDownLatch(1)
        handler.post {
            corePtr = AnowawNative.nativeStart(socketName)
            ok = corePtr != 0L
            latch.countDown()
            if (ok) {
                running = true
                pump()
            }
        }
        latch.await()
        if (!ok) Log.e(TAG, "nativeStart failed for socket $socketName")
        return ok
    }

    // Self-reposting pump loop on the bridge thread.
    private fun pump() {
        if (!running || corePtr == 0L) return
        AnowawNative.nativeDispatch(corePtr)
        val n = AnowawNative.nativePollInput(corePtr, pollHandles, pollMeta, pollCoords, POLL_CAP)
        for (i in 0 until n) {
            val ev = AnowawInputEvent(
                handle = pollHandles[i],
                kind = pollMeta[i * 4 + 0],
                code = pollMeta[i * 4 + 1],
                value = pollMeta[i * 4 + 2],
                timeMs = pollMeta[i * 4 + 3],
                x = pollCoords[i * 2 + 0],
                y = pollCoords[i * 2 + 1],
            )
            inputSink?.invoke(ev)
        }
        // Close-requested toplevels.
        val toClose = apps.keys.filter { AnowawNative.nativeCloseRequested(corePtr, it) == 1 }
        toClose.forEach { closeApp(it) }
        handler.postDelayed(::pump, 8L) // ~120 Hz
    }

    /**
     * Create a Wayland toplevel + an app-owned [VirtualDisplay] whose [Surface]
     * is captured through an [ImageReader]. Returns the anowaW app handle.
     *
     * The caller is responsible for launching the activity onto the returned
     * display id (own-app in baseline; arbitrary app in power mode).
     */
    fun createDisplay(
        packageName: String,
        title: String,
        width: Int,
        height: Int,
        densityDpi: Int,
        onFrameReady: ((displayId: Int, handle: Long) -> Unit)? = null,
    ): Long {
        var handle = 0L
        runOnBridgeSync {
            handle = AnowawNative.nativeBridgeApp(corePtr, packageName, title, width, height)
            if (handle == 0L) return@runOnBridgeSync

            val reader = ImageReader.newInstance(
                width, height, android.graphics.PixelFormat.RGBA_8888, 3
            )
            val app = App(handle, packageName, imageReader = reader,
                surface = reader.surface, width = width, height = height)

            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val vd = dm.createVirtualDisplay(
                "anowaw-$packageName",
                width, height, densityDpi,
                reader.surface,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY or
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION,
            )
            app.virtualDisplay = vd
            apps[handle] = app

            reader.setOnImageAvailableListener({ r ->
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val plane = image.planes[0]
                    val buf: ByteBuffer = plane.buffer
                    AnowawNative.nativePushFrame(
                        corePtr, handle, buf,
                        image.width, image.height, plane.rowStride,
                        AnowawNative.FORMAT_RGBA8888,
                    )
                } finally {
                    image.close()
                }
            }, handler)

            onFrameReady?.invoke(vd.display.displayId, handle)
        }
        return handle
    }

    /** Display id backing a bridged app (for ActivityOptions.setLaunchDisplayId). */
    fun displayIdFor(handle: Long): Int =
        apps[handle]?.virtualDisplay?.display?.displayId ?: android.view.Display.INVALID_DISPLAY

    fun closeApp(handle: Long) {
        runOnBridgeSync {
            apps.remove(handle)?.let { app ->
                app.virtualDisplay?.release()
                app.imageReader?.close()
                app.surface?.release()
                AnowawNative.nativeCloseApp(corePtr, handle)
            }
        }
    }

    fun stop() {
        running = false
        runOnBridgeSync {
            apps.keys.toList().forEach { h ->
                apps.remove(h)?.let {
                    it.virtualDisplay?.release()
                    it.imageReader?.close()
                }
            }
            if (corePtr != 0L) {
                AnowawNative.nativeStop(corePtr)
                corePtr = 0L
            }
        }
        thread.quitSafely()
    }

    private fun runOnBridgeSync(block: () -> Unit) {
        if (Thread.currentThread() === thread) { block(); return }
        val latch = java.util.concurrent.CountDownLatch(1)
        handler.post { try { block() } finally { latch.countDown() } }
        latch.await()
    }
}

/** Decoded input event handed to [AnowawBridge.inputSink]. */
data class AnowawInputEvent(
    val handle: Long,
    val kind: Int,
    val code: Int,
    val value: Int,
    val timeMs: Int,
    val x: Double,
    val y: Double,
)
