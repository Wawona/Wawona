# Platform-native controls (design language per OS)

Wawona chrome uses each platform’s **native control and design language**.
Goal is not pixel match across OSes. Goal is that a person who knows the
platform recognizes the app as a first-class citizen of that OS.

## Per host

| Host | Design language |
|---|---|
| macOS | AppKit / SwiftUI Aqua: native toolbar, titlebar, source list, search, menus, sheets |
| iOS / iPadOS / tvOS / visionOS | UIKit / SwiftUI system bars, lists, sheets, tab bars |
| watchOS | WatchKit / SwiftUI |
| Android | Jetpack Compose Material 3 Expressive |
| Windows | **WinUI / Fluent** appearance (Windows 10+/11+). Segoe, Fluent density, NavigationView-shaped chrome, ContentDialog / MenuFlyout metrics |
| Linux | GTK / libadwaita |

## Windows (hard)

Windows must look like a **Windows** app. Hard reject:

- Aqua / macOS titlebar-toolbar look on Windows
- Shared “one skin” that makes Windows match macOS pixels
- Shipping macOS SF Symbol chrome recipes as the Windows product face

Exact’s Windows host may paint Fluent to match a WinUI3 oracle (LLP 1115.004).
Prefer real WinUI3 controls when a host path can mount them. Appearance
fidelity to WinUI beats Contract pixel parity with Mac.

## Craft bar

For every Machines / Settings / Add / Present chrome screen: spacing,
hierarchy, hit targets, empty states, focus order, search, destructive
confirms, toolbar density. Prefer unsaid presentation (platform defaults)
over authored web-card chrome.

## Hard rejects

- Cross-platform painted chrome as the final product UI when native exists
- Pixel parity across OSes as a goal
- macOS-on-Windows or WinUI-on-macOS skins
