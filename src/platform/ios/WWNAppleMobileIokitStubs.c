/*
 * IOKit stubs for Apple platforms that ship IOKit headers but no linkable
 * IOKit.framework (tvOS, watchOS). fastfetch's SMBIOS path must not call these
 * under WAWONA_APPLE_MOBILE; stubs remain as a fail-closed link safety net for
 * any leftover object that still references IORegistry.
 *
 * Never link -framework IOKit on these targets (wawona-platform-targets).
 */
#if defined(__APPLE__)
#include <TargetConditionals.h>
#if (defined(TARGET_OS_TV) && TARGET_OS_TV) || (defined(TARGET_OS_WATCH) && TARGET_OS_WATCH)

#include <stdint.h>

typedef uint32_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_registry_entry_t;
typedef void *CFMutableDictionaryRef;
typedef void *CFTypeRef;
typedef void *CFAllocatorRef;
typedef void *CFStringRef;
typedef unsigned int kern_return_t;
typedef unsigned int IOOptionBits;
typedef uint32_t mach_port_t;

#ifndef MACH_PORT_NULL
#define MACH_PORT_NULL ((mach_port_t)0)
#endif
#ifndef KERN_FAILURE
#define KERN_FAILURE 5
#endif
#ifndef kNilOptions
#define kNilOptions 0
#endif

kern_return_t IOObjectRelease(io_object_t object) {
  (void)object;
  return 0;
}

CFMutableDictionaryRef IOServiceMatching(const char *name) {
  (void)name;
  return NULL;
}

io_service_t IOServiceGetMatchingService(mach_port_t master, CFMutableDictionaryRef matching) {
  (void)master;
  (void)matching;
  return 0;
}

CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key,
                                          CFAllocatorRef allocator, IOOptionBits options) {
  (void)entry;
  (void)key;
  (void)allocator;
  (void)options;
  return NULL;
}

#else
/* iOS / visionOS / macOS: real IOKit where linked; no stubs. */
typedef int wwn_iokit_stubs_unused;
#endif /* tvOS / watchOS */
#endif /* __APPLE__ */
