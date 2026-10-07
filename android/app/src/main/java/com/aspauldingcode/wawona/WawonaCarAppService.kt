package com.aspauldingcode.wawona

import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Android Auto entry point. This category is template UI. The car screen
 * lists compositor status and forces single-touch on the phone seat:
 * one wl_touch slot, also delivered as wl_pointer. Wayland pixels stay
 * on the phone. A TV uses touchpad mode instead.
 */
class WawonaCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: android.content.Intent): Screen {
            try {
                WawonaNative.nativeSetHostSeatMode(1)
            } catch (_: Throwable) {
            }
            lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onDestroy(owner: LifecycleOwner) {
                    try {
                        WawonaNative.nativeSetHostSeatMode(0)
                    } catch (_: Throwable) {
                    }
                }
            })
            return WawonaCarStatusScreen(carContext)
        }
    }
}

class WawonaCarStatusScreen(carContext: CarContext) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        val running = try {
            WawonaNative.nativeIsCompositorReady()
        } catch (_: Throwable) {
            false
        }
        val statusRow = Row.Builder()
            .setTitle("Compositor")
            .addText(if (running) "Running. Single-touch." else "Stopped. Single-touch.")
            .build()
        val pane = Pane.Builder().addRow(statusRow).build()
        return PaneTemplate.Builder(pane)
            .setTitle("Wawona")
            .build()
    }
}
