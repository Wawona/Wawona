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
/* NOTE: no fastfetch_main stub — wwn-fastfetch (libfastfetch.a) is now
 * -force_load'd on tvOS too (fastfetchLdflags tvosDeps), so the real
 * fastfetch_main wrapper is always pulled. A strong stub here would be a
 * duplicate symbol against the force-loaded archive; a weak one would satisfy
 * the -u and stop the member from linking (same reasoning as phoon). #139 */
/* NOTE: no phoon_main stub — wwn-phoon-rs (libphoon_rs.a) is lazy-linked on
 * every Apple target, including tvOS (-lphoon_rs + -Wl,-u,_phoon_main; std
 * dedupes against niri's force-load), so the real C ABI entry is always pulled.
 * A stub here would satisfy the -u and stop the archive member from linking. */
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
