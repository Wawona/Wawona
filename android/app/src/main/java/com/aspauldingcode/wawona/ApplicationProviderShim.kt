@file:Suppress("UNCHECKED_CAST")

package androidx.test.core.app

import android.app.Application
import android.content.Context

/**
 * Runtime shim for Skip's test-context probe on production builds.
 */
object ApplicationProvider {
    @JvmStatic
    fun <T : Context> getApplicationContext(): T {
        val app = currentApplication()
            ?: throw IllegalStateException("Application context is unavailable")
        return app.applicationContext as T
    }

    private fun currentApplication(): Application? {
        return try {
            val activityThreadClass = Class.forName("android.app.ActivityThread")
            val method = activityThreadClass.getMethod("currentApplication")
            method.invoke(null) as? Application
        } catch (_: Throwable) {
            null
        }
    }
}
