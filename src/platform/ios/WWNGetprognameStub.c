// Interpose getprogname/setprogname for Apple mobile App Store builds.
//
// Weston and fontconfig call getprogname(). libSystem's implementation pulls
// the private ___progname symbol; altool rejects that import (code 11).
//
// This file is only compiled into iOS/tvOS/visionOS app targets (src/platform/ios).
// Do not gate on TARGET_OS_* macros: an empty translation unit silently leaves
// the libSystem import in place.

__attribute__((used)) const char *getprogname(void) {
  return "Wawona";
}

__attribute__((used)) void setprogname(const char *name) {
  (void)name;
}
