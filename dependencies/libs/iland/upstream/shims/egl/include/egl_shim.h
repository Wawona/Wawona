#ifndef EGL_SHIM_H
#define EGL_SHIM_H

#include <gbm.h>
#include <EGL/egl.h>

typedef struct EGLShimDisplay {
    EGLDisplay angle_display;
    struct gbm_device *gbm_device;
} EGLShimDisplay;

typedef struct EGLShimSurface {
    EGLSurface angle_surface;          /* ANGLE pbuffer used by the copy path */
    struct gbm_surface *gbm_surface;
    uint32_t width;
    uint32_t height;

    /* Zero-copy path (ILAND_EGL_ZEROCOPY=1): instead of glReadPixels + a CPU
     * channel-swap into the IOSurface, ANGLE renders directly into an
     * IOSurface-backed Metal texture via EGL_ANGLE_iosurface_client_buffer.
     * One ANGLE pbuffer is cached per gbm bo (must cover GBM_NUM_BUFFERS = 4).
     * Lazily created the first time a bo is presented. */
    int        zerocopy;
    EGLConfig  config;
    EGLSurface iosurf_pbuffers[4];
} EGLShimSurface;

#endif
