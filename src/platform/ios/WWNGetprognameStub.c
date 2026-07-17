// Provide getprogname/setprogname for Apple mobile so static archives
// (weston, fontconfig) do not bind libSystem's private ___progname.
// App Store Connect rejects that import (altool code 11 / non-public symbols).

#include <TargetConditionals.h>

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_VISION || TARGET_OS_WATCH)

const char *getprogname(void) {
  return "Wawona";
}

void setprogname(const char *name) {
  (void)name;
}

#endif
