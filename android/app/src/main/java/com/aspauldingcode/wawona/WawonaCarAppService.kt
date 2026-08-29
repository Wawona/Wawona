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

/**
 * Android Auto entry point. Car screens only allow template-based UI for this
 * app category, so Wawona surfaces a compositor status dashboard. The actual
 * Wayland content stays on the phone.
 */
class WawonaCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: android.content.Intent): Screen =
            WawonaCarStatusScreen(carContext)
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
            .addText(if (running) "Running" else "Stopped")
            .build()
        val pane = Pane.Builder().addRow(statusRow).build()
        return PaneTemplate.Builder(pane)
            .setTitle("Wawona")
            .build()
    }
}
