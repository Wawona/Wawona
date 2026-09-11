package com.aspauldingcode.wawona.anowaw

/**
 * Thin JNI surface over the anowaW Rust bridge core (see include/anowaw.h and
 * platform/android/jni/anowaw_jni.c).
 *
 * IMPORTANT: the Rust C ABI is thread-affine. Every method here MUST be called
 * from the single bridge thread owned by [AnowawBridge]; do not call from the
 * main thread or arbitrary coroutines.
 */
object AnowawNative {
    init {
        // Packaged as libanowaw.so by dependencies/libs/anowaw/android.nix and
        // bundled into the Wawona APK jniLibs. The JNI glue is compiled into the
        // app's own .so, which links libanowaw.
        System.loadLibrary("anowaw_jni")
    }

    /** ABI version the linked core implements; must equal [ABI_VERSION]. */
    external fun nativeAbiVersion(): Int

    /** Connect to the nested Weston socket (e.g. "wayland-1"). 0 on failure. */
    external fun nativeStart(socketName: String): Long

    /** Register an app + create its Wayland toplevel. Returns handle or 0. */
    external fun nativeBridgeApp(bridge: Long, appId: String, title: String, width: Int, height: Int): Long

    /** Push one captured frame from a direct ByteBuffer. 0 on success. */
    external fun nativePushFrame(
        bridge: Long, appHandle: Long, buffer: java.nio.ByteBuffer,
        width: Int, height: Int, stride: Int, format: Int
    ): Int

    /** Drain up to [cap] input events into the caller-provided SoA arrays. */
    external fun nativePollInput(
        bridge: Long, handles: LongArray, meta: IntArray, coords: DoubleArray, cap: Int
    ): Int

    external fun nativeCloseRequested(bridge: Long, appHandle: Long): Int
    external fun nativeCloseApp(bridge: Long, appHandle: Long)
    external fun nativeDispatch(bridge: Long): Int
    external fun nativeStop(bridge: Long)

    const val ABI_VERSION = 1

    // Pixel formats (mirror Rust PixelFormat / anowaw.h).
    const val FORMAT_BGRA8888 = 0
    const val FORMAT_BGRX8888 = 1
    const val FORMAT_RGBA8888 = 2
    const val FORMAT_RGBX8888 = 3

    // Input kinds (mirror Rust InputKind / anowaw.h).
    const val INPUT_POINTER_MOTION = 0
    const val INPUT_POINTER_BUTTON = 1
    const val INPUT_POINTER_AXIS = 2
    const val INPUT_KEY = 3
    const val INPUT_TOUCH = 4
    const val INPUT_MODIFIERS = 5
    const val INPUT_POINTER_FOCUS = 6
}
