package com.aspauldingcode.wawona

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import kotlin.math.min

/**
 * Draws the virtual touchpad cursor and press-and-hold radial dial above the
 * compositor [SurfaceView] (which cannot host overlays itself).
 *
 * Cursor art matches iOS [TouchpadCursor] (28×40 pt, hotspot 5,5).
 */
class TouchpadOverlayView(context: Context) : View(context) {
    private val radialPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 6f
        strokeCap = Paint.Cap.ROUND
        color = 0xD9FFFFFF.toInt()
    }
    private val cursorBitmap: Bitmap? = BitmapFactory.decodeResource(
        resources,
        R.drawable.touchpad_cursor
    )
    private val density = resources.displayMetrics.density
    // Logical size in dp (matches iOS kTouchpadCursorSize).
    private val cursorWidthPx = 28f * density
    private val cursorHeightPx = 40f * density
    private val cursorHotspotXPx = 5f * density
    private val cursorHotspotYPx = 5f * density
    private val cursorDst = RectF()
    private var cursorX = 0f
    private var cursorY = 0f
    private var cursorVisible = false
    private var radialVisible = false
    private var radialProgress = 0f
    private val radialRadius = 36f

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
    }

    fun setCursorPosition(x: Float, y: Float) {
        cursorX = x
        cursorY = y
        if (cursorVisible) invalidate()
    }

    fun setCursorVisible(visible: Boolean) {
        if (cursorVisible == visible) return
        cursorVisible = visible
        invalidate()
    }

    fun setRadialDial(visible: Boolean, progress: Float = 0f) {
        radialVisible = visible
        radialProgress = progress.coerceIn(0f, 1f)
        invalidate()
    }

    /** Transparent overlay: never consume touches. They go to [WawonaSurfaceView] below. */
    override fun onTouchEvent(event: MotionEvent): Boolean = false

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (cursorVisible) {
            drawCursor(canvas, cursorX, cursorY)
        }
        if (radialVisible) {
            drawRadial(canvas, cursorX, cursorY, radialProgress)
        }
    }

    private fun drawCursor(canvas: Canvas, x: Float, y: Float) {
        val bitmap = cursorBitmap
        if (bitmap != null) {
            cursorDst.set(
                x - cursorHotspotXPx,
                y - cursorHotspotYPx,
                x - cursorHotspotXPx + cursorWidthPx,
                y - cursorHotspotYPx + cursorHeightPx
            )
            canvas.drawBitmap(bitmap, null, cursorDst, null)
            return
        }
        // Fallback if asset missing from the APK.
        val w = cursorWidthPx
        val h = cursorHeightPx
        val left = x - cursorHotspotXPx
        val top = y - cursorHotspotYPx
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = 0xFFFFFFFF.toInt()
        }
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f
            color = 0xFF000000.toInt()
        }
        canvas.drawLine(left, top, left, top + h, stroke)
        canvas.drawLine(left, top + h, left + w * 0.55f, top + h * 0.72f, stroke)
        canvas.drawLine(left, top + h, left + w * 0.42f, top + h * 0.42f, stroke)
        canvas.drawLine(left, top + h, left + w, top + h * 0.18f, stroke)
        canvas.drawLine(left, top, left + w, top + h * 0.18f, stroke)
        canvas.drawLine(left, top, left, top + h, fill)
    }

    private fun drawRadial(canvas: Canvas, x: Float, y: Float, progress: Float) {
        val sweep = min(360f, 360f * progress)
        canvas.drawArc(
            x - radialRadius,
            y - radialRadius,
            x + radialRadius,
            y + radialRadius,
            -90f,
            sweep,
            false,
            radialPaint
        )
    }
}
