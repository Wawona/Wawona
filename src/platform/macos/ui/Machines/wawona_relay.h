#ifndef WAWONA_RELAY_H
#define WAWONA_RELAY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * One C ABI for Machines kinds virtual_machine, container, and wasm.
 * Wawona never picks a hypervisor. Mode A vs Mode B is which binary you
 * installed, not a Settings switch.
 *
 * Wasm packages stay /wasm/v1 bytecode. Mode B may execute them (Pulley
 * on Apple mobile). There is no Mode B wasm catalog.
 * Mode A: never QEMU / UTM.
 * Mode B iOS VMs: Relay static CPU now. Mode B JIT is MAP_JIT write+exec.
 * TXM EPERM is JIT ARMED, not a second engine. No QEMU fallback.
 */

/* 0 ok. Negative forbidden/planned/fail. Caller frees strings with
 * relay_string_free. */
int relay_resolve_backend(const char *spec_json, char **backend_out);

int relay_start(const char *spec_json, char **handle_out);

int relay_stop(const char *handle);

int relay_wayland_endpoint(const char *handle, char **endpoint_out);

int relay_copy_frame(const char *handle, uint8_t *rgba, size_t len,
                     uint32_t *width, uint32_t *height);

void relay_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* WAWONA_RELAY_H */
