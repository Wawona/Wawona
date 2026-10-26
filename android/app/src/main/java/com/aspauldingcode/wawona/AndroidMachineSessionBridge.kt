package com.aspauldingcode.wawona

import android.content.Context
import java.io.File

/** Android VM lane: QEMU + KVM when /dev/kvm exists, else TCG+JIT. */
object AndroidMobileVmRunner {
    fun launch(context: Context, profile: MachineProfile): Boolean {
        val guestDir = File(context.filesDir, "wawona-mobile-guest")
        if (!guestDir.isDirectory || !File(guestDir, "rootfs.img").exists()) {
            return false
        }
        val libDir = context.applicationInfo.nativeLibraryDir
        val qemuSo = File(libDir, "libqemu-system-aarch64.so")
        val qemuBin = File(libDir, "qemu-system-aarch64")
        val qemuPath = when {
            qemuSo.exists() -> qemuSo.absolutePath
            qemuBin.exists() -> qemuBin.absolutePath
            else -> null
        }
        if (qemuPath != null) {
            File(context.filesDir, "WAWONA_QEMU.path").writeText(qemuPath)
        }
        val memoryMb = 768
        return WawonaNative.nativeLaunchMobileVm(guestDir.absolutePath, memoryMb)
    }

    fun stop() {
        WawonaNative.nativeStopMobileVm()
    }
}
