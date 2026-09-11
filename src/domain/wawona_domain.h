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

#ifdef __cplusplus
}
#endif
