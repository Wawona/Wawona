/* Temporary visionOS link stubs for clients not yet in visionosSimDeps.
 * foot is real via wwn-foot apple-mobile (libfoot.a) — do NOT stub foot_main.
 * Remaining stubs satisfy -Wl,-u until those recipes land for xros.
 *
 * Must NOT define these symbols on iOS/iPadOS — real archives collide. */
#include <TargetConditionals.h>

#if TARGET_OS_VISION
int fastfetch_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 1;
}
int fuzzel_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 1;
}
int niri_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 1;
}
int wawona_nvim_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 1;
}
int waypipe_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 1;
}
#endif /* TARGET_OS_VISION */
