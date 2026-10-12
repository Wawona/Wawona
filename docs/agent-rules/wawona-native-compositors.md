# Native compositors (Weston and Niri)

Cursor rule: `wawona-native-compositors`. Packaging split: `wawona-optional-software`.

Weston and Niri stay real ports with real entry points. They ship as **debs**
(and wasm when a real module exists), not as mandatory App Store in-app
static archives. Compatibility stubs remain forbidden. Deb recipes must not
carry App Store no-fork or in-process patches.

Nested cursor hide and compositor backend rules still apply when a nested
weston/niri process is running against Wawona.
