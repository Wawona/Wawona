package com.aspauldingcode.wawona.anowaw

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Foreground service that holds the [MediaProjection] session for the anowaW
 * **baseline (Play-safe)** tier.
 *
 * Play requirements satisfied here:
 *  * `foregroundServiceType="mediaProjection"` in the manifest (Android 14+ also
 *    needs the [ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION] flag on
 *    startForeground and the `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission).
 *  * The projection is started only after the user grants consent through the
 *    system `createScreenCaptureIntent()` dialog (handled by the caller, which
 *    forwards the result Intent as [EXTRA_RESULT_DATA]).
 *  * A visible, persistent notification for the duration of capture.
 *
 * In the baseline tier this projection mirrors the *whole* display; anowaW then
 * presents it as a single Wayland toplevel. Per-app embedding of *third-party*
 * apps requires the power-mode tier ([AnowawPowerController]).
 */
class AnowawProjectionService : Service() {

    companion object {
        private const val TAG = "anowaW"
        private const val CHANNEL_ID = "anowaw_bridge"
        private const val NOTIF_ID = 0xA0DA

        const val EXTRA_RESULT_CODE = "anowaw.resultCode"
        const val EXTRA_RESULT_DATA = "anowaw.resultData"
        const val EXTRA_SOCKET = "anowaw.socket"

        /** Build the system consent intent the Activity must launch first. */
        fun screenCaptureIntent(context: Context): Intent {
            val mpm = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
            return mpm.createScreenCaptureIntent()
        }
    }

    private var projection: MediaProjection? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()

        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
        val data: Intent? = intent?.getParcelableExtra(EXTRA_RESULT_DATA)
        if (resultCode == 0 || data == null) {
            Log.e(TAG, "projection service started without consent result; stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mediaProjection = mpm.getMediaProjection(resultCode, data)
        if (mediaProjection == null) {
            Log.e(TAG, "MediaProjectionManager returned null projection; stopping")
            stopSelf()
            return START_NOT_STICKY
        }
        projection = mediaProjection
        mediaProjection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.i(TAG, "MediaProjection stopped by system/user")
                stopSelf()
            }
        }, null)
        Log.i(TAG, "anowaW baseline projection active")
        // The AnowawBridge / capture wiring reads `projection` via the app's
        // service binder or a shared holder; kept minimal here.
        return START_NOT_STICKY
    }

    val mediaProjection: MediaProjection? get() = projection

    private fun startAsForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Wawona App Bridge",
                    NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notif: Notification =
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Wawona App Bridge")
                .setContentText("Mirroring the screen into the Linux desktop")
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    override fun onDestroy() {
        projection?.stop()
        projection = null
        super.onDestroy()
    }
}
