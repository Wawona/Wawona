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

1. Setting **New Tab** (or no windowing): Start shows the client in the
   current Machines window (`showSessionSurface`).
2. Setting **New Window**: Start opens a dedicated window. Wawona
   Terminal is that window (`WWNMacGuestConsole` on macOS, a terminal
   scene on iPad and visionOS, `TerminalActivity` on Android 24+). A
   Wayland client still gets its compositor window beside the terminal.
   Machines chrome stays. New Tab keeps the terminal in the current window.
3. Setting **Prompt**: macOS `NSAlert`; other Apple hosts action sheet;
   Android `AlertDialog`. Only when windowing is available.
4. Return from in-window session: sidebar **Machines** (selection
   `.session` → `.machines`). No floating "Machines" overlay on the client.

## Code

- Prefs: `kWWNPrefsDefaultStartType` / Android `defaultStartType`
- Resolve: `MachineStartPlacement` (`WawonaUIContracts`)
- Apple Start: `WWNMachinesViewModel.beginStart`
- Window open: `WWNSessionWindowPresenter`
- Android: `MainActivity.beginMachineStart` / `resolvedStartType`
