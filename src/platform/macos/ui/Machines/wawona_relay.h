#ifndef WAWONA_RELAY_H
#define WAWONA_RELAY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * One C ABI for Machines kinds virtual_machine, container, and wasm.
 * Wawona UI never picks a hypervisor. Relay resolves VZ, KVM, IosHv, or
 * static CPU from the artifact and (on Mode B iOS) a live host probe.
 * Mode A vs Mode B is which binary you installed, not a Settings switch.
 *
 * Wasm packages stay /wasm/v1 bytecode. Mode B may execute them (Pulley
 * on Apple mobile). There is no Mode B wasm catalog.
 * Never QEMU. Never UTM.
 */

/* 0 ok. Negative forbidden/planned/fail. Caller frees strings with
 * relay_string_free. */
int relay_resolve_backend(const char *spec_json, char **backend_out);

/* JSON: supported, reason, optional soc/target. Uses spec.ios_hv_host or
 * live sysctl on a Mode B iOS process. */
int relay_probe_ios_hv(const char *spec_json, char **json_out);

int relay_start(const char *spec_json, char **handle_out);

int relay_stop(const char *handle);

/* Native synchronous waypipe entry: fd is borrowed for this call. Duplicate it
 * if needed, never close the caller's fd, and return when its peer closes.
 * Entry stays callable until relay_stop succeeds. Transport only, no readiness.
 * A failed/pending stop retains the handle; caller must retry. */
typedef int (*relay_host_waypipe_entry)(int fd);
int relay_start_host_waypipe(const char *handle, relay_host_waypipe_entry entry);

int relay_wayland_endpoint(const char *handle, char **endpoint_out);

int relay_status(const char *handle, char **status_out);

/* Captured guest console. bytes may be NULL to query the required length. */
int relay_copy_log(const char *handle, uint8_t *bytes, size_t capacity,
                   size_t *length_out);

/* Latest guest SHM frame. rgba may be NULL to query width/height only. */
int relay_copy_frame(const char *handle, uint8_t *rgba, size_t len,
                     uint32_t *width, uint32_t *height);

/* Native Nix editor data. NULL source requests the default file. */
int relay_nix_editor(const char *name, const char *source, char **json_out);

/* NixOS generations on a stopped machine disk. Does not modify the disk. */
int relay_nixos_generations(const char *disk_path, char **json_out);

void relay_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* WAWONA_RELAY_H */
