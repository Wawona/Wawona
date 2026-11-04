# Machine Start placement (Prompt / New Tab / New Window)

Authority for Default Start Type and when Start prompts.

## Setting

Display → **Default Start Type**: `prompt` | `newTab` | `newWindow`
(legacy stored `tab` / `window` accepted). Shown only when the host can open
another window.

## Platform gate

| Host | Windowed Start | Prompt allowed |
|---|---|---|
| macOS | yes | yes when setting is Prompt |
| visionOS | yes (multi-scene) | yes |
| iPad | yes (`UIApplicationSupportsMultipleScenes`) | yes |
| iPhone | no | never (always New Tab) |
| Android API 24+ | yes (`SessionActivity` host task) | yes |
| Android < 24 | no | never |
| Linux | yes (tab or dedicated window) | yes |
| tvOS / watchOS | no | never |

iPad multi-window is **not** gated on iPadOS 26. Multi-scene windowing is
older. iPadOS 26 adds window control chrome only.

## Behavior

1. Setting **New Tab** (or no windowing): Start mounts Present for SHM
   drain but keeps Machines chrome. Focus / client attach reveals Metal
   under Tab Overview (`showSessionSurface` → selection `.tabOverview` or
   `.clientTab(window_id)`). Not over the Machines grid. Not AppKit window
   tabs.
2. Setting **New Window**: Start opens a dedicated window. Wawona
   Terminal is that window (`WWNMacGuestConsole` on macOS, a terminal
   scene on iPad and visionOS, `TerminalActivity` on Android 24+). A
   Wayland client gets the compositor Present in that session window
   (`WWNSessionWindowPresenter`). On macOS, the next toplevel Created sets
   `preferStandaloneOnCreate` so the client can tear into a floating
   `WWNWindow`. Machines chrome stays. Main window never gains a global
   tab bar.
3. Setting **Prompt**: macOS `NSAlert`; iPad / iPhone 15+ / visionOS
   `confirmationDialog` (not legacy `actionSheet`: invisible on visionOS);
   Android `AlertDialog`. Only when windowing is available.
4. Return from in-window Present: sidebar **Machines**, or Tab Overview
   card grid via the toolbar Tab Overview button / in-section "Show
   Overview". No floating Machines overlay on the client.

## Tabs (Safari chrome)

- **No** AppKit / WindowGroup global tab bar on the Machines UI
  (`NSWindow.allowsAutomaticWindowTabbing = false`; session windows
  `tabbingMode = .disallowed`).
- **Sidebar:** expandable **"N Tabs"** section (DisclosureGroup / Compose /
  GTK). Children are indented nested Wayland toplevels (or running session
  rows on Android/Linux until per-`window_id` store lands there). Hidden
  when nested count is 0. **Not** a flat "Tab Overview" sidebar row.
- **Toolbar:** one **Tab Overview** button (`square.on.square` /
  Dashboard / `view-grid-symbolic`) opens the Safari-style overview grid
  across Apple, Android, and Linux.
- **In-Present strip:** `WWNTabOverviewSessionTabBar` only when nested
  count **> 1** (Safari rule). 1 tab = no strip.
- 1 nested tab = 1 Wayland toplevel in Tab Overview. macOS tear-off /
  nest uses pasteboard `com.aspauldingcode.wawona.window-id`.
- 0 tabs = empty Tab Overview; start from Machines.
- Metal Present for tabbed Start is visible only while Tab Overview /
  client tab has Focus Present (`sessionSurfaceVisible`). Machines mounts
  Present at opacity 0 for drain only.

## Code

- Prefs: `kWWNPrefsDefaultStartType` / Android `defaultStartType`
- Resolve: `MachineStartPlacement` (`WawonaUIContracts`)
- Apple Start: `WWNMachinesViewModel.beginStart`
- Nested tabs: `WWNNestedClientTabStore` / `WWNHostWindowController`
- Window open: `WWNSessionWindowPresenter`
- Present reveal: `WWNMainWindowRouter.showSessionSurface` /
  `showTabOverview`
- Tab strip: `WWNTabOverviewSessionTabBar` (gated `showsSessionTabBar`)
- Android: `MachinesConfigurationSidebar` + toolbar Dashboard
- Linux: expandable tabs section + header `tab_overview_btn`
