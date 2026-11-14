#pragma once

/* Thin C trampoline for hosts that do not yet import generated UniFFI.
 * Policy lives in src/domain. This is not WWNCore*. */

#ifdef __cplusplus
extern "C" {
#endif

void wawona_domain_string_free(char *s);

/* SSH editor sanitize / port. Policy is rust `src/domain/sanitize_ssh_host`. */
char *wawona_editor_sanitize_ssh_host(const char *raw);
int wawona_editor_normalize_ssh_port(const char *raw, int fallback);
/* JSON {"host":"...","port":N}. Caller frees with wawona_domain_string_free. */
char *wawona_editor_split_ssh_host_port(
    const char *raw_host, const char *raw_port, int fallback);
/* JSON array of issue tokens. Caller frees. */
char *wawona_editor_validate(
    const char *name,
    const char *type_raw,
    const char *ssh_host,
    const char *ssh_user,
    const char *ssh_port_text);

/* Comma-separated settings sidebar slugs for host
 * (`macos`, `ios`, `tvos`, `watchos`, `visionos`, `android`, `linux`).
 * Caller frees with wawona_domain_string_free. */
char *wawona_settings_visible_sections(const char *host);
char *wawona_settings_allowed_vulkan_drivers(const char *host);
char *wawona_settings_allowed_opengl_drivers(const char *host);

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
/* Session input (touch / cursor / grab). surface: primary | limited_touch | pointer_remote. */
char *wawona_launch_session_input_policy(
    int is_nested_compositor,
    int show_virtual_cursor,
    const char *touch_input_override,
    const char *surface);

/* CloudKit sync policy. Hosts own CKRecord transport only. */
int wawona_cloud_sync_is_synced_key(const char *key);
int wawona_cloud_sync_home_path_excluded(const char *rel);
unsigned long long wawona_cloud_sync_home_max_file_bytes(void);
unsigned int wawona_cloud_sync_home_max_files(void);
int wawona_cloud_sync_prefer_remote(
    long long local_modified_ms, long long remote_modified_ms, int local_ever_synced);
/* Caller frees with wawona_domain_string_free. NULL on bad JSON. */
char *wawona_cloud_sync_redact_profiles(const char *json);
char *wawona_cloud_sync_merge_profiles(
    const char *local, const char *remote, int bootstrap);

#ifdef __cplusplus
}
#endif
