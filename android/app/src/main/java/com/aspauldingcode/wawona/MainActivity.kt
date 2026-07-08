package com.aspauldingcode.wawona

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.inputmethod.InputMethodManager
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowInsetsController
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Surface
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sqrt


class MainActivity : ComponentActivity(), SurfaceHolder.Callback {

    private lateinit var prefs: SharedPreferences
    private var surfaceReady = false
    private val resizeHandler = Handler(Looper.getMainLooper())
    private var pendingResize: Runnable? = null

    companion object {
        /** @deprecated Use [WawonaCompositorBackground] from theme. */
        @Deprecated("Use WawonaCompositorBackground")
        val CompositorBackground = WawonaCompositorBackground
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WLog.d("ACTIVITY", "onCreate started")

        try {
            WindowCompat.setDecorFitsSystemWindows(window, false)

            ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
                val displayCutout = insets.displayCutout
                val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())

                val left = maxOf(displayCutout?.safeInsetLeft ?: 0, systemBars.left)
                val top = maxOf(displayCutout?.safeInsetTop ?: 0, systemBars.top)
                val right = maxOf(displayCutout?.safeInsetRight ?: 0, systemBars.right)
                val bottom = maxOf(displayCutout?.safeInsetBottom ?: 0, systemBars.bottom)

                try {
                    WawonaNative.nativeUpdateSafeArea(left, top, right, bottom)
                } catch (e: Exception) {
                    WLog.e("ACTIVITY", "Error updating native safe area: ${e.message}")
                }

                insets
            }

            prefs = getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)



            setContent {
                WawonaTheme {
                    WawonaApp(
                        prefs = prefs,
                        surfaceCallback = this@MainActivity,
                        cacheDirPath = cacheDir.absolutePath,
                        displayDensity = resources.displayMetrics.density
                    )
                }
            }
        } catch (e: Exception) {
            WLog.e("ACTIVITY", "Fatal error in onCreate: ${e.message}")
            throw e
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // When Wawona holds the HOME role, pressing the Home button re-delivers a
        // MAIN/HOME intent to this already-running activity. Signal the Compose
        // tree so the desktop can surface the app drawer.
        val isHomeIntent = intent.action == android.content.Intent.ACTION_MAIN &&
            intent.categories?.contains(android.content.Intent.CATEGORY_HOME) == true
        if (isHomeIntent) {
            HomeIntentBus.signalHome()
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        WLog.d("SURFACE", "surfaceCreated (waiting for surfaceChanged with final dimensions)")
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        WLog.d("SURFACE", "surfaceChanged: format=$format, width=$width, height=$height")

        if (!surfaceReady) {
            try {
                WawonaNative.nativeSetSurface(holder.surface)
                surfaceReady = true
                WawonaNative.nativeSyncOutputSize(width, height)
                WawonaSettings.apply(prefs)
            } catch (e: Exception) {
                WLog.e("SURFACE", "Error in initial surfaceChanged: ${e.message}")
            }
            return
        }

        pendingResize?.let { resizeHandler.removeCallbacks(it) }
        val resize = Runnable {
            WLog.d("SURFACE", "Applying deferred resize: ${width}x${height}")
            try {
                WawonaNative.nativeResizeSurface(width, height)
                WawonaSettings.apply(prefs)
            } catch (e: Exception) {
                WLog.e("SURFACE", "Error in deferred surfaceChanged: ${e.message}")
            }
        }
        pendingResize = resize
        resizeHandler.postDelayed(resize, 200)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        WLog.d("SURFACE", "surfaceDestroyed")
        pendingResize?.let { resizeHandler.removeCallbacks(it) }
        pendingResize = null
        try {
            WawonaNative.nativeDestroySurface()
            surfaceReady = false
        } catch (e: Exception) {
            WLog.e("SURFACE", "Error in surfaceDestroyed: ${e.message}")
        }
    }

    override fun onDestroy() {
        WLog.d("ACTIVITY", "onDestroy — shutting down compositor core")
        try {
            WawonaNative.nativeShutdown()
        } catch (e: Exception) {
            WLog.e("ACTIVITY", "Error in nativeShutdown: ${e.message}")
        }
        super.onDestroy()
    }
}

private enum class KeyboardUiMode {
    HIDDEN_EXTERNAL,
    PIP_FLOATING,
    PIP_DOCKED_LEFT,
    PIP_DOCKED_RIGHT,
    ACCESSORY_ONLY,
    EXPANDED,
}

private fun KeyboardUiMode.isPip(): Boolean =
    this == KeyboardUiMode.PIP_FLOATING ||
        this == KeyboardUiMode.PIP_DOCKED_LEFT ||
        this == KeyboardUiMode.PIP_DOCKED_RIGHT

