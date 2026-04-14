package com.aspauldingcode.wawona

import android.app.Application
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import skip.foundation.ProcessInfo
import skip.ui.ComposeContext
import skip.ui.UIApplication
import wawona.ui.WawonaAppDelegate
import wawona.ui.WawonaRootView

open class AndroidAppMain : Application() {
    override fun onCreate() {
        super.onCreate()
        ProcessInfo.launch(this)
        WawonaAppDelegate.Companion.shared.onInit()
    }
}

open class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        WawonaNative.nativeInit(cacheDir.absolutePath)
        WawonaSettings.apply(getSharedPreferences("wawona_preferences", MODE_PRIVATE))
        UIApplication.Companion.launch(this)
        WawonaAppDelegate.Companion.shared.onLaunch()
        setContent {
            WawonaRootView().Compose(ComposeContext())
        }
    }

    override fun onResume() {
        super.onResume()
        WawonaAppDelegate.Companion.shared.onResume()
    }

    override fun onPause() {
        WawonaAppDelegate.Companion.shared.onPause()
        super.onPause()
    }

    override fun onStop() {
        WawonaAppDelegate.Companion.shared.onStop()
        super.onStop()
    }

    override fun onDestroy() {
        WawonaAppDelegate.Companion.shared.onDestroy()
        super.onDestroy()
        WawonaNative.nativeShutdown()
    }
}
