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
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
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
                        surfaceCallback = this@MainActivity
                    )
                }
            }

            WawonaNative.nativeInit(cacheDir.absolutePath)
            WawonaNative.nativeSetDisplayDensity(resources.displayMetrics.density)
            WLog.d("ACTIVITY", "nativeInit completed successfully (density=${resources.displayMetrics.density})")
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
    surfaceCallback: SurfaceHolder.Callback
) {
    var showSettings by remember { mutableStateOf(false) }
    var isWaypipeRunning by remember { mutableStateOf(false) }
    var windowTitle by remember { mutableStateOf("") }
    val respectSafeArea = prefs.getBoolean("respectSafeArea", true)
    val context = LocalContext.current

    val activity = context as? ComponentActivity
    
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

    LaunchedEffect(westonSimpleShmEnabled, nativeWestonEnabled, nativeWestonTerminalEnabled) {
        // Android Weston/weston-terminal are currently compatibility stubs.
        // Route all three toggles to the in-process weston-simple-shm client so
        // enabling from Settings has immediate visible behavior.
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
                        } catch (_: Exception) { }
                    }
                }
                hadWindow = hasWindow

                // Propagate the Wayland client's window title to the Android
                // Activity so it appears in the Recents / Overview screen,
                // mirroring how weston-terminal relays OSC 0/2 title changes.
                if (windowTitle.isNotEmpty()) {
                    activity?.title = windowTitle
                    activity?.setTaskDescription(
                        android.app.ActivityManager.TaskDescription(windowTitle)
                    )
                }
            } catch (_: Exception) { }
            delay(500)
        }
    }

    val wpSshEnabled = prefs.getBoolean("waypipeSSHEnabled", true)
    val wpSshHost = prefs.getString("waypipeSSHHost", "") ?: ""
    val wpSshUser = prefs.getString("waypipeSSHUser", "") ?: ""
    val wpRemoteCommand = prefs.getString("waypipeRemoteCommand", "") ?: ""

    fun launchWaypipe() {
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

        try {
            val launched = WawonaNative.nativeRunWaypipe(
                wpSshEnabled, wpSshHost, wpSshUser, sshPassword,
                remoteCmd, compress, threads, video,
                debug, oneshot || wpSshEnabled, noGpu,
                loginShell, titlePrefix, secCtx
            )
            if (launched) {
                isWaypipeRunning = true
                WLog.i("WAYPIPE", "Waypipe launched (ssh=$wpSshEnabled, host=$wpSshHost)")
            } else {
                Toast.makeText(context, "Waypipe is already running", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            WLog.e("WAYPIPE", "Error starting waypipe: ${e.message}")
            Toast.makeText(context, "Error: ${e.message}", Toast.LENGTH_LONG).show()
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

    val density = LocalDensity.current
    val imeBottom = with(density) { WindowInsets.ime.getBottom(this) }
    val showAccessoryBar = imeBottom > 0

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MainActivity.CompositorBackground)
            .windowInsetsPadding(WindowInsets.ime)
    ) {
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
            onRunWaypipeClick = { launchWaypipe() },
            onStopWaypipeClick = { stopWaypipe() },
            onMenuClosed = { surfaceViewRef?.requestFocus() }
        )

        if (showSettings) {
            SettingsDialog(
                prefs = prefs,
                onDismiss = {
                    showSettings = false
                    surfaceViewRef?.requestFocus()
                },
                onApply = { WawonaSettings.apply(prefs) }
            )
        }
    }
}
