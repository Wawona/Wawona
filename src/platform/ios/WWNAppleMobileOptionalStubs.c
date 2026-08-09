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
/* NOTE: no phoon_main stub — wwn-phoon-rs (libphoon_rs.a) is force-loaded on
 * every Apple target, including tvOS, so the real C ABI entry is always
 * present. A stub here would collide with it (duplicate symbol). */
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
