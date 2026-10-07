# WawonaApple

Framework glue for Apple platforms only. This target holds thin Swift wrappers
around AppKit, UIKit, WatchKit, Carbon TIS, Metal present, and similar APIs.

It does **not** own screens, navigation, or business policy. Those stay in
`WawonaUI`, `WawonaModel`, and Rust (`libwawona`). New glue calls the Rust C
ABI (`WWNCore*`, `WWNApplyHostKeyLevels`, `wwn_modeb_desktop_*`, iland present
hooks) via `@_silgen_name` or UniFFI, not duplicated logic.

Android (Kotlin/JNI) and Linux (GTK) are unchanged.
