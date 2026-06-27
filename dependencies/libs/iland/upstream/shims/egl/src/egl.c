#ifndef ILAND_ANGLE_STATIC
#include <dlfcn.h>
#endif
#include <TargetConditionals.h>

#ifdef ILAND_ANGLE_STATIC
/* Rename before any Khronos header include (egl_shim.h pulls in EGL/egl.h). */
#define eglGetDisplay                  angle_eglGetDisplay
#define eglInitialize                  angle_eglInitialize
#define eglTerminate                   angle_eglTerminate
#define eglGetError                    angle_eglGetError
#define eglQueryString                 angle_eglQueryString
#define eglGetConfigs                  angle_eglGetConfigs
#define eglChooseConfig                angle_eglChooseConfig
#define eglGetConfigAttrib             angle_eglGetConfigAttrib
#define eglCreateContext               angle_eglCreateContext
#define eglDestroyContext              angle_eglDestroyContext
#define eglCreateWindowSurface         angle_eglCreateWindowSurface
#define eglDestroySurface              angle_eglDestroySurface
#define eglMakeCurrent                 angle_eglMakeCurrent
#define eglSwapBuffers                 angle_eglSwapBuffers
#define eglBindAPI                     angle_eglBindAPI
#define eglWaitGL                      angle_eglWaitGL
#define eglSwapInterval                angle_eglSwapInterval
#define eglCreatePbufferSurface        angle_eglCreatePbufferSurface
#define eglCreatePbufferFromClientBuffer angle_eglCreatePbufferFromClientBuffer
#define eglGetCurrentContext           angle_eglGetCurrentContext
#endif

#include <egl_shim.h>
#include <gbm_priv.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <IOSurface/IOSurfaceRef.h>
#include <Accelerate/Accelerate.h>

#ifdef ILAND_ANGLE_STATIC
#include <GLES2/gl2.h>
#undef eglGetDisplay
#undef eglInitialize
#undef eglTerminate
#undef eglGetError
#undef eglQueryString
#undef eglGetConfigs
#undef eglChooseConfig
#undef eglGetConfigAttrib
#undef eglCreateContext
#undef eglDestroyContext
#undef eglCreateWindowSurface
#undef eglDestroySurface
#undef eglMakeCurrent
#undef eglSwapBuffers
#undef eglBindAPI
#undef eglWaitGL
#undef eglSwapInterval
#undef eglCreatePbufferSurface
#undef eglCreatePbufferFromClientBuffer
#undef eglGetCurrentContext
#endif

static void *g_angle_handle = NULL;

#ifdef ILAND_ANGLE_STATIC
/* Renamed ANGLE entry points from the block above — use for typeof/load. */
#define ILAND_ANGLE_SYM(name) angle_##name
#else
#define ILAND_ANGLE_SYM(name) name
#endif

#define ANGLE_FN(name) static __typeof__(&ILAND_ANGLE_SYM(name)) real_##name = NULL

/* Bit used to mark duplicate EGLConfigs that report XRGB8888 */
#define XRGB_DUP_BIT ((EGLConfig)(uintptr_t)0x80000000)

ANGLE_FN(eglGetDisplay);
ANGLE_FN(eglInitialize);
ANGLE_FN(eglTerminate);
ANGLE_FN(eglGetError);
ANGLE_FN(eglQueryString);
ANGLE_FN(eglGetConfigs);
ANGLE_FN(eglChooseConfig);
ANGLE_FN(eglGetConfigAttrib);
ANGLE_FN(eglCreateContext);
ANGLE_FN(eglDestroyContext);
ANGLE_FN(eglCreateWindowSurface);
ANGLE_FN(eglDestroySurface);
ANGLE_FN(eglMakeCurrent);
ANGLE_FN(eglSwapBuffers);
ANGLE_FN(eglBindAPI);
ANGLE_FN(eglWaitGL);
ANGLE_FN(eglSwapInterval);
ANGLE_FN(eglCreatePbufferSurface);
ANGLE_FN(eglCreatePbufferFromClientBuffer);
ANGLE_FN(eglGetCurrentContext);

