# App Store compliance for the Darwin CLI

Mode A ships inside the Wawona iOS, iPadOS, tvOS, watchOS, and visionOS app.
Review Guidelines 2.5.1 and 2.5.2 are build constraints: public APIs, no
downloaded executable code, no private frameworks, no private selectors.

The store binary must not contain Mode B sources. Those live outside
`src/platform/ios/` and are packaged later as Debian packages for
`repo.wawona.io`. The store app does not download those packages.

`.github/scripts/verify-darwin-cli-mode-a.py` fails the tree if Mode A command
sources name private or jailbreak symbols.

## Public API map

| Command | Public API | Scope |
|---|---|---|
| `open` | `UIApplication openURL:options:completionHandler:` | URLs the system can open |
| `open` on a directory | `shareddocuments://` when the path is inside this app's Documents or iCloud container | Files, not an arbitrary host path |
| `open` on a file | `UIDocumentInteractionController` | present preview or the open-in menu |
| `pbcopy` / `pbpaste` | `UIPasteboard` | iOS, iPadOS, visionOS. tvOS and watchOS report unavailable (`API_UNAVAILABLE`) |
| `say` | `AVSpeechSynthesizer` / `AVSpeechUtterance` | speech the system synthesizer can speak |
| `plutil` | `NSPropertyListSerialization`, `NSJSONSerialization` | files this app can read |
| `defaults` | `NSUserDefaults` for this app's bundle id. Other domains are plist files under the container `Library/Preferences` | not other apps, not the host global domain |
| `xattr` | `listxattr`, `getxattr`, `setxattr`, `removexattr` (`XATTR_NOFOLLOW`) | files this app can access |
| `sips` | ImageIO (`CGImageSource`, `CGImageDestination`) and CoreGraphics (`CGBitmapContext`) | format, dimensions, resize, and a small format set |
| `ditto` | `FileManager.copyItem` | container copy |
| `GetFileInfo` / `SetFile` | `FileManager` metadata | accessible files |
| `security dump-keychain` | `SecItemCopyMatching` | this app's generic passwords |
| `log` | `os.OSLog` | this app |
| `caffeinate -t` | `UIApplication.isIdleTimerDisabled` | timed, then cleared |
| `networksetup` / `scutil` | `getifaddrs` | reads only |
| `launchctl` / `diskutil` / `mdfind` / `lsregister` / `spctl` / `tmutil` / `softwareupdate` | Wawona files under `Library/Wawona/darwin-cli` | virtual, labeled in stderr |

## Not in Mode A

These Mode A frontends exist and exit non-zero. They do not call the host
operation:

`kmutil`, `csrutil`, `systemextensionsctl`, `metal`, `simctl`, `devicectl`,
`profiles`, `osascript`, `xcrun`, `uiopen`, `uicache`, `uialert`, `uinotify`,
`uisave`, `uishoot`, `uidisplay`, `lsrebuild`, `mgask`, `ldid`.

Wawona-scoped `launchctl`, `diskutil`, and `mdfind` say `SupportedVirtual` and
do not touch host launchd, disks, or Spotlight.
