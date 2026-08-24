# In-process cairo teardown (Apple mobile + Android)

Linux weston is a **process**. `cairo_debug_reset_static_data` is a Valgrind
helper that **asserts** if any cairo object remains
(`_cairo_hash_table_destroy`). Apple mobile and Android link
`weston_compositor_main` **in-process** with weston-terminal, desktop-shell,
keyboard, pango, and Foot. They share one libcairo.

Closing nested weston must **not** reset process-global cairo/fontconfig
maps. That SIGABRTs the host Wawona process (iOS Simulator: crash thread in
`wayland_destroy` → `cleanup_after_cairo` → `_cairo_hash_table_destroy`).

macOS out-of-process weston (Resources/bin, CLI wrappers) may still call the
helper. Do not skip it there.

## Hard rejects

- `cleanup_after_cairo()` / `cairo_debug_reset_static_data` /
  `pango_cairo_font_map_set_default(NULL)` / `FcFini` from compositor
  `wayland_destroy` on in-process hosts
- Treating the toytoolkit `clients/window.c` skip (wwn #96) as covering
  compositor teardown. That skip only stops **toytoolkit** `display_destroy`.
  Nested weston still calls `cleanup_after_cairo` from the wayland backend.
- Assuming compositor `cairo-util.c.o` is the linked definition. Apple
  mobile **deletes** `cairo-util.c.o` from `libweston-compositor-13.a` to
  avoid duplicate symbols with `libweston-13.a`. The live function is the
  toytoolkit copy unless both the wayland.c **calls** and the function body
  are patched.

## Code

- Patch script: `wwn-weston/dependencies/clients/weston/terminal-patches/patch-cairo-util-inprocess.py`
- Wired from `compositor-apple-mobile.nix`, `compositor-android.nix`,
  `ios.nix`, `android.nix`
- Skip the two `cleanup_after_cairo()` calls in
  `libweston/backend-wayland/wayland.c`
- No-op `cleanup_after_cairo` in `shared/cairo-util.c` for in-process
  archives

Cursor rule: `wawona-inprocess-cairo`. See `wawona-native-compositors`,
`wawona-compositor-backend`.