static void (*g_glReadPixels)(int, int, int, int, unsigned int, unsigned int, void *) = NULL;
static void (*g_glFinish)(void) = NULL;

/* EGL_ANGLE_iosurface_client_buffer constants (ANGLE-specific; not in stock
 * EGL/egl.h). Values are stable across ANGLE releases. */
#ifndef EGL_IOSURFACE_ANGLE
#define EGL_IOSURFACE_ANGLE                 0x3454
#endif
#ifndef EGL_IOSURFACE_PLANE_ANGLE
#define EGL_IOSURFACE_PLANE_ANGLE           0x345A
#endif
#ifndef EGL_TEXTURE_RECTANGLE_ANGLE
#define EGL_TEXTURE_RECTANGLE_ANGLE         0x345B
#endif
#ifndef EGL_TEXTURE_TYPE_ANGLE
#define EGL_TEXTURE_TYPE_ANGLE              0x345C
#endif
#ifndef EGL_TEXTURE_INTERNAL_FORMAT_ANGLE
#define EGL_TEXTURE_INTERNAL_FORMAT_ANGLE   0x345D
#endif
#ifndef GL_BGRA_EXT
#define GL_BGRA_EXT                         0x80E1
#endif
#ifndef GL_UNSIGNED_BYTE
#define GL_UNSIGNED_BYTE                    0x1401
#endif

/* Set once at first surface creation from $ILAND_EGL_ZEROCOPY. */
static int g_zerocopy_enabled = -1;

static int zerocopy_enabled(void)
{
    if (g_zerocopy_enabled < 0) {
        const char *e = getenv("ILAND_EGL_ZEROCOPY");
        g_zerocopy_enabled = (e && e[0] == '1') ? 1 : 0;
    }
    return g_zerocopy_enabled;
}

/* Thread-local reusable pixel buffer to avoid malloc/free per frame */
static __thread void  *g_pixels    = NULL;
static __thread size_t g_pixels_sz = 0;

static inline uint32_t rgba_to_bgra(uint32_t rgba)
{
    return (rgba & 0xFF00FF00u) | ((rgba >> 16) & 0xFFu) | ((rgba & 0xFFu) << 16);
}

/* Permute map: RGBA → BGRA (swap byte 0 and byte 2) */
static const uint8_t kRGBAToBGRAMap[4] = { 2, 1, 0, 3 };

#ifdef ILAND_ANGLE_STATIC
static int load_angle(void)
{
    if (g_angle_handle) return 0;
    g_angle_handle = (void *)1;

#define LOAD(name) real_##name = ILAND_ANGLE_SYM(name)

    LOAD(eglGetDisplay);
    LOAD(eglInitialize);
    LOAD(eglTerminate);
    LOAD(eglGetError);
    LOAD(eglQueryString);
    LOAD(eglGetConfigs);
    LOAD(eglChooseConfig);
    LOAD(eglGetConfigAttrib);
    LOAD(eglCreateContext);
    LOAD(eglDestroyContext);
    LOAD(eglCreateWindowSurface);
    LOAD(eglDestroySurface);
    LOAD(eglMakeCurrent);
    LOAD(eglSwapBuffers);
    LOAD(eglBindAPI);
    LOAD(eglWaitGL);
    LOAD(eglSwapInterval);
    LOAD(eglCreatePbufferSurface);
    LOAD(eglCreatePbufferFromClientBuffer);
    LOAD(eglGetCurrentContext);

    return 0;
}

static void load_gles2(void)
{
    if (g_glReadPixels) return;
    g_glReadPixels = glReadPixels;
    g_glFinish = glFinish;
}
#else
static void *open_angle_library(const char *path)
{
    void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (handle) return handle;
    return dlopen(path, RTLD_LAZY);
}

