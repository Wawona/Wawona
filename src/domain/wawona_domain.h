#pragma once

/* Thin C trampoline for hosts that do not yet import generated UniFFI.
 * Policy lives in src/domain. This is not WWNCore*. */

#ifdef __cplusplus
extern "C" {
#endif

void wawona_domain_string_free(char *s);

/* Comma-separated settings sidebar slugs for host
 * (`macos`, `ios`, `tvos`, `watchos`, `visionos`, `android`, `linux`).
 * Caller frees with wawona_domain_string_free. */
char *wawona_settings_visible_sections(const char *host);

/* Four-state gate: available, planned, blocked, or forbidden.
 * Caller frees with wawona_domain_string_free. */
char *wawona_capability_gate(const char *platform, const char *feature);

/* 1 if this client / bundled id is forbidden as a Machines profile. */
int wawona_session_is_forbidden_client_id(const char *id);

/* Darwin argv → JSON plan. Caller frees. */
char *wawona_darwin_cli_parse(int argc, const char *const *argv);
char *wawona_darwin_cli_help(void);

/* Bundled client catalog JSON. Caller frees. */
char *wawona_client_catalog_json(void);

/* Pref defaults JSON / key CSV. Caller frees. */
char *wawona_prefs_defaults_json(void);
char *wawona_prefs_keys_csv(void);

/* Launch resolve. Caller frees. */
char *wawona_launch_resolve_backend(
    const char *pref, int classic_own_display, const char *cli_override);
char *wawona_launch_nested_cursor_policy(
    int is_nested_compositor, int show_virtual_cursor);

#ifdef __cplusplus
}
#endif
