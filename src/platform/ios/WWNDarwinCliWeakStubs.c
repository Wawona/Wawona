/* Placeholders when libwawona predates darwin_cli exports. Weak so a real
 * Rust archive wins; stale / skip-nix links still resolve Swift @_silgen_name. */
#include <stddef.h>

__attribute__((weak)) int wwn_darwin_cli_run(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 1;
}

#define WWN_DARWIN_SET(name) \
  __attribute__((weak)) void name(void *fn) { (void)fn; }

WWN_DARWIN_SET(wwn_darwin_cli_set_pasteboard_copy)
WWN_DARWIN_SET(wwn_darwin_cli_set_pasteboard_paste)
WWN_DARWIN_SET(wwn_darwin_cli_set_speak)
WWN_DARWIN_SET(wwn_darwin_cli_set_list_voices)
WWN_DARWIN_SET(wwn_darwin_cli_set_open_url)
WWN_DARWIN_SET(wwn_darwin_cli_set_open_directory)
WWN_DARWIN_SET(wwn_darwin_cli_set_open_file)
WWN_DARWIN_SET(wwn_darwin_cli_set_sips_info)
WWN_DARWIN_SET(wwn_darwin_cli_set_sips_write)
WWN_DARWIN_SET(wwn_darwin_cli_set_product_version)
WWN_DARWIN_SET(wwn_darwin_cli_set_idle_prevent)
WWN_DARWIN_SET(wwn_darwin_cli_set_plist_read_json)
WWN_DARWIN_SET(wwn_darwin_cli_set_plist_write)
WWN_DARWIN_SET(wwn_darwin_cli_set_copy_item)
WWN_DARWIN_SET(wwn_darwin_cli_set_keychain_dump)
WWN_DARWIN_SET(wwn_darwin_cli_set_oslog)
WWN_DARWIN_SET(wwn_darwin_cli_set_path_status)
WWN_DARWIN_SET(wwn_darwin_cli_set_host_flag)