static int load_angle(void)
{
    if (g_angle_handle) return 0;
#if TARGET_OS_IPHONE
    static const char *candidates[] = {
        "@executable_path/Frameworks/libEGL.dylib",
        "libEGL.dylib",
        NULL,
    };
    for (size_t i = 0; candidates[i]; i++) {
        g_angle_handle = open_angle_library(candidates[i]);
        if (g_angle_handle) break;
    }
#else
    g_angle_handle = open_angle_library("/opt/local/lib/libEGL.dylib");
#endif
    if (!g_angle_handle) return -1;

#define LOAD(name) do { \
    real_##name = dlsym(g_angle_handle, #name); \
    if (!real_##name) return -1; \
} while(0)

    LOAD(eglGetDisplay);
    LOAD(eglInitialize);
    LOAD(eglTerminate);
    LOAD(eglGetError);
    LOAD(eglQueryString);
    LOAD(eglGetConfigs);
    LOAD(eglChooseConfig);
    LOAD(eglGetConfigAttrib);
    LOAD(eglCreateContext);
    LOAD(eglDestroyContext);
    LOAD(eglCreateWindowSurface);
    LOAD(eglDestroySurface);
    LOAD(eglMakeCurrent);
    LOAD(eglSwapBuffers);
    LOAD(eglBindAPI);
    LOAD(eglWaitGL);
    LOAD(eglSwapInterval);
    LOAD(eglCreatePbufferSurface);
    LOAD(eglCreatePbufferFromClientBuffer);
    LOAD(eglGetCurrentContext);

    return 0;
}

static void load_gles2(void)
{
    if (g_glReadPixels) return;
#if TARGET_OS_IPHONE
    static const char *candidates[] = {
        "@executable_path/Frameworks/libGLESv2.dylib",
        "libGLESv2.dylib",
        NULL,
    };
    void *h = NULL;
    for (size_t i = 0; candidates[i]; i++) {
        h = open_angle_library(candidates[i]);
        if (h) break;
    }
#else
    void *h = open_angle_library("/opt/local/lib/libGLESv2.dylib");
#endif
    if (!h) return;
    g_glReadPixels = dlsym(h, "glReadPixels");
    g_glFinish    = dlsym(h, "glFinish");
}
#endif

static EGLShimDisplay *unwrap_display(EGLDisplay dpy)
{
    return (EGLShimDisplay *)dpy;
}

static EGLShimSurface *unwrap_surface(EGLSurface surf)
{
    return (EGLShimSurface *)surf;
}

EGLDisplay eglGetDisplay(EGLNativeDisplayType display_id)
{
    if (load_angle() < 0) return EGL_NO_DISPLAY;

    EGLShimDisplay *dpy = calloc(1, sizeof(*dpy));
    if (!dpy) return EGL_NO_DISPLAY;

    dpy->gbm_device = (struct gbm_device *)display_id;
    dpy->angle_display = real_eglGetDisplay(EGL_DEFAULT_DISPLAY);

    return (EGLDisplay)dpy;
}

EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor)
{
    load_gles2();
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglInitialize(dpy, major, minor);
    return real_eglInitialize(sd->angle_display, major, minor);
}

EGLBoolean eglTerminate(EGLDisplay dpy)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglTerminate(dpy);
    EGLBoolean ret = real_eglTerminate(sd->angle_display);
    if (g_pixels) { free(g_pixels); g_pixels = NULL; g_pixels_sz = 0; }
    free(sd);
    return ret;
}

EGLint eglGetError(void)
{
    if (!real_eglGetError) return EGL_SUCCESS;
    return real_eglGetError();
}

const char *eglQueryString(EGLDisplay dpy, EGLint name)
{
    if (dpy == EGL_NO_DISPLAY) return NULL;
    if (!real_eglQueryString) return NULL;
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglQueryString(dpy, name);
    return real_eglQueryString(sd->angle_display, name);
}

EGLBoolean eglGetConfigs(EGLDisplay dpy, EGLConfig *configs,
                          EGLint config_size, EGLint *num_config)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglGetConfigs(dpy, configs, config_size, num_config);
    return real_eglGetConfigs(sd->angle_display, configs, config_size, num_config);
}

EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list,
                            EGLConfig *configs, EGLint config_size,
                            EGLint *num_config)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglChooseConfig(dpy, attrib_list, configs,
                                          config_size, num_config);

    int n_attribs = 0;
    if (attrib_list) {
        const EGLint *p = attrib_list;
        while (p[0] != EGL_NONE) { n_attribs += 2; p += 2; }
        n_attribs += 1;
    }

    /* Stack buffer for typical attrib lists (up to 32 pairs) */
    EGLint stack_buf[65];
    EGLint *mod_attribs;
    int use_heap = ((n_attribs + 1) > (int)(sizeof(stack_buf) / sizeof(stack_buf[0])));
    if (use_heap) {
        mod_attribs = malloc((n_attribs + 1) * sizeof(EGLint));
        if (!mod_attribs) return EGL_FALSE;
    } else {
        mod_attribs = stack_buf;
    }

    if (attrib_list) {
        memcpy(mod_attribs, attrib_list, (n_attribs + 1) * sizeof(EGLint));
        for (int i = 0; mod_attribs[i] != EGL_NONE; i += 2) {
            if (mod_attribs[i] == EGL_SURFACE_TYPE) {
                mod_attribs[i + 1] = EGL_PBUFFER_BIT;
                break;
            }
        }
    }

    EGLBoolean ret = real_eglChooseConfig(sd->angle_display, mod_attribs,
                                           configs, config_size, num_config);
    if (use_heap) free(mod_attribs);
    return ret;
}

EGLBoolean eglGetConfigAttrib(EGLDisplay dpy, EGLConfig config,
                               EGLint attribute, EGLint *value)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglGetConfigAttrib(dpy, config, attribute, value);

    if (attribute == EGL_SURFACE_TYPE) {
        if (!real_eglGetConfigAttrib(sd->angle_display, config,
                                      attribute, value))
            return EGL_FALSE;
        if (*value & EGL_PBUFFER_BIT)
            *value |= EGL_WINDOW_BIT;
        return EGL_TRUE;
    }

    if (attribute == EGL_NATIVE_VISUAL_ID) {
        static const EGLint rgba_attrs[] = {
            EGL_ALPHA_SIZE, EGL_RED_SIZE, EGL_GREEN_SIZE, EGL_BLUE_SIZE
        };
        EGLint rgba[4];
        for (int i = 0; i < 4; i++) {
            if (!real_eglGetConfigAttrib(sd->angle_display, config,
                                          rgba_attrs[i], &rgba[i]))
                return EGL_FALSE;
        }
        if (rgba[1] == 8 && rgba[2] == 8 && rgba[3] == 8) {
            *value = rgba[0] == 8 ? 0x34325241  /* AR24 → ARGB8888 */
                                  : 0x34325258; /* XR24 → XRGB8888 */
            return EGL_TRUE;
        }
    }

    return real_eglGetConfigAttrib(sd->angle_display, config, attribute, value);
}

EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config,
                             EGLContext share_context,
                             const EGLint *attrib_list)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglCreateContext(dpy, config, share_context, attrib_list);
    return real_eglCreateContext(sd->angle_display, config, share_context, attrib_list);
}

EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglDestroyContext(dpy, ctx);
    return real_eglDestroyContext(sd->angle_display, ctx);
}

/* Zero-copy: get/create the ANGLE IOSurface-client-buffer pbuffer for gbm bo
 * index `idx`. ANGLE renders the default framebuffer straight into the
 * IOSurface-backed Metal texture — no glReadPixels, no CPU channel swap. */