@Composable
fun WawonaApp(
    prefs: SharedPreferences,
    surfaceCallback: SurfaceHolder.Callback,
    cacheDirPath: String,
    displayDensity: Float
) {
    val context = LocalContext.current
    val activity = context as? ComponentActivity

    var profiles by remember { mutableStateOf(MachineProfileStore.loadProfiles(prefs)) }
    val sessionOrchestrator = remember { SessionOrchestrator() }
    var showMachinesHome by remember { mutableStateOf(true) }
    var showWelcome by remember { mutableStateOf(!prefs.getBoolean("hasSeenWelcome", false)) }
    var isWaypipeRunning by remember { mutableStateOf(false) }
    /* Startup log overlay. */
    var showStartupLog by remember { mutableStateOf(false) }
    var startupLogClientLabel by remember { mutableStateOf("") }
    val startupLogLines = remember { mutableStateOf(listOf<String>()) }
    var windowTitle by remember { mutableStateOf("") }
    val clipboardManager = remember {
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    }
    // Guards against the feedback loop: writing to ClipboardManager ourselves
    // (a client copied something) synchronously fires our own
    // OnPrimaryClipChangedListener, which would otherwise bounce that same
    // text right back into the compositor as if the user had copied it
    // natively. Set immediately before every self-triggered write, cleared
    // by the listener once it sees the matching change.
    var suppressNextClipboardChange by remember { mutableStateOf(false) }
    var nativeRuntimeReady by remember { mutableStateOf(false) }
    var showSettingsDialog by remember { mutableStateOf(false) }
    var thumbnailRevision by remember { mutableIntStateOf(0) }
    var surfaceViewRef by remember { mutableStateOf<WawonaSurfaceView?>(null) }
    var keyboardUiMode by remember { mutableStateOf(KeyboardUiMode.ACCESSORY_ONLY) }
    var keyboardUiModeBeforeExternal by remember { mutableStateOf(KeyboardUiMode.ACCESSORY_ONLY) }
    var pipButtonOffsetX by remember { mutableStateOf(16f) }
    var pipButtonOffsetY by remember { mutableStateOf(160f) }
    val appScope = rememberCoroutineScope()
    var shakeToCloseEnabled by remember {
        mutableStateOf(prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true))
    }
    var swipeBackToCloseEnabled by remember {
        mutableStateOf(prefs.getBoolean("wawona.pref.swipeBackToCloseEnabled", true))
    }
    var showSessionCloseDialog by remember { mutableStateOf(false) }
    var respectSafeArea by remember {
        mutableStateOf(prefs.getBoolean("respectSafeArea", true))
    }
    var desktopModeEnabled by remember {
        mutableStateOf(DesktopReplacement.isEnabled(prefs))
    }
    var desktopMachineId by remember {
        mutableStateOf(DesktopReplacement.desktopMachineId(prefs))
    }
    var showAppDrawer by remember { mutableStateOf(false) }
    val immersiveCompositorMode =
        !showWelcome && !showMachinesHome && sessionOrchestrator.activeSessionId != null

    var westonSimpleShmEnabled by remember {
        mutableStateOf(prefs.getBoolean("westonSimpleSHMEnabled", false))
    }
    var nativeWestonEnabled by remember {
        mutableStateOf(prefs.getBoolean("westonEnabled", false))
    }
    var nativeWestonTerminalEnabled by remember {
        mutableStateOf(prefs.getBoolean("westonTerminalEnabled", false))
    }

    fun isNativeClientRunning(clientId: String): Boolean = when (clientId) {
        "weston" -> WawonaNative.nativeIsWestonRunning()
        "weston-terminal" -> WawonaNative.nativeIsWestonTerminalRunning()
        "weston-simple-shm" -> WawonaNative.nativeIsWestonSimpleSHMRunning()
        "foot" -> WawonaNative.nativeIsFootRunning()
        else ->
            WawonaNative.nativeIsBundledClientRunning() &&
                WawonaNative.nativeGetRunningBundledClientId() == clientId
    }

    fun launchNativeClient(clientId: String): Boolean {
        if (isNativeClientRunning(clientId)) {
            return true
        }
        val launched = when (clientId) {
            "weston-simple-shm" -> WawonaNative.nativeRunWestonSimpleSHM()
            "weston" -> WawonaNative.nativeRunWeston()
            "weston-terminal" -> WawonaNative.nativeRunWestonTerminal()
            else -> WawonaNative.nativeRunBundledClient(clientId)
        }
        if (!launched) {
            Toast.makeText(
                context,
                "Failed to launch native app '$clientId'.",
                Toast.LENGTH_SHORT
            ).show()
            return false
        }
        WLog.i("NATIVE", "Launched native app '$clientId'")
        return true
    }

    fun stopNativeClient(clientId: String) {
        when (clientId) {
            "weston" -> WawonaNative.nativeStopWeston()
            "weston-terminal" -> WawonaNative.nativeStopWestonTerminal()
            "weston-simple-shm" -> WawonaNative.nativeStopWestonSimpleSHM()
            "foot" -> WawonaNative.nativeStopFoot()
            else -> {
                if (WawonaNative.nativeGetRunningBundledClientId() == clientId) {
                    WawonaNative.nativeStopBundledClient()
                }
            }
        }
    }

    fun stopWaypipe() {
        try {
            WawonaNative.nativeStopWaypipe()
            isWaypipeRunning = false
            WLog.i("WAYPIPE", "Waypipe stopped")
        } catch (e: Exception) {
            WLog.e("WAYPIPE", "Error stopping waypipe: ${e.message}")
            Toast.makeText(context, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    DisposableEffect(prefs) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { sp, key ->
            when (key) {
                "westonSimpleSHMEnabled" ->
                    westonSimpleShmEnabled = sp.getBoolean("westonSimpleSHMEnabled", false)
                "westonEnabled" ->
                    nativeWestonEnabled = sp.getBoolean("westonEnabled", false)
                "westonTerminalEnabled" ->
                    nativeWestonTerminalEnabled = sp.getBoolean("westonTerminalEnabled", false)
                "wawona.pref.shakeToCloseEnabled" ->
                    shakeToCloseEnabled = sp.getBoolean("wawona.pref.shakeToCloseEnabled", true)
                "wawona.pref.swipeBackToCloseEnabled" ->
                    swipeBackToCloseEnabled = sp.getBoolean("wawona.pref.swipeBackToCloseEnabled", true)
                "respectSafeArea" -> {
                    respectSafeArea = sp.getBoolean("respectSafeArea", true)
                    try {
                        WawonaSettings.apply(sp)
                    } catch (_: Exception) {
                    }
                    activity?.window?.decorView?.let { ViewCompat.requestApplyInsets(it) }
                }
                DesktopReplacement.KEY_ENABLED ->
                    desktopModeEnabled = DesktopReplacement.isEnabled(sp)
                DesktopReplacement.KEY_MACHINE_ID ->
                    desktopMachineId = DesktopReplacement.desktopMachineId(sp)
            }
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }

    LaunchedEffect(sessionOrchestrator.activeSessionId) {
        showSessionCloseDialog = false
    }

    /* Collect WLog sink lines into the startup log list while overlay is shown. */
    LaunchedEffect(showStartupLog) {
        if (showStartupLog) {
            startupLogLines.value = listOf()
            WLog.enableSink()
            WLog.sinkFlow.collectLatest { line ->
                startupLogLines.value = startupLogLines.value + line
            }
        } else {
            WLog.disableSink()
        }
    }

    /* Auto-dismiss startup log after a grace period once logs stop flowing. */
    LaunchedEffect(showStartupLog, startupLogLines.value.size) {
        if (!showStartupLog) return@LaunchedEffect
        /* Wait until there have been at least a few lines and then no new ones
         * for 2 s, indicating the client has fully started. */
        if (startupLogLines.value.size >= 3) {
            delay(2_000)
            if (showStartupLog) showStartupLog = false
        }
    }

    fun activeProfile(): MachineProfile? {
        val activeSession = sessionOrchestrator.activeSession() ?: return null
        return profiles.firstOrNull { it.id == activeSession.machineId }
    }

    suspend fun captureActiveThumbnail(profile: MachineProfile?) {
        if (profile == null || !SessionExitSettings.isThumbnailEnabled(prefs, profile)) return
        if (MachineThumbnailStore.captureFromSurface(surfaceViewRef, profile.id)) {
            thumbnailRevision += 1
        }
    }

    fun tearDownActiveSession(profile: MachineProfile?) {
        when (profile?.type) {
            MachineType.NATIVE -> stopNativeClient(profile.nativeLauncher.ifBlank { "weston-terminal" })
            MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> stopWaypipe()
            else -> stopWaypipe()
        }
        val activeId = sessionOrchestrator.activeSessionId
        if (activeId != null) {
            sessionOrchestrator.markDisconnected(activeId)
        }
        sessionOrchestrator.setActiveSession(null)
        showStartupLog = false
        showMachinesHome = true
    }

    fun requestSessionCloseConfirm() {
        showSessionCloseDialog = true
    }

    fun confirmSessionClose() {
        showSessionCloseDialog = false
        val profile = activeProfile()
        appScope.launch {
            captureActiveThumbnail(profile)
            tearDownActiveSession(profile)
        }
    }

    fun hideNativeKeyboard() {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val targetView = surfaceViewRef ?: (activity?.window?.currentFocus ?: activity?.window?.decorView)
        if (imm != null && targetView != null) {
            imm.hideSoftInputFromWindow(targetView.windowToken, 0)
        }
    }

    fun showNativeKeyboard() {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val targetView = surfaceViewRef ?: activity?.window?.decorView
        if (imm != null && targetView != null) {
            targetView.requestFocus()
            imm.showSoftInput(targetView, InputMethodManager.SHOW_IMPLICIT)
        }
    }



    DisposableEffect(showMachinesHome, sessionOrchestrator.activeSessionId) {
        if (showMachinesHome || sessionOrchestrator.activeSessionId == null) {
            onDispose {}
        } else {
            val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            val accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            if (sensorManager == null || accelerometer == null) {
                onDispose {}
            } else {
                val shakeThreshold = 13.0f
                val shakeDebounceMs = 1200L
                var lastShakeAtMs = 0L
                val shakeListener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        if (event.values.size < 3) return
                        val profile = activeProfile()
                        if (!SessionExitSettings.resolvedShakeEnabled(prefs, profile)) return
                        val x = event.values[0]
                        val y = event.values[1]
                        val z = event.values[2]
                        val magnitude = sqrt((x * x + y * y + z * z).toDouble()).toFloat()
                        val acceleration = abs(magnitude - SensorManager.GRAVITY_EARTH)
                        if (acceleration < shakeThreshold) return
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastShakeAtMs < shakeDebounceMs) return
                        lastShakeAtMs = now
                        requestSessionCloseConfirm()
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                    }
                }
                sensorManager.registerListener(
                    shakeListener,
                    accelerometer,
                    SensorManager.SENSOR_DELAY_UI
                )
                onDispose {
                    sensorManager.unregisterListener(shakeListener)
                }
            }
        }
    }

    DisposableEffect(immersiveCompositorMode) {
        val window = activity?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (controller != null) {
            if (immersiveCompositorMode) {
                controller.hide(WindowInsetsCompat.Type.systemBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(WindowInsetsCompat.Type.systemBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_DEFAULT
            }
        }
        onDispose {}
    }

    fun ensureNativeRuntimeReady(): Boolean {
        if (nativeRuntimeReady) {
            return true
        }
        return try {
            WawonaShellRootfs.ensureInstalled(context)
            WawonaNative.nativePrepareShellEnvironment(context.filesDir.absolutePath)
            WawonaNative.nativeInit(cacheDirPath)
            if (!WawonaNative.nativeIsCompositorReady()) {
                throw IllegalStateException("Wayland compositor did not start")
            }
            WawonaNative.nativeSetDisplayDensity(displayDensity)
            nativeRuntimeReady = true
            WLog.d("ACTIVITY", "native runtime initialized after machine connect")
            true
        } catch (e: Throwable) {
            WLog.e("ACTIVITY", "native runtime init failed: ${e.message}")
            val detail = e.message?.takeIf { it.isNotBlank() }
            val toastText = detail ?: "Failed to initialize compositor runtime"
            Toast.makeText(context, toastText, Toast.LENGTH_LONG).show()
            false
        }
    }

    LaunchedEffect(westonSimpleShmEnabled, nativeWestonEnabled, nativeWestonTerminalEnabled) {
        if (!nativeRuntimeReady) {
            return@LaunchedEffect
        }

        if (westonSimpleShmEnabled) {
            if (!WawonaNative.nativeIsWestonSimpleSHMRunning()) {
                if (WawonaNative.nativeRunWestonSimpleSHM()) {
                    WLog.i("WESTON", "weston-simple-shm launched")
                } else {
                    WLog.e("WESTON", "Failed to launch weston-simple-shm")
                }
            }
        } else if (WawonaNative.nativeIsWestonSimpleSHMRunning()) {
            WawonaNative.nativeStopWestonSimpleSHM()
            WLog.i("WESTON", "weston-simple-shm stopped")
        }

        if (nativeWestonEnabled) {
            if (!WawonaNative.nativeIsWestonRunning()) {
                if (WawonaNative.nativeRunWeston()) {
                    WLog.i("WESTON", "nested Weston compositor launched")
                } else {
                    WLog.e("WESTON", "Failed to launch nested Weston compositor")
                }
            }
        } else if (WawonaNative.nativeIsWestonRunning()) {
            WawonaNative.nativeStopWeston()
            WLog.i("WESTON", "nested Weston compositor stopped")
        }

        if (nativeWestonTerminalEnabled) {
            if (!WawonaNative.nativeIsWestonTerminalRunning()) {
                if (WawonaNative.nativeRunWestonTerminal()) {
                    WLog.i("WESTON", "weston-terminal launched")
                } else {
                    WLog.e("WESTON", "Failed to launch weston-terminal")
                }
            }
        } else if (WawonaNative.nativeIsWestonTerminalRunning()) {
            WawonaNative.nativeStopWestonTerminal()
            WLog.i("WESTON", "weston-terminal stopped")
        }
    }

    var hadWindow by remember { mutableStateOf(false) }
    var lastPolledOutputW by remember { mutableIntStateOf(0) }
    var lastPolledOutputH by remember { mutableIntStateOf(0) }

    // Native copy (another app, or text the user pasted from outside Wawona)
    // -> push into the compositor so Wayland clients (e.g. weston-terminal)
    // can paste it. Uses a real listener (not polling) since ClipboardManager
    // notifies listeners immediately when the primary clip changes.
    DisposableEffect(clipboardManager) {
        val listener = ClipboardManager.OnPrimaryClipChangedListener {
            if (suppressNextClipboardChange) {
                suppressNextClipboardChange = false
                return@OnPrimaryClipChangedListener
            }
            if (!prefs.getBoolean("universalClipboard", true)) {
                return@OnPrimaryClipChangedListener
            }
            val text = clipboardManager.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(context)
                ?.toString()
            if (!text.isNullOrEmpty()) {
                try {
                    WawonaNative.nativeSetClipboardText(text)
                } catch (_: Exception) {
                }
            }
        }
        clipboardManager.addPrimaryClipChangedListener(listener)
        onDispose { clipboardManager.removePrimaryClipChangedListener(listener) }
    }

    LaunchedEffect(Unit) {
        while (true) {
            try {
                val activeProfile = sessionOrchestrator.activeSession()?.let { active ->
                    profiles.firstOrNull { it.id == active.machineId }
                }
                isWaypipeRunning = when (activeProfile?.type) {
                    MachineType.NATIVE -> isNativeClientRunning(
                        activeProfile.nativeLauncher.ifBlank { "weston-terminal" }
                    )
                    MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> WawonaNative.nativeIsWaypipeRunning()
                    else -> false
                }
                windowTitle = WawonaNative.nativeGetFocusedWindowTitle()
                if (prefs.getBoolean("universalClipboard", true)) {
                    val clientText = WawonaNative.nativePollClipboardText()
                    if (!clientText.isNullOrEmpty()) {
                        suppressNextClipboardChange = true
                        clipboardManager.setPrimaryClip(ClipData.newPlainText("Wawona", clientText))
                    }
                }
                ScreencopyHelper.pollAndCapture(activity?.window)
                val hasWindow = windowTitle.isNotEmpty()
                if (hasWindow && !hadWindow) {
                    surfaceViewRef?.requestFocus()
                }
                val w = surfaceViewRef?.width ?: 0
                val h = surfaceViewRef?.height ?: 0
                if (w > 0 && h > 0 && (w != lastPolledOutputW || h != lastPolledOutputH)) {
                    lastPolledOutputW = w
                    lastPolledOutputH = h
                    try {
                        WawonaNative.nativeSyncOutputSize(w, h)
                        WawonaSettings.apply(prefs)
                    } catch (_: Exception) {
                    }
                }
                hadWindow = hasWindow
                if (windowTitle.isNotEmpty()) {
                    activity?.title = windowTitle
                    activity?.setTaskDescription(
                        android.app.ActivityManager.TaskDescription(windowTitle)
                    )
                }
            } catch (_: Exception) {
            }
            delay(500)
        }
    }

    fun launchWaypipe(): Boolean {
        val wpSshEnabled = prefs.getBoolean("waypipeSSHEnabled", true)
        val rawHost = prefs.getString("waypipeSSHHost", "") ?: ""
        val host = MachineInputSanitizer.sanitizeHost(rawHost)
        val port = MachineInputSanitizer.normalizePort(
            prefs.getString("waypipeSSHPort", "22") ?: "22"
        )
        val wpSshHost = if (host.isBlank()) host else "$host:$port"
        val wpSshUser = prefs.getString("waypipeSSHUser", "") ?: ""
        val wpRemoteCommand = prefs.getString("waypipeRemoteCommand", "") ?: ""
        val sshPassword = prefs.getString("waypipeSSHPassword", "") ?: ""
        val remoteCmd = wpRemoteCommand.ifEmpty { "weston-simple-shm" }
        val compress = prefs.getString("waypipeCompress", "lz4") ?: "lz4"
        val threads = (prefs.getString("waypipeThreads", "0") ?: "0").toIntOrNull() ?: 0
        val video = prefs.getString("waypipeVideo", "none") ?: "none"
        val debug = prefs.getBoolean("waypipeDebug", false)
        val oneshot = prefs.getBoolean("waypipeOneshot", false)
        val noGpu = prefs.getBoolean("waypipeDisableGpu", false)
        val loginShell = prefs.getBoolean("waypipeLoginShell", false)
        val titlePrefix = prefs.getString("waypipeTitlePrefix", "") ?: ""
        val secCtx = prefs.getString("waypipeSecCtx", "") ?: ""

        return try {
            if (WawonaNative.nativeIsWaypipeRunning()) {
                isWaypipeRunning = true
                return true
            }
            val launched = WawonaNative.nativeRunWaypipe(
                wpSshEnabled, wpSshHost, wpSshUser, sshPassword,
                remoteCmd, compress, threads, video,
                debug, oneshot || wpSshEnabled, noGpu,
                loginShell, titlePrefix, secCtx
            )
            if (launched) {
                isWaypipeRunning = true
                WLog.i("WAYPIPE", "Waypipe launched (ssh=$wpSshEnabled, host=$wpSshHost)")
                true
            } else {
                isWaypipeRunning = true
                WLog.i("WAYPIPE", "Waypipe already running")
                true
            }
        } catch (e: Exception) {
            WLog.e("WAYPIPE", "Error starting waypipe: ${e.message}")
            Toast.makeText(context, "Error: ${e.message}", Toast.LENGTH_LONG).show()
            false
        }
    }

    fun launchNativeMachine(profile: MachineProfile): Boolean {
        val launcher = profile.nativeLauncher.ifBlank { "weston-terminal" }
        return launchNativeClient(launcher)
    }

    fun connectMachine(profile: MachineProfile, sessionId: String? = null) {
        val targetSession = sessionId ?: sessionOrchestrator.startSession(profile).sessionId
        MachineProfileStore.applyMachineToPrefs(prefs, profile)
        MachineProfileStore.setActiveMachineId(prefs, profile.id)
        respectSafeArea = prefs.getBoolean("respectSafeArea", true)
        try {
            WawonaSettings.apply(prefs)
            activity?.window?.decorView?.let { ViewCompat.requestApplyInsets(it) }
        } catch (_: Exception) {
        }
        if (!ensureNativeRuntimeReady()) {
            sessionOrchestrator.markDegraded(targetSession, "Failed to initialize compositor runtime")
            return
        }
        val launched = when (profile.type) {
            MachineType.NATIVE -> launchNativeMachine(profile)
            MachineType.SSH_WAYPIPE -> launchWaypipe()
            MachineType.SSH_TERMINAL -> {
                val withTerminalCommand = profile.copy(
                    remoteCommand = profile.remoteCommand.ifBlank { "weston-simple-shm" }
                )
                MachineProfileStore.applyMachineToPrefs(prefs, withTerminalCommand)
                WawonaSettings.apply(prefs)
                launchWaypipe()
            }
            MachineType.VM, MachineType.CONTAINER -> AndroidMobileVmRunner.launch(context, profile)
        }

        if (launched) {
            sessionOrchestrator.markConnected(targetSession)
            sessionOrchestrator.setActiveSession(targetSession)
            /* App Bridge (anowaW): once the nested-Weston desktop machine is up,
             * attach the bridge so Android apps can be embedded as Wayland
             * windows. Only fires for an eligible desktop machine with the
             * feature enabled; no-op otherwise. */
            if (profile.isAppBridgeEligible &&
                DesktopReplacement.isAppBridgeEnabled(prefs)) {
                appScope.launch { AnowawSession.attach(context, prefs) }
            }
            /* Show startup log overlay before switching to compositor view. */
            val label = when (profile.type) {
                MachineType.NATIVE -> profile.nativeLauncher.ifBlank { "weston-terminal" }
                else -> profile.name.ifBlank { "Wayland client" }
            }
            startupLogClientLabel = label
            showStartupLog = true
            showMachinesHome = false
        } else {
            sessionOrchestrator.markDegraded(
                targetSession,
                "Launch unsupported or failed for ${profile.type.value}"
            )
        }
    }

    fun disconnectMachine(profile: MachineProfile) {
        val session = sessionOrchestrator.sessions.firstOrNull {
            it.machineId == profile.id &&
                (it.state == MachineSessionState.CONNECTED || it.state == MachineSessionState.CONNECTING)
        } ?: return
        appScope.launch {
            if (SessionExitSettings.isThumbnailEnabled(prefs, profile)) {
                if (MachineThumbnailStore.captureFromSurface(surfaceViewRef, profile.id)) {
                    thumbnailRevision += 1
                }
            }
            if (AnowawSession.isActive) AnowawSession.detach()
            when (profile.type) {
                MachineType.NATIVE -> stopNativeClient(profile.nativeLauncher)
                MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> stopWaypipe()
                MachineType.VM, MachineType.CONTAINER -> AndroidMobileVmRunner.stop()
            }
            sessionOrchestrator.markDisconnected(session.sessionId)
            if (sessionOrchestrator.activeSessionId == session.sessionId) {
                sessionOrchestrator.setActiveSession(null)
                showMachinesHome = true
            }
        }
    }

    fun focusMachine(profile: MachineProfile) {
        val session = sessionOrchestrator.sessions.firstOrNull {
            it.machineId == profile.id && it.state == MachineSessionState.CONNECTED
        } ?: return
        MachineProfileStore.applyMachineToPrefs(prefs, profile)
        MachineProfileStore.setActiveMachineId(prefs, profile.id)
        respectSafeArea = prefs.getBoolean("respectSafeArea", true)
        try {
            WawonaSettings.apply(prefs)
            activity?.window?.decorView?.let { ViewCompat.requestApplyInsets(it) }
        } catch (_: Exception) {
        }
        sessionOrchestrator.setActiveSession(session.sessionId)
        showMachinesHome = false
    }

    fun disconnectActiveSession() {
        confirmSessionClose()
    }

    /**
     * Desktop Replacement: connect the user-selected native "desktop" machine so
     * the running compositor becomes the Wayland desktop. Only native machines
     * are eligible; anything else is ignored.
     */
    fun launchDesktopMachine(): Boolean {
        val desktop = DesktopReplacement.resolveDesktopMachine(prefs, profiles) ?: return false
        val existing = sessionOrchestrator.sessions.firstOrNull {
            it.machineId == desktop.id && it.state == MachineSessionState.CONNECTED
        }
        if (existing != null) {
            focusMachine(desktop)
        } else {
            val session = sessionOrchestrator.startSession(desktop)
            connectMachine(desktop, session.sessionId)
        }
        return true
    }

    fun launchWaylandMachineFromDrawer(profile: MachineProfile) {
        showAppDrawer = false
        val existing = sessionOrchestrator.sessions.firstOrNull {
            it.machineId == profile.id && it.state == MachineSessionState.CONNECTED
        }
        if (existing != null) {
            focusMachine(profile)
        } else {
            val session = sessionOrchestrator.startSession(profile)
            connectMachine(profile, session.sessionId)
        }
    }

    fun launchAndroidAppFromDrawer(app: AndroidApp) {
        // When the App Bridge is active, open the app as a window inside the
        // Wayland desktop instead of full-screen. Fall back to a normal launch
        // if bridging is unavailable or disallowed (e.g. third-party app in the
        // Play-safe baseline tier).
        if (AnowawSession.isActive && AnowawSession.launchAppIntoDesktop(context, app)) {
            showAppDrawer = false
            return
        }
        if (!AndroidAppLauncher.launch(context, app.packageName)) {
            Toast.makeText(context, "Unable to launch ${app.label}", Toast.LENGTH_SHORT).show()
        } else {
            showAppDrawer = false
        }
    }

    /* On entering desktop mode with a valid native desktop machine, boot straight
     * into the Wayland desktop instead of the Machine Configuration grid. */
    LaunchedEffect(desktopModeEnabled, desktopMachineId, profiles, showWelcome) {
        if (showWelcome) return@LaunchedEffect
        if (!desktopModeEnabled) return@LaunchedEffect
        if (sessionOrchestrator.activeSessionId != null) return@LaunchedEffect
        if (DesktopReplacement.resolveDesktopMachine(prefs, profiles) != null && showMachinesHome) {
            launchDesktopMachine()
        }
    }

    /* HOME button (Wawona holding the launcher role) opens the app drawer over
     * the desktop, re-connecting the desktop machine if needed. */
    val homeTick by HomeIntentBus.homeTick
    LaunchedEffect(homeTick) {
        if (homeTick == 0) return@LaunchedEffect
        if (!desktopModeEnabled) return@LaunchedEffect
        if (sessionOrchestrator.activeSessionId == null) {
            launchDesktopMachine()
        }
        showAppDrawer = true
    }

    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val imeBottom = with(density) { WindowInsets.ime.getBottom(this) }
    val imeVisible = imeBottom > 0
    val safeAreaPadding = if (respectSafeArea) {
        WindowInsets.safeDrawing.asPaddingValues()
    } else {
        androidx.compose.foundation.layout.PaddingValues()
    }
    val systemBarBottomPx = with(density) { WindowInsets.systemBars.getBottom(this) }
    val systemBarBottomDp = with(density) { systemBarBottomPx.toDp() }
    val hardwareKeyboardActive =
        configuration.keyboard != Configuration.KEYBOARD_NOKEYS &&
            configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO
    val inSessionUi = !showWelcome && !showMachinesHome
    val showAccessoryBar =
        inSessionUi && !hardwareKeyboardActive && !keyboardUiMode.isPip()
    val showKeyboardPipButton =
        inSessionUi && !hardwareKeyboardActive && keyboardUiMode.isPip()

    LaunchedEffect(hardwareKeyboardActive, inSessionUi) {
        if (!inSessionUi) return@LaunchedEffect
        if (hardwareKeyboardActive) {
            if (keyboardUiMode != KeyboardUiMode.HIDDEN_EXTERNAL) {
                keyboardUiModeBeforeExternal = keyboardUiMode
            }
            keyboardUiMode = KeyboardUiMode.HIDDEN_EXTERNAL
            hideNativeKeyboard()
        } else if (keyboardUiMode == KeyboardUiMode.HIDDEN_EXTERNAL) {
            keyboardUiMode =
                if (keyboardUiModeBeforeExternal == KeyboardUiMode.HIDDEN_EXTERNAL) {
                    KeyboardUiMode.EXPANDED
                } else {
                    keyboardUiModeBeforeExternal
                }
        }
    }

    LaunchedEffect(keyboardUiMode, inSessionUi) {
        if (!inSessionUi) return@LaunchedEffect
        when (keyboardUiMode) {
            KeyboardUiMode.EXPANDED -> showNativeKeyboard()
            KeyboardUiMode.ACCESSORY_ONLY,
            KeyboardUiMode.HIDDEN_EXTERNAL,
            KeyboardUiMode.PIP_FLOATING,
            KeyboardUiMode.PIP_DOCKED_LEFT,
            KeyboardUiMode.PIP_DOCKED_RIGHT -> hideNativeKeyboard()
        }
    }

    LaunchedEffect(imeBottom, keyboardUiMode, inSessionUi, hardwareKeyboardActive) {
        if (!inSessionUi || hardwareKeyboardActive) return@LaunchedEffect
        if (imeVisible && !keyboardUiMode.isPip() &&
            keyboardUiMode != KeyboardUiMode.HIDDEN_EXTERNAL
        ) {
            if (keyboardUiMode != KeyboardUiMode.EXPANDED) {
                keyboardUiMode = KeyboardUiMode.EXPANDED
            }
        } else if (keyboardUiMode.isPip() && imeVisible) {
            keyboardUiMode = KeyboardUiMode.EXPANDED
        } else if (keyboardUiMode == KeyboardUiMode.EXPANDED && !imeVisible) {
            showNativeKeyboard()
        }
    }

    LaunchedEffect(Unit) {
        // Always start on Machines so startup is predictable.
        profiles = MachineProfileStore.loadProfiles(prefs)
    }

    if (showWelcome) {
        AppWelcomeScreen(
            onContinue = {
                prefs.edit().putBoolean("hasSeenWelcome", true).apply()
                showWelcome = false
            }
        )
    } else if (showMachinesHome) {
        MachineWelcomeScreen(
            profiles = profiles,
            thumbnailRevision = thumbnailRevision,
            activeMachineId = MachineProfileStore.getActiveMachineId(prefs),
            machineStatusFor = { machineId -> sessionOrchestrator.statusForMachine(machineId) },
            onCreate = { profile ->
                profiles = MachineProfileStore.upsertProfile(prefs, profile)
            },
            onUpdate = { profile ->
                profiles = MachineProfileStore.upsertProfile(prefs, profile)
            },
            onDelete = { profile ->
                profiles = MachineProfileStore.deleteProfile(prefs, profile.id)
                MachineThumbnailStore.delete(context, profile.id)
                thumbnailRevision += 1
                sessionOrchestrator.sessions
                    .filter { it.machineId == profile.id }
                    .forEach { sessionOrchestrator.removeSession(it.sessionId) }
            },
            onConnect = { profile ->
                val session = sessionOrchestrator.startSession(profile)
                connectMachine(profile, session.sessionId)
            },
            onFocus = { profile -> focusMachine(profile) },
            onStop = { profile -> disconnectMachine(profile) },
            onOpenSettings = { showSettingsDialog = true }
        )
    } else {
        // In desktop mode, Back is a launcher gesture: open the app drawer instead
        // of tearing down the desktop session.
        BackHandler(enabled = desktopModeEnabled && !showAppDrawer) {
            showAppDrawer = true
        }
        BackHandler(enabled = !desktopModeEnabled && inSessionUi) {
            if (SessionExitSettings.resolvedSwipeBackEnabled(prefs, activeProfile())) {
                requestSessionCloseConfirm()
            } else {
                appScope.launch {
                    captureActiveThumbnail(activeProfile())
                    tearDownActiveSession(activeProfile())
                }
            }
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(LocalWawonaCompositorBackground.current)
        ) {
            // Respect safe area by inset-padding the compositor (iOS
            // safeAreaLayoutGuide parity). wl_output size follows the padded
            // surface; do not also crop via native safe_area_insets.
            AndroidView(
                factory = { ctx: Context ->
                    WawonaCompositorContainer(ctx).apply {
                        surfaceView.holder.addCallback(surfaceCallback)
                    }
                },
                update = { container -> surfaceViewRef = container.surfaceView },
                modifier = Modifier
                    .fillMaxSize()
                    .padding(safeAreaPadding)
                    .testTag(WawonaTestTags.COMPOSITOR_SURFACE)
            )

            if (desktopModeEnabled) {
                Surface(
                    onClick = { showAppDrawer = true },
                    shape = RoundedCornerShape(24.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.85f),
                    shadowElevation = 6.dp,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .statusBarsPadding()
                        .padding(start = 12.dp, top = 8.dp)
                        .testTag(WawonaTestTags.APP_DRAWER_OPEN),
                ) {
                    Box(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Filled.Apps,
                            contentDescription = "Open app drawer",
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            if (showAccessoryBar) {
                val safeLeftDp = if (respectSafeArea) {
                    with(density) { WindowInsets.safeDrawing.getLeft(this, LayoutDirection.Ltr).toDp() }
                } else {
                    0.dp
                }
                val safeRightDp = if (respectSafeArea) {
                    with(density) { WindowInsets.safeDrawing.getRight(this, LayoutDirection.Ltr).toDp() }
                } else {
                    0.dp
                }
                val accessoryBottomPadding = when {
                    imeVisible -> with(density) { imeBottom.toDp() }
                    keyboardUiMode == KeyboardUiMode.EXPANDED -> systemBarBottomDp
                    else -> systemBarBottomDp + 8.dp
                }
                ModifierAccessoryBar(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(
                            start = safeLeftDp,
                            end = safeRightDp,
                            bottom = accessoryBottomPadding
                        )
                        .fillMaxWidth(),
                    keyboardExpanded = keyboardUiMode == KeyboardUiMode.EXPANDED,
                    onToggleKeyboardExpanded = {
                        keyboardUiMode =
                            if (keyboardUiMode == KeyboardUiMode.EXPANDED) {
                                KeyboardUiMode.ACCESSORY_ONLY
                            } else {
                                KeyboardUiMode.EXPANDED
                            }
                    },
                    onCollapseToPipByDrag = {
                        keyboardUiMode = KeyboardUiMode.PIP_FLOATING
                    }
                )
            }

            if (showKeyboardPipButton) {
                BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                    val pipDocked = keyboardUiMode == KeyboardUiMode.PIP_DOCKED_LEFT ||
                        keyboardUiMode == KeyboardUiMode.PIP_DOCKED_RIGHT
                    val pipWidthDp = if (pipDocked) 30.dp else 56.dp
                    val pipHeightDp = 42.dp
                    val pipWidthPx = with(density) { pipWidthDp.toPx() }
                    val pipHeightPx = with(density) { pipHeightDp.toPx() }
                    val maxX = (constraints.maxWidth - pipWidthPx).coerceAtLeast(0f)
                    val maxY = (constraints.maxHeight - pipHeightPx).coerceAtLeast(0f)
                    val bottomInsetPx = maxOf(
                        with(density) { 16.dp.toPx() },
                        systemBarBottomPx.toFloat() + with(density) { 8.dp.toPx() }
                    )
                    val clampedYMax = (maxY - bottomInsetPx).coerceAtLeast(0f)
                    pipButtonOffsetX = pipButtonOffsetX.coerceIn(
                        if (keyboardUiMode == KeyboardUiMode.PIP_DOCKED_LEFT) {
                            with(density) { (-14).dp.toPx() }
                        } else {
                            0f
                        },
                        if (keyboardUiMode == KeyboardUiMode.PIP_DOCKED_RIGHT) {
                            (constraints.maxWidth - with(density) { 16.dp.toPx() }).coerceAtLeast(0f)
                        } else {
                            maxX
                        }
                    )
                    pipButtonOffsetY = pipButtonOffsetY.coerceIn(0f, clampedYMax)

                    TextButton(
                        onClick = { keyboardUiMode = KeyboardUiMode.ACCESSORY_ONLY },
                        modifier = Modifier
                            .offset {
                                IntOffset(
                                    pipButtonOffsetX.roundToInt(),
                                    pipButtonOffsetY.roundToInt()
                                )
                            }
                            .pointerInput(maxX, clampedYMax) {
                                detectDragGestures(
                                    onDragStart = {
                                        keyboardUiMode = KeyboardUiMode.PIP_FLOATING
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        pipButtonOffsetX =
                                            (pipButtonOffsetX + dragAmount.x).coerceIn(0f, maxX)
                                        pipButtonOffsetY =
                                            (pipButtonOffsetY + dragAmount.y).coerceIn(0f, clampedYMax)
                                    },
                                    onDragEnd = {
                                        val dockThreshold = with(density) { 28.dp.toPx() }
                                        keyboardUiMode = when {
                                            pipButtonOffsetX <= dockThreshold -> {
                                                pipButtonOffsetX = with(density) { (-14).dp.toPx() }
                                                KeyboardUiMode.PIP_DOCKED_LEFT
                                            }
                                            pipButtonOffsetX >= maxX - dockThreshold -> {
                                                pipButtonOffsetX = (constraints.maxWidth - with(density) { 16.dp.toPx() })
                                                    .coerceAtLeast(0f)
                                                KeyboardUiMode.PIP_DOCKED_RIGHT
                                            }
                                            else -> KeyboardUiMode.PIP_FLOATING
                                        }
                                    }
                                )
                            }
                            .background(
                                MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.78f),
                                RoundedCornerShape(24.dp)
                            )
                            .size(width = pipWidthDp, height = pipHeightDp)
                    ) {
                        Text(
                            when (keyboardUiMode) {
                                KeyboardUiMode.PIP_DOCKED_LEFT -> "›"
                                KeyboardUiMode.PIP_DOCKED_RIGHT -> "‹"
                                else -> "⌨"
                            }
                        )
                    }
                }
            }

            if (showStartupLog) {
                StartupLogOverlay(
                    clientLabel = startupLogClientLabel,
                    lines = startupLogLines.value,
                    onDismiss = { showStartupLog = false },
                    modifier = Modifier.align(Alignment.Center)
                )
            }

        }
    }

    if (showSettingsDialog) {
        SettingsDialog(
            prefs = prefs,
            onDismiss = { showSettingsDialog = false },
            onApply = {
                WawonaSettings.apply(prefs)
            }
        )
    }

    if (showAppDrawer) {
        BackHandler(enabled = true) { showAppDrawer = false }
        AppDrawer(
            waylandMachines = profiles.filter { DesktopReplacement.isEligible(it) },
            onLaunchWaylandMachine = { launchWaylandMachineFromDrawer(it) },
            onLaunchAndroidApp = { launchAndroidAppFromDrawer(it) },
            onDismiss = { showAppDrawer = false },
        )
    }

    if (showSessionCloseDialog) {
        AlertDialog(
            onDismissRequest = { showSessionCloseDialog = false },
            title = { Text("Close current Wayland app?") },
            text = {
                Text("This will disconnect the active machine session and return to Machine Configuration.")
            },
            confirmButton = {
                TextButton(onClick = { confirmSessionClose() }) {
                    Text("Close")
                }
            },
            dismissButton = {
                TextButton(onClick = { showSessionCloseDialog = false }) {
                    Text("Cancel")
                }
            },
        )
    }

    LaunchedEffect(isWaypipeRunning) {
        if (!isWaypipeRunning) {
            sessionOrchestrator.activeSessionId?.let { activeId ->
                val active = sessionOrchestrator.activeSession()
                if (active != null && active.state == MachineSessionState.CONNECTED) {
                    sessionOrchestrator.markDisconnected(activeId)
                }
            }
        }
    }
}

/**
 * Startup log overlay — shown between "Run" and the first compositor frame.
 *
 * Displays a native scrollable text view (LazyColumn of log lines) with a
 * frosted-glass card.  The user can long-press to select and copy text.
 * Auto-dismissed by the caller when [showStartupLog] is set to false.
 */
@Composable
private fun StartupLogOverlay(
    clientLabel: String,
    lines: List<String>,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    /* Auto-scroll to the latest entry. */
    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) {
            listState.animateScrollToItem(lines.size - 1)
        }
    }

    Surface(
        modifier = modifier
            .fillMaxWidth(0.92f)
            .fillMaxSize(0.72f),
        shape = RoundedCornerShape(16.dp),
        color = Color(0xDD121212),
        tonalElevation = 8.dp,
        shadowElevation = 12.dp,
    ) {
        Column(modifier = Modifier.padding(0.dp)) {
            /* Header */
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .padding(end = 10.dp)
                            .height(18.dp)
                            .fillMaxWidth(0.05f),
                        strokeWidth = 2.dp,
                        color = Color(0xFF4CAF50),
                    )
                    Text(
                        text = "Starting $clientLabel",
                        style = TextStyle(
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                }
                TextButton(onClick = onDismiss) {
                    Text("Done", color = Color(0xFF90CAF9), fontSize = 13.sp)
                }
            }

            HorizontalDivider(color = Color(0x33FFFFFF), thickness = 0.5.dp)

            /* Log lines — selectable for copy */
            SelectionContainer {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .background(Color(0xFF0A0A0A))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                ) {
                    items(lines) { line ->
                        Text(
                            text = line,
                            style = TextStyle(
                                color = Color(0xFF69FF74),
                                fontSize = 11.5.sp,
                                fontFamily = FontFamily.Monospace,
                                lineHeight = 18.sp,
                            ),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    if (lines.isEmpty()) {
                        item {
                            Text(
                                text = "Waiting for log output…",
                                style = TextStyle(
                                    color = Color(0xFF888888),
                                    fontSize = 11.5.sp,
                                    fontFamily = FontFamily.Monospace,
                                ),
                            )
                        }
                    }
                }
            }

            HorizontalDivider(color = Color(0x33FFFFFF), thickness = 0.5.dp)
            Text(
                text = "Long-press to select • auto-dismisses on first frame",
                style = TextStyle(color = Color(0xFF666666), fontSize = 10.sp),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun AppWelcomeScreen(onContinue: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .padding(horizontal = 28.dp, vertical = 24.dp)
    ) {
        Column(
            modifier = Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = "Welcome to Wawona",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onBackground,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "A clean Wayland compositor experience.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.78f)
            )
            Spacer(modifier = Modifier.height(6.dp))
            Button(onClick = onContinue) {
                Text("Continue")
            }
        }
    }
}
