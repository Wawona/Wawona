/* macOS: EGLNativeDisplayType is int, so eglGetDisplay expects int not a ptr.
 * Force-included so we don't alter kmscube.c itself.               */
#include <EGL/egl.h>
#define eglGetDisplay(dev) (eglGetDisplay)((EGLNativeDisplayType)(uintptr_t)(dev))
