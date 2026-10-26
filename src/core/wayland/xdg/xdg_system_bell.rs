//! `xdg_system_bell_v1` (wayland-protocols staging).
//!
//! Dispatch is owned by Smithay `delegate_xdg_system_bell!`. Host feedback:
//! - macOS: `NSBeep()` (user Sound prefs alert)
//! - iOS family: short `AudioServices` UI sound (no preferred alert on iOS)
//! - watchOS: WatchKit notification haptic
//! - Android: `ToneGenerator.TONE_PROP_BEEP` on STREAM_NOTIFICATION
//! - Linux GTK: `gdk::Display::beep()`
//!
//! Catalog: Functional / StoreSafeCore. Always advertised when globals register.
