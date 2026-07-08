package com.aspauldingcode.wawona

import android.content.Context
import android.view.MotionEvent
import android.widget.FrameLayout

/** Hosts the Vulkan [WawonaSurfaceView] plus a transparent touchpad overlay. */
class WawonaCompositorContainer(context: Context) : FrameLayout(context) {
    val surfaceView = WawonaSurfaceView(context)
    val touchpadOverlay = TouchpadOverlayView(context)

    init {
        addView(surfaceView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(
            touchpadOverlay,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        )
        surfaceView.bindTouchpadOverlay(touchpadOverlay)
    }

    /** Route all touches to the compositor surface; the overlay is draw-only. */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean =
        surfaceView.dispatchTouchEvent(ev)
}
