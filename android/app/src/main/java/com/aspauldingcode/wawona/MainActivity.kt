package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.inputmethod.InputMethodManager
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowInsetsController
import android.widget.Toast
import androidx.activity.ComponentActivity
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
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
import kotlinx.coroutines.delay

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

            val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
            windowInsetsController.let { controller ->
                controller.hide(WindowInsetsCompat.Type.systemBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }

            prefs = getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)

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
    var showSettings by remember { mutableStateOf(false) }
    var isWaypipeRunning by remember { mutableStateOf(false) }
    var windowTitle by remember { mutableStateOf("") }
    var nativeRuntimeReady by remember { mutableStateOf(false) }
    val respectSafeArea = prefs.getBoolean("respectSafeArea", true)

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
            }
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
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

    LaunchedEffect(Unit) {
        while (true) {
            try {
                isWaypipeRunning = WawonaNative.nativeIsWaypipeRunning()
                windowTitle = WawonaNative.nativeGetFocusedWindowTitle()
                ScreencopyHelper.pollAndCapture(activity?.window)
                val hasWindow = windowTitle.isNotEmpty()
                if (hasWindow && !hadWindow) {
                    surfaceViewRef?.requestFocus()
                    val w = surfaceViewRef?.width ?: 0
                    val h = surfaceViewRef?.height ?: 0
                    if (w > 0 && h > 0) {
                        try {
                            WawonaNative.nativeSyncOutputSize(w, h)
                        } catch (_: Exception) {
                        }
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
        val remoteCmd = wpRemoteCommand.ifEmpty { "weston-terminal" }
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

    fun connectMachine(profile: MachineProfile, sessionId: String? = null) {
        val targetSession = sessionId ?: sessionOrchestrator.startSession(profile).sessionId
        MachineProfileStore.applyMachineToPrefs(prefs, profile)
        MachineProfileStore.setActiveMachineId(prefs, profile.id)
        if (!ensureNativeRuntimeReady()) {
            sessionOrchestrator.markDegraded(targetSession, "Failed to initialize compositor runtime")
            return
        }

        val launched = when (profile.type) {
            MachineType.NATIVE -> true
            MachineType.SSH_WAYPIPE -> launchWaypipe()
            MachineType.SSH_TERMINAL -> {
                val withTerminalCommand = profile.copy(
                    remoteCommand = profile.remoteCommand.ifBlank { "weston-terminal" }
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
        stopWaypipe()
        sessionOrchestrator.markDisconnected(activeId)
        sessionOrchestrator.setActiveSession(null)
        showMachinesHome = true
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
            }
        )
    } else {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MainActivity.CompositorBackground)
                .windowInsetsPadding(WindowInsets.ime)
        ) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MachineSessionStrip(
                    sessions = sessionOrchestrator.sessions.filter {
                        it.state == MachineSessionState.CONNECTED ||
                            it.state == MachineSessionState.CONNECTING ||
                            it.state == MachineSessionState.DEGRADED
                    },
                    activeSessionId = sessionOrchestrator.activeSessionId,
                    onShowMachines = { showMachinesHome = true },
                    onSelectSession = { session ->
                        val profile = profiles.firstOrNull { it.id == session.machineId }
                            ?: return@MachineSessionStrip
                        connectMachine(profile, session.sessionId)
                    }
                )
            }

            AndroidView(
                factory = { ctx: Context ->
                    WawonaSurfaceView(ctx).apply {
                        holder.addCallback(surfaceCallback)
                    }
                },
                update = { view -> surfaceViewRef = view },
                modifier = Modifier
                    .fillMaxSize()
                    .then(
                        if (respectSafeArea) {
                            Modifier.windowInsetsPadding(WindowInsets.safeDrawing)
                        } else {
                            Modifier
                        }
                    )
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

            ExpressiveFabMenu(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(
                        start = 24.dp,
                        top = 24.dp,
                        end = 24.dp,
                        bottom = if (showAccessoryBar) 24.dp + 80.dp else 24.dp
                    ),
                isWaypipeRunning = isWaypipeRunning,
                onSettingsClick = { showSettings = true },
                onStopWaypipeClick = { disconnectActiveSession() },
                onMenuClosed = { surfaceViewRef?.requestFocus() }
            )

            if (showSettings) {
                SettingsDialog(
                    prefs = prefs,
                    onDismiss = {
                        profiles = MachineProfileStore.persistActiveMachineSettings(prefs)
                        showSettings = false
                        surfaceViewRef?.requestFocus()
                    },
                    onApply = {
                        profiles = MachineProfileStore.persistActiveMachineSettings(prefs)
                        WawonaSettings.apply(prefs)
                    }
                )
            }
        }
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
