package com.aspauldingcode.wawona

import android.content.Context
import java.io.File

/** In-process mobile VM + container-in-VM lane (mirrors iOS WWNMobileVmEngine). */
object AndroidMobileVmRunner {
    fun launch(context: Context, profile: MachineProfile): Boolean {
        val guestDir = File(context.filesDir, "wawona-mobile-guest")
        if (!guestDir.isDirectory || !File(guestDir, "rootfs.img").exists()) {
            return false
        }
        val memoryMb = 768
        return WawonaNative.nativeLaunchMobileVm(guestDir.absolutePath, memoryMb)
    }

    fun stop() {
        WawonaNative.nativeStopMobileVm()
    }
}
