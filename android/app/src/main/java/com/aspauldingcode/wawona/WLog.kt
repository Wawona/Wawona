package com.aspauldingcode.wawona

import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object WLog {
    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    fun d(tag: String, msg: String) {
        Log.d("Wawona", "${fmt.format(Date())} [$tag] $msg")
    }

    fun i(tag: String, msg: String) {
        Log.i("Wawona", "${fmt.format(Date())} [$tag] $msg")
    }

    fun w(tag: String, msg: String) {
        Log.w("Wawona", "${fmt.format(Date())} [$tag] $msg")
    }

    fun e(tag: String, msg: String) {
        Log.e("Wawona", "${fmt.format(Date())} [$tag] $msg")
    }
}