static EGLSurface zc_pbuffer_for_bo(EGLShimDisplay *sd, EGLShimSurface *ss,
                                    int idx, struct gbm_bo *bo)
{
    if (idx < 0 || idx >= (int)(sizeof(ss->iosurf_pbuffers) /
                                sizeof(ss->iosurf_pbuffers[0])))
        return EGL_NO_SURFACE;
    if (ss->iosurf_pbuffers[idx]) return ss->iosurf_pbuffers[idx];

    IOSurfaceRef io = gbm_bo_get_iosurface(bo);
    if (!io || !real_eglCreatePbufferFromClientBuffer) return EGL_NO_SURFACE;

    const EGLint attribs[] = {
        EGL_WIDTH,                          (EGLint)ss->width,
        EGL_HEIGHT,                         (EGLint)ss->height,
        EGL_IOSURFACE_PLANE_ANGLE,          0,
        EGL_TEXTURE_TARGET,                 EGL_TEXTURE_RECTANGLE_ANGLE,
        EGL_TEXTURE_INTERNAL_FORMAT_ANGLE,  GL_BGRA_EXT,
        EGL_TEXTURE_FORMAT,                 EGL_TEXTURE_RGBA,
        EGL_TEXTURE_TYPE_ANGLE,             GL_UNSIGNED_BYTE,
        EGL_NONE
    };

    EGLSurface s = real_eglCreatePbufferFromClientBuffer(
        sd->angle_display, EGL_IOSURFACE_ANGLE,
        (EGLClientBuffer)io, ss->config, attribs);
    ss->iosurf_pbuffers[idx] = s;
    return s;
}

EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config,
                                   EGLNativeWindowType win,
                                   const EGLint *attrib_list)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglCreateWindowSurface(dpy, config, win, attrib_list);

    struct gbm_surface *gs = (struct gbm_surface *)win;
    if (!gs) return EGL_NO_SURFACE;

    EGLShimSurface *ss = calloc(1, sizeof(*ss));
    if (!ss) return EGL_NO_SURFACE;

    ss->gbm_surface = gs;
    ss->width  = gbm_bo_get_width(gs->bos[0]);
    ss->height = gbm_bo_get_height(gs->bos[0]);
    ss->config = config;

    if (zerocopy_enabled()) {
        /* Bind the current write bo's IOSurface as the ANGLE render target. */
        ss->zerocopy = 1;
        struct gbm_bo *wbo = gbm_surface_get_write_bo(gs);
        EGLSurface pb = zc_pbuffer_for_bo(sd, ss, gs->write_idx, wbo);
        if (pb) {
            ss->angle_surface = pb;
            return (EGLSurface)ss;
        }
        /* Fall back to the copy path if ANGLE can't bind the IOSurface. */
        ss->zerocopy = 0;
    }

    EGLint pb_attribs[] = {
        EGL_WIDTH,  (EGLint)ss->width,
        EGL_HEIGHT, (EGLint)ss->height,
        EGL_NONE
    };

    ss->angle_surface = real_eglCreatePbufferSurface(sd->angle_display,
                                                       config, pb_attribs);
    if (!ss->angle_surface) {
        free(ss);
        return EGL_NO_SURFACE;
    }

    return (EGLSurface)ss;
}

EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglDestroySurface(dpy, surface);

    EGLShimSurface *ss = unwrap_surface(surface);
    if (!ss) return real_eglDestroySurface(dpy, surface);

    if (ss->zerocopy) {
        for (size_t i = 0; i < sizeof(ss->iosurf_pbuffers) /
                               sizeof(ss->iosurf_pbuffers[0]); i++) {
            if (ss->iosurf_pbuffers[i])
                real_eglDestroySurface(sd->angle_display,
                                       ss->iosurf_pbuffers[i]);
        }
    } else {
        real_eglDestroySurface(sd->angle_display, ss->angle_surface);
    }
    free(ss);
    return EGL_TRUE;
}

EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw,
                           EGLSurface read, EGLContext ctx)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglMakeCurrent(dpy, draw, read, ctx);

    EGLShimSurface *sdraw = unwrap_surface(draw);
    EGLShimSurface *sread = unwrap_surface(read);

    EGLSurface adraw = sdraw ? sdraw->angle_surface : draw;
    EGLSurface aread = sread ? sread->angle_surface : read;

    return real_eglMakeCurrent(sd->angle_display, adraw, aread, ctx);
}

EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglSwapBuffers(dpy, surface);

    EGLShimSurface *ss = unwrap_surface(surface);
    if (!ss) return real_eglSwapBuffers(dpy, surface);

    struct gbm_surface *gs = ss->gbm_surface;

    if (ss->zerocopy) {
        /* Content is already in the current write bo's IOSurface (ANGLE
         * rendered straight into it). Make sure the GPU work has landed,
         * publish the bo, and bind the next write bo for the next frame. */
        if (g_glFinish) g_glFinish();
        else if (real_eglWaitGL) real_eglWaitGL();

        gbm_surface_advance_write(gs);

        struct gbm_bo *next = gbm_surface_get_write_bo(gs);
        EGLSurface next_pb = zc_pbuffer_for_bo(sd, ss, gs->write_idx, next);
        if (next_pb) {
            ss->angle_surface = next_pb;
            EGLContext cur = real_eglGetCurrentContext
                                 ? real_eglGetCurrentContext()
                                 : EGL_NO_CONTEXT;
            real_eglMakeCurrent(sd->angle_display, next_pb, next_pb, cur);
        }
        return EGL_TRUE;
    }

    struct gbm_bo *bo = gbm_surface_get_write_bo(gs);
    IOSurfaceRef iosurf = gbm_bo_get_iosurface(bo);

    uint32_t w = ss->width;
    uint32_t h = ss->height;
    size_t total = (size_t)w * h * 4;

    if (!g_glReadPixels) return real_eglSwapBuffers(sd->angle_display, ss->angle_surface);

    /* Reuse thread-local buffer to avoid malloc/free per frame */
    if (g_pixels_sz < total) {
        void *p = realloc(g_pixels, total);
        if (!p) return real_eglSwapBuffers(sd->angle_display, ss->angle_surface);
        g_pixels = p;
        g_pixels_sz = total;
    }

    /* Read pixels BEFORE swap — back buffer content is undefined after */
    g_glReadPixels(0, 0, (int)w, (int)h, 0x1908, 0x1401, g_pixels);

    EGLBoolean ret = real_eglSwapBuffers(sd->angle_display, ss->angle_surface);
    if (!ret) return ret;

    IOSurfaceLock(iosurf, 0, NULL);
    uint8_t *dst8 = (uint8_t *)IOSurfaceGetBaseAddress(iosurf);
    size_t dst_pitch_bytes = IOSurfaceGetBytesPerRow(iosurf);
    const uint8_t *src8 = (const uint8_t *)g_pixels;

    /* Copy rows with vertical flip (source is bottom-up from GL) */
    for (uint32_t y = 0; y < h; y++) {
        const uint8_t *s = src8 + (size_t)(h - 1 - y) * w * 4;
        uint8_t *d = dst8 + (size_t)y * dst_pitch_bytes;
        memcpy(d, s, (size_t)w * 4);
    }

    /* Channel swap RGBA→BGRA using Accelerate (SIMD on Apple Silicon) */
    vImage_Buffer buf = {
        .data     = dst8,
        .width    = w,
        .height   = h,
        .rowBytes = dst_pitch_bytes,
    };
    vImagePermuteChannels_ARGB8888(&buf, &buf, kRGBAToBGRAMap, 0);

    IOSurfaceUnlock(iosurf, 0, NULL);

    gbm_surface_advance_write(gs);

    return EGL_TRUE;
}

EGLBoolean eglBindAPI(EGLenum api)
{
    if (!real_eglBindAPI) return EGL_FALSE;
    return real_eglBindAPI(api);
}

EGLBoolean eglWaitGL(void)
{
    if (!real_eglWaitGL) return EGL_FALSE;
    return real_eglWaitGL();
}

EGLBoolean eglSwapInterval(EGLDisplay dpy, EGLint interval)
{
    EGLShimDisplay *sd = unwrap_display(dpy);
    if (!sd) return real_eglSwapInterval(dpy, interval);
    return real_eglSwapInterval(sd->angle_display, interval);
}
