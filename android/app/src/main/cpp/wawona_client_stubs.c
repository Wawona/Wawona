/*
 * wawona_client_stubs.c
 *
 * Android launcher bridge for bundled native Wayland clients that are still
 * shipped as separate shared objects. Weston toytoolkit clients (weston_main,
 * weston_terminal_main, flower_main, …) are static-linked from libweston-13.a
 * into libwawona.so — not dlopen'd here.
 */

#include <android/log.h>
#include <dlfcn.h>

#define TAG "WawonaClients"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

typedef int (*client_main_fn)(int argc, const char **argv);

static int run_client_main(const char *lib_name, const char *symbol_name,
                           int argc, const char **argv) {
  void *handle = dlopen(lib_name, RTLD_NOW | RTLD_LOCAL);
  if (!handle) {
    LOGE("Failed to dlopen(%s): %s", lib_name, dlerror());
    return 1;
  }

  dlerror();
  client_main_fn fn = (client_main_fn)dlsym(handle, symbol_name);
  const char *sym_err = dlerror();
  if (sym_err != NULL || fn == NULL) {
    LOGE("Failed to resolve %s from %s: %s", symbol_name, lib_name,
         sym_err ? sym_err : "unknown");
    dlclose(handle);
    return 1;
  }

  LOGI("Launching %s from %s", symbol_name, lib_name);
  int rc = fn(argc, argv);
  LOGI("%s exited with code %d", symbol_name, rc);
  dlclose(handle);
  return rc;
}

int foot_main(int argc, const char **argv) {
  return run_client_main("libfoot.so", "foot_main", argc, argv);
}

int weston_simple_shm_main(int argc, const char **argv) {
  return run_client_main("libweston_simple_shm.so", "weston_simple_shm_main", argc,
                         argv);
}

#ifdef WAWONA_WESTON_TOYTOOLKIT

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#if defined(__ANDROID__)
#include <bits/signal_types.h>
#endif
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef NL_LANGINFO
typedef int nl_item;
#define CODESET 0
#endif

extern int smoke_main(int argc, const char **argv);

int os_resize_anonymous_file(int fd, off_t size) {
  if (ftruncate(fd, size) < 0)
    return -1;
  return 0;
}

char *nl_langinfo(nl_item item) {
  (void)item;
  return "UTF-8";
}

typedef void *iconv_t;

iconv_t iconv_open(const char *tocode, const char *fromcode) {
  (void)tocode;
  (void)fromcode;
  return (iconv_t)1;
}

size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf,
             size_t *outbytesleft) {
  size_t n;
  (void)cd;
  if (!inbuf || !*inbuf || !inbytesleft || !outbuf || !*outbuf ||
      !outbytesleft)
    return (size_t)-1;
  n = (*inbytesleft < *outbytesleft) ? *inbytesleft : *outbytesleft;
  memcpy(*outbuf, *inbuf, n);
  *inbuf += n;
  *outbytesleft -= n;
  *outbuf += n;
  *inbytesleft -= n;
  return 0;
}

int iconv_close(iconv_t cd) {
  (void)cd;
  return 0;
}

#include <xlocale.h>

double __wrap_strtod_l(const char *nptr, char **endptr, locale_t loc) {
  (void)loc;
  return strtod(nptr, endptr);
}

int close_range(unsigned int first, unsigned int last, int flags) {
  unsigned int fd;
  (void)flags;
  for (fd = first; fd <= last; fd++)
    close((int)fd);
  return 0;
}

int pthread_getname_np(pthread_t thread, char *name, size_t len) {
  (void)thread;
  if (name && len > 0)
    name[0] = '\0';
  return 0;
}

int pthread_attr_setinheritsched(pthread_attr_t *attr, int inheritsched) {
  (void)attr;
  (void)inheritsched;
  return 0;
}

static int spawn_exec_fallback(pid_t *pid, const char *path, char *const argv[],
                               char *const envp[]) {
  pid_t child = fork();
  if (child < 0)
    return -1;
  if (child == 0) {
    if (envp)
      execve(path, argv, envp);
    else
      execv(path, argv);
    _exit(127);
  }
  if (pid)
    *pid = child;
  return 0;
}

int posix_spawnattr_init(posix_spawnattr_t *attr) {
  memset(attr, 0, sizeof(*attr));
  return 0;
}

int posix_spawnattr_destroy(posix_spawnattr_t *attr) {
  (void)attr;
  return 0;
}

int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags) {
  (void)attr;
  (void)flags;
  return 0;
}

int posix_spawnattr_setsigdefault(posix_spawnattr_t *attr,
                                  const sigset_t *sigdefault) {
  (void)attr;
  (void)sigdefault;
  return 0;
}

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *actions) {
  memset(actions, 0, sizeof(*actions));
  return 0;
}

