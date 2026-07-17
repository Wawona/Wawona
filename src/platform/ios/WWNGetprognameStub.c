// Fallback getprogname/setprogname for Apple mobile (force-loaded archive).
// Prefer fixing callers (weston string macro, fontconfig polyfill) so the
// binary never imports libSystem getprogname → private ___progname.

__attribute__((used)) const char *getprogname(void) {
  return "Wawona";
}

__attribute__((used)) void setprogname(const char *name) {
  (void)name;
}
