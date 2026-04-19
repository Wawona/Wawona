package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.sqrt

private object WawonaBackPressBridge {
    @Volatile
    var interceptEnabled: Boolean = false
    var token by mutableIntStateOf(0)

    fun emitBackPress() {
        token += 1
    }
}

class MainActivity : ComponentActivity(), SurfaceHolder.Callback {

    private lateinit var prefs: SharedPreferences
    private var surfaceReady = false
    private val resizeHandler = Handler(Looper.getMainLooper())
    private var pendingResize: Runnable? = null

    companion object {
        val CompositorBackground = Color(0xFF0F1018)
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

            onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    if (WawonaBackPressBridge.interceptEnabled) {
                        WawonaBackPressBridge.emitBackPress()
                        return
                    }
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                    isEnabled = true
                }
            })

            setContent {
                WawonaTheme(darkTheme = true) {
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
    var windowTitle by remember { mutableStateOf("") }
    var nativeRuntimeReady by remember { mutableStateOf(false) }
    var showSettingsDialog by remember { mutableStateOf(false) }
    var shakeToCloseEnabled by remember {
        mutableStateOf(prefs.getBoolean("wawona.pref.shakeToCloseEnabled", true))
    }
    var suppressShakeBackWarning by remember {
        mutableStateOf(prefs.getBoolean("wawona.pref.suppressShakeBackWarning", false))
    }
    var shakeBackWarningShownForSession by remember { mutableStateOf(false) }
    var showShakeBackWarningDialog by remember { mutableStateOf(false) }
    var respectSafeArea by remember {
        mutableStateOf(prefs.getBoolean("respectSafeArea", true))
    }
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
                "wawona.pref.suppressShakeBackWarning" ->
                    suppressShakeBackWarning = sp.getBoolean("wawona.pref.suppressShakeBackWarning", false)
                "respectSafeArea" -> {
                    respectSafeArea = sp.getBoolean("respectSafeArea", true)
                    try {
                        WawonaSettings.apply(sp)
                    } catch (_: Exception) {
                    }
                    activity?.window?.decorView?.let { ViewCompat.requestApplyInsets(it) }
                }
            }
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }

    LaunchedEffect(sessionOrchestrator.activeSessionId) {
        shakeBackWarningShownForSession = false
        showShakeBackWarningDialog = false
    }

    DisposableEffect(showWelcome, showMachinesHome) {
        WawonaBackPressBridge.interceptEnabled = !showWelcome && !showMachinesHome
        onDispose {
            WawonaBackPressBridge.interceptEnabled = false
        }
    }

    DisposableEffect(showMachinesHome, shakeToCloseEnabled, sessionOrchestrator.activeSessionId) {
        if (showMachinesHome || !shakeToCloseEnabled || sessionOrchestrator.activeSessionId == null) {
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
                        val x = event.values[0]
                        val y = event.values[1]
                        val z = event.values[2]
                        val magnitude = sqrt((x * x + y * y + z * z).toDouble()).toFloat()
                        val acceleration = abs(magnitude - SensorManager.GRAVITY_EARTH)
                        if (acceleration < shakeThreshold) return
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastShakeAtMs < shakeDebounceMs) return
                        lastShakeAtMs = now
                        val activeId = sessionOrchestrator.activeSessionId ?: return
                        val activeSession = sessionOrchestrator.activeSession()
                        val activeProfile = activeSession?.let { session ->
                            profiles.firstOrNull { it.id == session.machineId }
                        }
                        when (activeProfile?.type) {
                            MachineType.NATIVE -> {
                                when (activeProfile.nativeLauncher.ifBlank { "weston-simple-shm" }) {
                                    "weston" -> WawonaNative.nativeStopWeston()
                                    "weston-terminal" -> WawonaNative.nativeStopWestonTerminal()
                                    "foot" -> WawonaNative.nativeStopFoot()
                                    else -> WawonaNative.nativeStopWestonSimpleSHM()
                                }
                            }
                            MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> {
                                WawonaNative.nativeStopWaypipe()
                                isWaypipeRunning = false
                            }
                            else -> {
                                WawonaNative.nativeStopWaypipe()
                                isWaypipeRunning = false
                            }
                        }
                        sessionOrchestrator.markDisconnected(activeId)
                        sessionOrchestrator.setActiveSession(null)
                        showMachinesHome = true
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
            WawonaNative.nativeInit(cacheDirPath)
            WawonaNative.nativeSetDisplayDensity(displayDensity)
            nativeRuntimeReady = true
            WLog.d("ACTIVITY", "native runtime initialized after machine connect")
            true
        } catch (e: Exception) {
            WLog.e("ACTIVITY", "native runtime init failed: ${e.message}")
            Toast.makeText(context, "Failed to initialize compositor runtime", Toast.LENGTH_LONG).show()
            false
        }
    }

    LaunchedEffect(westonSimpleShmEnabled, nativeWestonEnabled, nativeWestonTerminalEnabled) {
        if (!nativeRuntimeReady) {
            return@LaunchedEffect
        }
        val shouldRunCompatClient =
            westonSimpleShmEnabled || nativeWestonEnabled || nativeWestonTerminalEnabled
        val isRunning = WawonaNative.nativeIsWestonSimpleSHMRunning()

        if (shouldRunCompatClient && !isRunning) {
            val launched = WawonaNative.nativeRunWestonSimpleSHM()
            if (launched) {
                WLog.i(
                    "WESTON",
                    "Compatibility Weston client launched (simple-shm backend)"
                )
            } else {
                WLog.e("WESTON", "Failed to launch compatibility Weston client")
            }
        } else if (!shouldRunCompatClient && isRunning) {
            WawonaNative.nativeStopWestonSimpleSHM()
            WLog.i("WESTON", "Compatibility Weston client stopped")
        }
    }

    var surfaceViewRef by remember { mutableStateOf<WawonaSurfaceView?>(null) }
    var hadWindow by remember { mutableStateOf(false) }
    var lastPolledOutputW by remember { mutableIntStateOf(0) }
    var lastPolledOutputH by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        while (true) {
            try {
                val activeProfile = sessionOrchestrator.activeSession()?.let { active ->
                    profiles.firstOrNull { it.id == active.machineId }
                }
                isWaypipeRunning = when (activeProfile?.type) {
                    MachineType.NATIVE -> when (activeProfile.nativeLauncher.ifBlank { "weston-simple-shm" }) {
                        "weston" -> WawonaNative.nativeIsWestonRunning()
                        "weston-terminal" -> WawonaNative.nativeIsWestonTerminalRunning()
                        "foot" -> WawonaNative.nativeIsFootRunning()
                        else -> WawonaNative.nativeIsWestonSimpleSHMRunning()
                    }
                    MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> WawonaNative.nativeIsWaypipeRunning()
                    else -> false
                }
                windowTitle = WawonaNative.nativeGetFocusedWindowTitle()
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
        val wpSshHost = prefs.getString("waypipeSSHHost", "") ?: ""
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
                Toast.makeText(context, "Waypipe is already running", Toast.LENGTH_SHORT).show()
                false
            }
        } catch (e: Exception) {
            WLog.e("WAYPIPE", "Error starting waypipe: ${e.message}")
            Toast.makeText(context, "Error: ${e.message}", Toast.LENGTH_LONG).show()
            false
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

    fun runNativeLauncher(launcher: String): Boolean = when (launcher) {
        "weston" -> WawonaNative.nativeRunWeston()
        "weston-terminal" -> WawonaNative.nativeRunWestonTerminal()
        "foot" -> WawonaNative.nativeRunFoot()
        else -> WawonaNative.nativeRunWestonSimpleSHM()
    }

    fun stopNativeLauncher(launcher: String) {
        when (launcher) {
            "weston" -> WawonaNative.nativeStopWeston()
            "weston-terminal" -> WawonaNative.nativeStopWestonTerminal()
            "foot" -> WawonaNative.nativeStopFoot()
            else -> WawonaNative.nativeStopWestonSimpleSHM()
        }
    }

    fun isNativeLauncherRunning(launcher: String): Boolean = when (launcher) {
        "weston" -> WawonaNative.nativeIsWestonRunning()
        "weston-terminal" -> WawonaNative.nativeIsWestonTerminalRunning()
        "foot" -> WawonaNative.nativeIsFootRunning()
        else -> WawonaNative.nativeIsWestonSimpleSHMRunning()
    }

    fun launchNativeMachine(profile: MachineProfile): Boolean {
        val launcher = profile.nativeLauncher.ifBlank { "weston-simple-shm" }
        val launched = runNativeLauncher(launcher)
        if (!launched) {
            Toast.makeText(
                context,
                "Failed to launch native app '$launcher' (already running or unavailable).",
                Toast.LENGTH_SHORT
            ).show()
            return false
        }
        WLog.i("NATIVE", "Launched native app '$launcher'")
        return true
    }

    fun connectMachine(profile: MachineProfile, sessionId: String? = null) {
        val targetSession = sessionId ?: sessionOrchestrator.startSession(profile).sessionId
        MachineProfileStore.applyMachineToPrefs(prefs, profile)
        MachineProfileStore.setActiveMachineId(prefs, profile.id)
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
                launchWaypipe()
            }
            MachineType.VM -> {
                Toast.makeText(
                    context,
                    "Virtual machine runtime is a v0.2.3 stub (UTM SE integration pending).",
                    Toast.LENGTH_LONG
                ).show()
                false
            }
            MachineType.CONTAINER -> {
                Toast.makeText(
                    context,
                    "Container runtime is a v0.2.3 stub (integration pending).",
                    Toast.LENGTH_LONG
                ).show()
                false
            }
        }

        if (launched) {
            sessionOrchestrator.markConnected(targetSession)
            sessionOrchestrator.setActiveSession(targetSession)
            showMachinesHome = false
        } else {
            sessionOrchestrator.markDegraded(
                targetSession,
                "Launch unsupported or failed for ${profile.type.value}"
            )
        }
    }

    fun disconnectActiveSession() {
        val activeId = sessionOrchestrator.activeSessionId ?: return
        val activeSession = sessionOrchestrator.activeSession()
        val activeProfile = activeSession?.let { session ->
            profiles.firstOrNull { it.id == session.machineId }
        }
        when (activeProfile?.type) {
            MachineType.NATIVE -> stopNativeLauncher(activeProfile.nativeLauncher)
            MachineType.SSH_WAYPIPE, MachineType.SSH_TERMINAL -> stopWaypipe()
            else -> stopWaypipe()
        }
        sessionOrchestrator.markDisconnected(activeId)
        sessionOrchestrator.setActiveSession(null)
        showMachinesHome = true
    }

    // Activity-level callback is the source of truth for compositor back handling.
    BackHandler(enabled = false) {}

    var lastHandledBackToken by remember { mutableIntStateOf(0) }
    LaunchedEffect(WawonaBackPressBridge.token, showMachinesHome, shakeToCloseEnabled) {
        val token = WawonaBackPressBridge.token
        if (token == 0 || token == lastHandledBackToken) {
            return@LaunchedEffect
        }
        lastHandledBackToken = token
        if (showMachinesHome) {
            return@LaunchedEffect
        }
        if (!shakeToCloseEnabled) {
            disconnectActiveSession()
            return@LaunchedEffect
        }
        if (!suppressShakeBackWarning &&
            !shakeBackWarningShownForSession &&
            !showShakeBackWarningDialog
        ) {
            shakeBackWarningShownForSession = true
            showShakeBackWarningDialog = true
        }
    }

    val density = LocalDensity.current
    val imeBottom = with(density) { WindowInsets.ime.getBottom(this) }
    val showAccessoryBar = imeBottom > 0

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
            sessions = sessionOrchestrator.sessions,
            machineStatusFor = { machineId -> sessionOrchestrator.statusForMachine(machineId) },
            onCreate = { profile ->
                profiles = MachineProfileStore.upsertProfile(prefs, profile)
            },
            onUpdate = { profile ->
                profiles = MachineProfileStore.upsertProfile(prefs, profile)
            },
            onDelete = { profile ->
                profiles = MachineProfileStore.deleteProfile(prefs, profile.id)
                sessionOrchestrator.sessions
                    .filter { it.machineId == profile.id }
                    .forEach { sessionOrchestrator.removeSession(it.sessionId) }
            },
            onConnect = { profile ->
                val session = sessionOrchestrator.startSession(profile)
                connectMachine(profile, session.sessionId)
            },
            onOpenSession = { session ->
                val profile = profiles.firstOrNull { it.id == session.machineId }
                if (profile != null) {
                    connectMachine(profile, session.sessionId)
                }
            },
            onOpenSettings = { showSettingsDialog = true }
        )
    } else {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MainActivity.CompositorBackground)
                .windowInsetsPadding(WindowInsets.ime)
        ) {
            // Full-bleed surface: safe area / cutouts are applied in native via
            // nativeUpdateSafeArea + respectSafeArea (matches Wawona Settings).
            // Do not also pad here — that double-applied insets and broke output size.
            AndroidView(
                factory = { ctx: Context ->
                    WawonaSurfaceView(ctx).apply {
                        holder.addCallback(surfaceCallback)
                    }
                },
                update = { view -> surfaceViewRef = view },
                modifier = Modifier.fillMaxSize()
            )

            if (showAccessoryBar) {
                ModifierAccessoryBar(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth(),
                    onDismissKeyboard = {
                        val imm = context.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                        val window = (context as? ComponentActivity)?.window
                        val view = window?.currentFocus
                        if (view != null && imm != null) {
                            imm.hideSoftInputFromWindow(view.windowToken, 0)
                        }
                    }
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

    if (showShakeBackWarningDialog) {
        AlertDialog(
            onDismissRequest = { showShakeBackWarningDialog = false },
            title = { Text("Shake to exit is enabled") },
            text = {
                Text(
                    "You have Shake to exit enabled, shake device or disable this setting to use native back guesture to exit."
                )
            },
            confirmButton = {
                TextButton(onClick = { showShakeBackWarningDialog = false }) {
                    Text("Okay")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        prefs.edit().putBoolean("wawona.pref.suppressShakeBackWarning", true).apply()
                        suppressShakeBackWarning = true
                        showShakeBackWarningDialog = false
                    }
                ) {
                    Text("Don't show again")
                }
            }
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

@Composable
private fun AppWelcomeScreen(onContinue: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MainActivity.CompositorBackground)
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
                color = Color.White,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "A clean Wayland compositor experience.",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.78f)
            )
            Spacer(modifier = Modifier.height(6.dp))
            Button(onClick = onContinue) {
                Text("Continue")
            }
        }
    }
}