int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *actions) {
  (void)actions;
  return 0;
}

int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *actions,
                                     int fd, int newfd) {
  (void)actions;
  (void)fd;
  (void)newfd;
  return 0;
}

int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *actions,
                                      int fd) {
  (void)actions;
  (void)fd;
  return 0;
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp, char *const argv[],
                char *const envp[]) {
  (void)file_actions;
  (void)attrp;
  return spawn_exec_fallback(pid, path, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp, char *const argv[],
                 char *const envp[]) {
  return posix_spawn(pid, file, file_actions, attrp, argv, envp);
}

#endif /* WAWONA_WESTON_TOYTOOLKIT */

#if defined(__ANDROID__)
#include <android/hardware_buffer.h>
#include <dlfcn.h>
#include <errno.h>
#include <sys/syscall.h>
#include <unistd.h>

/* Bionic only exports memfd_create from API 30; libffi and the Rust backend
 * still reference it when minSdk is lower. Route through the aarch64 syscall. */
int __wrap_memfd_create(const char *name, unsigned int flags) {
#if defined(__aarch64__)
  return (int)syscall(279, name, flags);
#elif defined(__NR_memfd_create)
  return (int)syscall(__NR_memfd_create, name, flags);
#else
  (void)name;
  (void)flags;
  errno = ENOSYS;
  return -1;
#endif
}

/* Rust nix::unistd::syncfs is linked from libwawona.a; provide a syscall
 * wrapper when Bionic does not export syncfs for the active minSdk. */
int __wrap_syncfs(int fd) {
#if defined(__NR_syncfs)
  return (int)syscall(__NR_syncfs, fd);
#elif defined(__aarch64__)
  return (int)syscall(267, fd); /* __NR_syncfs on aarch64 */
#else
  (void)fd;
  errno = ENOSYS;
  return -1;
#endif
}

typedef int (*WwnAhbAllocateFn)(const AHardwareBuffer_Desc *,
                                AHardwareBuffer **);
typedef void (*WwnAhbDescribeFn)(const AHardwareBuffer *,
                                 AHardwareBuffer_Desc *);
typedef void (*WwnAhbReleaseFn)(AHardwareBuffer *);
typedef int (*WwnAhbLockFn)(AHardwareBuffer *, uint64_t, int32_t,
                            const ARect *, void **);
typedef int (*WwnAhbUnlockFn)(AHardwareBuffer *, int32_t *);

int __wrap_AHardwareBuffer_allocate(const AHardwareBuffer_Desc *desc,
                                    AHardwareBuffer **out_buffer) {
  WwnAhbAllocateFn fn =
      (WwnAhbAllocateFn)dlsym(RTLD_NEXT, "AHardwareBuffer_allocate");
  return fn ? fn(desc, out_buffer) : -ENOSYS;
}

void __wrap_AHardwareBuffer_describe(const AHardwareBuffer *buffer,
                                     AHardwareBuffer_Desc *out_desc) {
  WwnAhbDescribeFn fn =
      (WwnAhbDescribeFn)dlsym(RTLD_NEXT, "AHardwareBuffer_describe");
  if (fn)
    fn(buffer, out_desc);
  else if (out_desc)
    memset(out_desc, 0, sizeof(*out_desc));
}

void __wrap_AHardwareBuffer_release(AHardwareBuffer *buffer) {
  WwnAhbReleaseFn fn =
      (WwnAhbReleaseFn)dlsym(RTLD_NEXT, "AHardwareBuffer_release");
  if (fn)
    fn(buffer);
}

int __wrap_AHardwareBuffer_lock(AHardwareBuffer *buffer, uint64_t usage,
                                int32_t fence, const ARect *rect,
                                void **out_address) {
  WwnAhbLockFn fn = (WwnAhbLockFn)dlsym(RTLD_NEXT, "AHardwareBuffer_lock");
  return fn ? fn(buffer, usage, fence, rect, out_address) : -ENOSYS;
}

int __wrap_AHardwareBuffer_unlock(AHardwareBuffer *buffer,
                                  int32_t *out_fence) {
  WwnAhbUnlockFn fn =
      (WwnAhbUnlockFn)dlsym(RTLD_NEXT, "AHardwareBuffer_unlock");
  return fn ? fn(buffer, out_fence) : -ENOSYS;
}
#endif

#ifndef WAWONA_WESTON_COMPOSITOR
#include <signal.h>

/* Provided by libweston-compositor when nested compositor is linked; stub otherwise. */
volatile sig_atomic_t wwn_weston_compositor_shutdown_requested = 0;
#endif
