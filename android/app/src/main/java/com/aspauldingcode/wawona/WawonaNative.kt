package com.aspauldingcode.wawona

import android.view.Surface

object WawonaNative {
    init {
        try {
            // ANGLE SONAME is libEGL_angle.so / libGLESv2_angle.so. Load those
            // only. Never also load libEGL.so / libGLESv2.so as a second copy.
            System.loadLibrary("EGL_angle")
            System.loadLibrary("GLESv2_angle")
            WLog.d("NATIVE", "Loading native library 'wawona'")
            System.loadLibrary("wawona")
            WLog.d("NATIVE", "Native library 'wawona' loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            WLog.e("NATIVE", "Failed to load native library 'wawona': ${e.message}")
            throw e
        } catch (e: Exception) {
            WLog.e("NATIVE", "Unexpected error loading native library: ${e.message}")
            throw e
        }
    }

    external fun nativePrepareShellEnvironment(filesDir: String)

    external fun nativeInit(cacheDir: String)
    /**
     * Set `XKB_DEFAULT_LAYOUT` / `XKB_DEFAULT_VARIANT` before seat keyboard
     * init (follow-system; #60 / #141). Call before [nativeInit].
     */
    external fun nativeSetXkbDefaults(layout: String, variant: String)
    external fun nativeIsCompositorReady(): Boolean
    external fun nativeSetSurface(surface: Surface)
    /**
     * Tear down the Vulkan surface. Pass the dying [Surface] so a stale
     * SessionActivity cannot destroy a newer host task's swapchain (#141).
     */
    external fun nativeDestroySurface(surface: Surface?)
    /** Fast resize: recreate swapchain only, no full teardown. */
    external fun nativeResizeSurface(width: Int, height: Int)
    /** Lightweight output sync: update compositor output size without touching the render pipeline. */
    external fun nativeSyncOutputSize(width: Int, height: Int)
    external fun nativeShutdown()
    /** Set the Android display density for auto-scale computation (DisplayMetrics.density). */
    external fun nativeSetDisplayDensity(density: Float)
    external fun nativeUpdateSafeArea(left: Int, top: Int, right: Int, bottom: Int)
    external fun nativeApplySettings(
        forceServerSideDecorations: Boolean,
        autoRetinaScaling: Boolean,
        renderingBackend: Int,
        respectSafeArea: Boolean,
        renderMacOSPointer: Boolean,
        swapCmdAsCtrl: Boolean,
        universalClipboard: Boolean,
        colorSyncSupport: Boolean,
        nestedCompositorsSupport: Boolean,
        useMetal4ForNested: Boolean,
        multipleClients: Boolean,
        waypipeRSSupport: Boolean,
        enableTCPListener: Boolean,
        tcpPort: Int,
        vulkanDriver: String,
        openglDriver: String,
        compositorBackend: String
    )

    /** Apply environment override JSON: `{ "set": {...}, "unset": [...] }` (#157). */
    external fun nativeApplyEnvironmentOverrides(json: String)

    external fun nativeSetCore(corePtr: Long)

    external fun nativeCommitText(text: String)
    external fun nativePreeditText(text: String, cursorBegin: Int, cursorEnd: Int)
    external fun nativeDeleteSurroundingText(beforeLength: Int, afterLength: Int)

    external fun nativeGetCursorRect(outRect: IntArray)

    external fun nativeTouchDown(id: Int, x: Float, y: Float, timestampMs: Int)
    external fun nativeTouchUp(id: Int, timestampMs: Int)
    external fun nativeTouchMotion(id: Int, x: Float, y: Float, timestampMs: Int)
    external fun nativeTouchCancel()
    external fun nativeTouchFrame()

    external fun nativeKeyEvent(keycode: Int, state: Int, timestampMs: Int)
    /** Inject key by Linux evdev keycode (for accessory bar). */
    external fun nativeInjectKey(linuxKeycode: Int, pressed: Boolean, timestampMs: Int)
    /** Set XKB modifier state (for accessory bar sticky/locked modifiers). */
    external fun nativeInjectModifiers(depressed: Int, latched: Int, locked: Int, group: Int)
    external fun nativePointerAxis(axis: Int, value: Float, timestampMs: Int)
    external fun nativePointerMotion(x: Double, y: Double, timestampMs: Int)
    external fun nativePointerButton(buttonCode: Int, state: Int, timestampMs: Int)
    external fun nativePointerEnter(x: Double, y: Double, timestampMs: Int)
    external fun nativePointerLeave(timestampMs: Int)
    
    external fun injectDragEnter(windowId: Long, x: Double, y: Double, mimeTypes: String)
    external fun injectDragMotion(windowId: Long, x: Double, y: Double)
    external fun injectDragDrop(windowId: Long, data: String)
    external fun injectDragLeave(windowId: Long)

    external fun nativeKeyboardFocus(hasFocus: Boolean)
    /** Ask focused toplevel to close (`xdg_toplevel.close`). */
    external fun nativeRequestActiveWindowClose(): Boolean
    /** True once after a client MinimizeRequested; consumed on read. */
    external fun nativeConsumeMinimizeRequested(): Boolean
    /** Returns the toplevel that requested minimize, or 0 when none is pending. */
    external fun nativeConsumeMinimizedWindow(): Long
    /** Reserve the next mapped Wayland toplevel for an Android SessionActivity. */
    external fun nativeReserveNextHostWindow(hostId: Long)
    /** Returns the Wayland toplevel atomically claimed by this host task, or 0. */
    external fun nativeGetWindowForHost(hostId: Long): Long
    /** Send this SessionActivity's settled freeform bounds to its toplevel. */
    external fun nativeResizeHostWindow(hostId: Long, width: Int, height: Int)
    /** Sync task focus to the claimed Wayland toplevel. */
    external fun nativeSetHostWindowFocused(hostId: Long, focused: Boolean)
    /** Ask the toplevel in a closing host task to close gracefully. */
    external fun nativeCloseHostWindow(hostId: Long): Boolean
    /** Detach a destroyed Android SessionActivity from its toplevel claim. */
    external fun nativeReleaseHostWindow(hostId: Long)
    external fun nativeSetWindowActivated(windowId: Long, active: Boolean)
    external fun nativeGetFocusedWindowTitle(): String
    /** Push text copied on the native side (ClipboardManager) into the compositor so clients can paste it. */
    external fun nativeSetClipboardText(text: String)
    /** Pop text a Wayland client just copied, or null if nothing changed since the last poll. */
    external fun nativePollClipboardText(): String?
    /** True when a Wayland client has committed zwp_text_input_v3.enable (IME routing). */
    external fun nativeTextInputIsEnabled(): Boolean
    /** Soft OSK should expand: committed TI or terminal-focus synthesis. */
    external fun nativeTextEntryWanted(): Boolean
    /** Fills [hint, purpose] from committed zwp_text_input_v3.content_type. */
    external fun nativeGetTextInputContentType(outHintPurpose: IntArray)
    /** Returns capture_id if pending, else 0. Fills outWidthHeight with [width, height]. */
    external fun nativeGetPendingScreencopy(outWidthHeight: IntArray): Long
    external fun nativeScreencopyComplete(captureId: Long, pixels: ByteArray)
    external fun nativeScreencopyFailed(captureId: Long)
    external fun nativeGetPendingImageCopyCapture(outWidthHeight: IntArray): Long
    external fun nativeImageCopyCaptureComplete(captureId: Long, pixels: ByteArray)
    external fun nativeImageCopyCaptureFailed(captureId: Long)

    external fun nativeRunWaypipe(
        sshEnabled: Boolean,
        sshHost: String,
        sshUser: String,
        sshPassword: String,
        sshKeyPath: String,
        sshAuthMethod: Int,
        remoteCommand: String,
        compress: String,
        threads: Int,
        video: String,
        debug: Boolean,
        oneshot: Boolean,
        noGpu: Boolean,
        loginShell: Boolean,
        titlePrefix: String,
        secCtx: String
    ): Boolean

    external fun nativeStopWaypipe()
    external fun nativeIsWaypipeRunning(): Boolean

    external fun nativeRunWestonSimpleSHM(): Boolean
    external fun nativeStopWestonSimpleSHM()
    external fun nativeIsWestonSimpleSHMRunning(): Boolean
    external fun nativeRunWeston(): Boolean
    external fun nativeStopWeston()
    external fun nativeIsWestonRunning(): Boolean
    external fun nativeRunWestonTerminal(): Boolean
    external fun nativeStopWestonTerminal()
    external fun nativeIsWestonTerminalRunning(): Boolean
    external fun nativeRunFoot(): Boolean
    external fun nativeStopFoot()
    external fun nativeIsFootRunning(): Boolean

    external fun nativeRunBundledClient(clientId: String): Boolean
    external fun nativeStopBundledClient()
    external fun nativeIsBundledClientRunning(): Boolean
    external fun nativeGetRunningBundledClientId(): String?

    /** Fork/exec catalog client against nested niri Wayland socket (issue #78). */
    external fun nativeRunNestedWlClient(execName: String): Boolean

    /** Boot bundled mobile NixOS guest (QEMU/AVF when engine is embedded). */
    external fun nativeLaunchMobileVm(guestDir: String, memoryMb: Int): Boolean
    external fun nativeStopMobileVm()
    external fun nativeIsMobileVmRunning(): Boolean

    external fun nativeTestPing(host: String, port: Int, timeoutMs: Int): String
    external fun nativeTestSSH(
        host: String,
        user: String,
        password: String,
        port: Int,
        keyPath: String,
        authMethod: Int
    ): String
}
