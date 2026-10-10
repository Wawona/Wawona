# Apple mobile bundle share env (FONTCONFIG / WESTON_DATA_DIR)

In-process weston clients (`weston-desktop-shell`, `weston-keyboard`,
terminals) inherit the **process** environment. On iOS / iPadOS / tvOS /
visionOS / watchOS there is no `/usr/share/weston` and no system
fontconfig. Without explicit env they log:

- `FONTCONFIG_FILE=(unset)` → `Cannot load default config file`
- `ERROR loading icon … /usr/share/weston/terminal.png`
- `/usr/share/weston/pattern.png: No such file or directory`

## Required

Call `WWNBundleShareEnvironment.apply()` (via
`WWNRootfsProvider.applyShellEnvironment()` on phone/TV/vision, or
Watch `WWNWatchShellEnvironment.apply()`) **after** `XDG_RUNTIME_DIR` is
set and **before** `weston_compositor_main` / client spawn.

That sets at least:

| Variable | Source |
|---|---|
| `WESTON_DATA_DIR` | `Bundle…/share/weston` |
| `FONTCONFIG_FILE` / `FONTCONFIG_PATH` | runtime `fonts.conf` under `XDG_RUNTIME_DIR` |
| `WAWONA_MONO_FONT` / `WAWONA_SANS_FONT` | bundled DejaVu under `share/fonts` |
| `XKB_CONFIG_ROOT` / `XLOCALEDIR` | `share/X11/…` when present |
| `XCURSOR_PATH` | `share/icons` when Adwaita cursors present |

Always rewrite `fonts.conf` (bundle UUID changes on reinstall). Writable
fontconfig cache must live under the sandbox (`XDG_RUNTIME_DIR/…`), never
the nix store path baked into `fontconfig-ios`.

Android mirrors the same contract in `android_jni.c` shell env setup.

## Hard rejects

- Relying on Watch-only `applyBundleShareEnv` while iOS Start leaves
  FONTCONFIG unset
- Pointing `FONTCONFIG_FILE` at a previous container path after reinstall
- Expecting `/usr/share/weston` on Apple mobile

Code: `Sources/WawonaApple/Shell/BundleShareEnvironment.swift`.
Call sites: `RootfsManager.applyShellEnvironment`,
`WWNMachineSessionBridge.connect`, `WaypipeRunner+Launch` weston,
`WWNSceneDelegate` after runtime dir, Watch shell apply.
