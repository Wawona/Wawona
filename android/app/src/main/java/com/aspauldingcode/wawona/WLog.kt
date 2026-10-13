package com.aspauldingcode.wawona

import android.util.Log
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Unified logger. When a Terminal capture is active (between [enableSink]
 * and [disableSink]) every log line is also emitted on [sinkFlow] so
 * Wawona Terminal can show CLI-side host logs for the Start session.
 */
object WLog {
    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    private val _sinkFlow = MutableSharedFlow<String>(
        extraBufferCapacity = 256,  // drop oldest if the UI falls behind
    )
    /** Collect this into Wawona Terminal while a machine Start is live. */
    val sinkFlow: SharedFlow<String> = _sinkFlow.asSharedFlow()

    private val sinkActive = AtomicBoolean(false)

    /** Start routing every log call to [sinkFlow]. */
    fun enableSink() { sinkActive.set(true) }

    /** Stop routing log calls to [sinkFlow]. */
    fun disableSink() { sinkActive.set(false) }

    private fun emit(line: String) {
        if (sinkActive.get()) _sinkFlow.tryEmit(line)
    }

    fun d(tag: String, msg: String) {
        val line = "${fmt.format(Date())} [$tag] $msg"
        Log.d("Wawona", line)
        emit(line)
    }

    fun i(tag: String, msg: String) {
        val line = "${fmt.format(Date())} [$tag] $msg"
        Log.i("Wawona", line)
        emit(line)
    }

    fun w(tag: String, msg: String) {
        val line = "${fmt.format(Date())} [$tag] $msg"
        Log.w("Wawona", line)
        emit(line)
    }

    fun e(tag: String, msg: String) {
        val line = "${fmt.format(Date())} [$tag] $msg"
        Log.e("Wawona", line)
        emit(line)
    }
}
