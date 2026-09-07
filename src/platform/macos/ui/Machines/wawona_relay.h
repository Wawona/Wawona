#ifndef WAWONA_RELAY_H
#define WAWONA_RELAY_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * One C ABI for Machines kinds virtual_machine, container, and Mode A wasm.
 * Wawona never picks a hypervisor. Mode A vs Mode B is which binary you
 * installed, not a Settings switch.
 *
 * Never QEMU. Never UTM.
 */

/* 0 ok. Negative forbidden/planned/fail. Caller frees strings with
 * relay_string_free. */
int relay_resolve_backend(const char *spec_json, char **backend_out);

int relay_start(const char *spec_json, char **handle_out);

int relay_stop(const char *handle);

int relay_wayland_endpoint(const char *handle, char **endpoint_out);

void relay_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* WAWONA_RELAY_H */
