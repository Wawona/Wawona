/*
 * Optional in-process entry points that wawona-dispatch / UI reference.
 * SSH CLI symbols (ssh_main / ssh_keygen_main / scp_main) come from
 * libwwn-ssh-cli.a (wwn-ssh) — do NOT stub them here.
 *
 * Darwin's linker does not treat __attribute__((weak)) declarations as
 * allow-missing the way ELF does when the referencing .o is -force_load'd.
 * Provide empty definitions so platforms without those archives still link.
 *
 * tvOS also omits GPU clients / bundled editors.
 */
#include <stdio.h>
#include <stddef.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_TV

int wawona_nvim_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}
int fastfetch_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}
/* tvOS does NOT force-load libphoon_rs.a: its full-std Rust archive
 * duplicate-symbol-collides with niri's std on this tier-3 target. This block
 * is TARGET_OS_TV-only, so a plain stub here serves tvOS without affecting the
 * iOS/iPadOS/visionOS targets (which force-load the real phoon_main). */
int phoon_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}
int fuzzel_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}
int simple_egl_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}
int kmscube_main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;
  return 127;
}

#endif /* tvOS */
