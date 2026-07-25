/*
 * anowaw_jni.c — JNI glue between the Wawona Android app and the anowaW Rust
 * bridge core (include/anowaw.h).
 *
 * Mirrors the shape of Wawona's existing android_jni.c waypipe wiring: the
 * Kotlin AnowawBridge holds a `long` pointer to the Rust AnowawBridge and drives
 * it through these natives. Frame bytes come from an ImageReader (baseline) or a
 * privileged VirtualDisplay Surface (power mode); input events flow back out via
 * nativePollInput and are re-injected by the Kotlin/InputManager layer.
 *
 * The Rust C ABI is thread-affine, so the Kotlin side confines all native calls
 * to a single dedicated bridge thread.
 */
#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "anowaw.h"

#define JNI_FN(name) Java_com_aspauldingcode_wawona_anowaw_AnowawNative_##name

JNIEXPORT jint JNICALL
JNI_FN(nativeAbiVersion)(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return (jint)anowaw_abi_version();
}

JNIEXPORT jlong JNICALL
JNI_FN(nativeStart)(JNIEnv *env, jclass clazz, jstring socketName) {
    (void)clazz;
    const char *name = socketName ? (*env)->GetStringUTFChars(env, socketName, NULL) : "";
    AnowawBridge *b = anowaw_start(name);
    if (socketName) (*env)->ReleaseStringUTFChars(env, socketName, name);
    return (jlong)(intptr_t)b;
}

JNIEXPORT jlong JNICALL
JNI_FN(nativeBridgeApp)(JNIEnv *env, jclass clazz, jlong handle,
                        jstring appId, jstring title, jint width, jint height) {
    (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)handle;
    if (!b) return 0;
    const char *aid = appId ? (*env)->GetStringUTFChars(env, appId, NULL) : "";
    const char *ttl = title ? (*env)->GetStringUTFChars(env, title, NULL) : "";
    uint64_t h = anowaw_bridge_app(b, aid, ttl, (uint32_t)width, (uint32_t)height);
    if (appId) (*env)->ReleaseStringUTFChars(env, appId, aid);
    if (title) (*env)->ReleaseStringUTFChars(env, title, ttl);
    return (jlong)h;
}

/* Push a frame from a direct ByteBuffer (ImageReader plane / GraphicBuffer map). */
JNIEXPORT jint JNICALL
JNI_FN(nativePushFrame)(JNIEnv *env, jclass clazz, jlong bridge, jlong appHandle,
                        jobject buffer, jint width, jint height, jint stride, jint format) {
    (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)bridge;
    if (!b || !buffer) return -1;
    const uint8_t *data = (const uint8_t *)(*env)->GetDirectBufferAddress(env, buffer);
    jlong len = (*env)->GetDirectBufferCapacity(env, buffer);
    if (!data || len <= 0) return -2;
    return anowaw_push_frame(b, (uint64_t)appHandle, data, (size_t)len,
                             (uint32_t)width, (uint32_t)height, (uint32_t)stride,
                             (uint32_t)format);
}

/*
 * Drain decoded input events into a preallocated int/double SoA supplied by
 * Kotlin (avoids per-event object churn). Returns the count written.
 * Layout per event i:
 *   meta[i*4+0] = kind, meta[i*4+1] = code, meta[i*4+2] = value, meta[i*4+3] = time_ms
 *   handles[i]  = app handle
 *   coords[i*2+0] = x, coords[i*2+1] = y
 */
JNIEXPORT jint JNICALL
JNI_FN(nativePollInput)(JNIEnv *env, jclass clazz, jlong bridge,
                        jlongArray handles, jintArray meta, jdoubleArray coords, jint cap) {
    (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)bridge;
    if (!b || cap <= 0) return 0;

    AnowawInputEvent *events = (AnowawInputEvent *)calloc((size_t)cap, sizeof(AnowawInputEvent));
    if (!events) return -1;
    int n = anowaw_poll_input(b, events, (size_t)cap);
    if (n <= 0) { free(events); return n; }

    jlong *h = (*env)->GetLongArrayElements(env, handles, NULL);
    jint *m = (*env)->GetIntArrayElements(env, meta, NULL);
    jdouble *c = (*env)->GetDoubleArrayElements(env, coords, NULL);
    for (int i = 0; i < n; i++) {
        h[i] = (jlong)events[i].handle;
        m[i * 4 + 0] = (jint)events[i].kind;
        m[i * 4 + 1] = (jint)events[i].code;
        m[i * 4 + 2] = (jint)events[i].value;
        m[i * 4 + 3] = (jint)events[i].time_ms;
        c[i * 2 + 0] = events[i].x;
        c[i * 2 + 1] = events[i].y;
    }
    (*env)->ReleaseLongArrayElements(env, handles, h, 0);
    (*env)->ReleaseIntArrayElements(env, meta, m, 0);
    (*env)->ReleaseDoubleArrayElements(env, coords, c, 0);
    free(events);
    return n;
}

JNIEXPORT jint JNICALL
JNI_FN(nativeCloseRequested)(JNIEnv *env, jclass clazz, jlong bridge, jlong appHandle) {
    (void)env; (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)bridge;
    return b ? anowaw_close_requested(b, (uint64_t)appHandle) : 0;
}

JNIEXPORT void JNICALL
JNI_FN(nativeCloseApp)(JNIEnv *env, jclass clazz, jlong bridge, jlong appHandle) {
    (void)env; (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)bridge;
    if (b) anowaw_close_app(b, (uint64_t)appHandle);
}

JNIEXPORT jint JNICALL
JNI_FN(nativeDispatch)(JNIEnv *env, jclass clazz, jlong bridge) {
    (void)env; (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)bridge;
    return b ? anowaw_dispatch(b) : -1;
}

JNIEXPORT void JNICALL
JNI_FN(nativeStop)(JNIEnv *env, jclass clazz, jlong bridge) {
    (void)env; (void)clazz;
    AnowawBridge *b = (AnowawBridge *)(intptr_t)bridge;
    if (b) anowaw_stop(b);
}
