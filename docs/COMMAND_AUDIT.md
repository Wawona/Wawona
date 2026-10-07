# Darwin CLI command audit

Mode A is the App Store shell: public APIs, this app's container, no private
frameworks, no downloaded executables. Mode B is a separate jailbreak package
set for `repo.wawona.io` APT. It is not linked into the store app.

Inventory date: 2026-10-06. Procursus tree is
`github.com/ProcursusTeam/Procursus` `main`. roothide patches are not vendored.
Apple proprietary binaries are not copied. Procursus `sw_vers.c` calls
`_CFCopySystemVersionDictionary`; Mode A does not use that symbol.

| Command | Upstream | License | Procursus | Mode A | Mode B | Private API | Status |
|---|---|---|---|---|---|---|---|
| open / openurl | independent, public UIKit | Wawona | no | `UIApplication` + `shareddocuments://` + `UIDocumentInteractionController` | not `uiopen` | no | landed |
| pbcopy / pbpaste | independent | Wawona | no | `UIPasteboard` (iOS, iPadOS, visionOS) | same public API is enough | no | landed |
| say | independent | Wawona | no | `AVSpeechSynthesizer` | same | no | landed |
| plutil | independent. Procursus builds Diatrus/plutil 0.2.2 | Wawona (this copy) | yes, separate upstream | `NSPropertyListSerialization`, `NSJSONSerialization` | may later use the Procursus package | no | landed |
| defaults | ProcursusTeam/defaults is MIT, installed as `defaults-procursus` | MIT upstream, Wawona container copy | yes | container plists + this app's `NSUserDefaults` only | Procursus `defaults` can see more domains | no in Mode A | landed, container scope |
| xattr | independent, POSIX | Wawona | BSD/file tools elsewhere | `listxattr` / `getxattr` / `setxattr` / `removexattr` | same, wider paths | no | landed |
| sips | independent | Wawona | no matching package found | ImageIO + CoreGraphics subset | same | no | landed, subset |
| sw_vers | do not use Procursus `build_misc/darwintools/sw_vers.c` | BSD 3-clause upstream, not used | vendored C uses a private CF symbol | `UIDevice` + `sysctl kern.osversion` | public subset is enough | upstream yes, Mode A no | landed |
| uiopen | ProcursusTeam/uikittools-ng `uiopen.m` | BSD-4-Clause | uikittools | Mode A frontend exits `UnsupportedSandbox`. Do not ship Procursus `uiopen` | package `wawona-uikit-tools` | yes | Mode A frontend + Mode B package metadata |
| uicache, uialert, uinotify, uisave, uishoot, uidisplay, lsrebuild | uikittools-ng | BSD-3/4-Clause | uikittools | Mode A frontend `UnsupportedSandbox` | `wawona-uikit-tools` | yes | Mode A frontend + Mode B package |
| mgask | uikittools-ng `mgask.m` | BSD | uikittools | Mode A frontend `UnsupportedSandbox` | `wawona-uikit-tools` | yes | Mode A frontend + Mode B package |
| ldid | ProcursusTeam/ldid | AGPL-3.0 | ldid | Mode A frontend `UnsupportedSandbox`. AGPL stays out of the app | `wawona-security-tools` | signing | Mode A frontend + Mode B package |
| launchctl | ProcursusTeam/launchctl | BSD-2-Clause | launchctl | Wawona service manager (`SupportedVirtual`) | `wawona-launch-tools` | XPC / launchd | Mode A virtual landed |
| diskutil, hdiutil | none suitable | | no | Wawona virtual disks / userspace images | real APFS only in Mode B later | yes for host disks | Mode A virtual landed |
| mdfind, mdls, mdutil | none | | no | Wawona file names | Spotlight private APIs stay in Mode B | yes for host Spotlight | Mode A virtual landed |
| lsregister | none | | no | Wawona document registry | LaunchServices private | yes | Mode A virtual landed |
| softwareupdate | none | | no | Wawona resource metadata only. Not apt | jailbreak package frontend later | | Mode A virtual landed |
| pmset, caffeinate | none | | no | public idle-timer / Wawona power policy | private power later | some | Mode A landed restricted |
| security | public Security.framework | | no | this app's keychain | expanded keychain later | some | Mode A landed restricted |
| log | OSLog | | no | this app's logs | unified log is private | host log is private | Mode A landed restricted |
| system_profiler | none | | no | public `UIDevice` / sysctl subset | deeper IOKit later | deeper yes | Mode A landed restricted |
| ioreg | none | | no | public sysctl subset | IORegistry later | yes | Mode A restricted landed |
| networksetup, scutil | none | | no | public `getifaddrs` | SystemConfiguration writes refused | some | Mode A landed restricted |
| profiles | none | | no | `MissingBackend` | investigate | yes | Mode A frontend |
| codesign | none copied | | no | inspect/verify only | ldid for signing | | Mode A inspect landed |
| spctl | none | | no | Wawona trust DB | not host AMFI | | Mode A virtual landed |
| tmutil | none | | no | Wawona snapshots | not host Time Machine | | Mode A virtual landed |
| uicache, uialert, uinotify, uisave, uishoot, uidisplay, lsrebuild | uikittools-ng | BSD-3/4-Clause | uikittools | unsupported | package `wawona-uikit-tools` later, do not link into the app | yes | jailbreak-only |
| mgask | uikittools-ng `mgask.m` | BSD | uikittools | unsupported | MobileGestalt query, separate package | yes | jailbreak-only |
| ldid | ProcursusTeam/ldid | AGPL-3.0 | ldid | unsupported. AGPL must stay out of the app | separate package, keep the license | signing | jailbreak-only |
| launchctl | ProcursusTeam/launchctl | BSD-2-Clause | launchctl | Wawona service manager, not launchd. Not built yet | Procursus port talks to real launchd. Do not put it in Mode A | XPC / launchd | virtual planned / jailbreak candidate |
| diskutil, hdiutil | none suitable | | no | Wawona virtual disks / userspace images. Not built | real APFS only where a jailbreak allows it | yes for host disks | virtual planned |
| mdfind, mdls, mdutil | none | | no | Wawona file index. Not built | Spotlight private APIs stay in Mode B | yes for host Spotlight | virtual planned |
| lsregister | none | | no | Wawona document registry. Not built | LaunchServices private | yes | virtual planned |
| softwareupdate | none | | no | Wawona resource metadata only. Not apt. Not built | jailbreak package frontend, separate from the store app | | planned |
| pmset, caffeinate | none | | no | public idle-timer subset only if it matches a real activity. Not built | private power. Not built | some | planned |
| security | public Security.framework | | no | this app's keychain only. Not built | expanded keychain. Not built | some | planned |
| log | OSLog | | no | this app's logs. Not built | unified log is private. Not built | host log is private | planned |
| system_profiler | none | | no | public `UIDevice` / sysctl subset. `sw_vers` covers the first slice | deeper IOKit. Not built | deeper yes | partial via sw_vers |
| ioreg | none | | no | unsupported on the host. A virtual board may be added later | IORegistry. Not built | yes | unsupported in Mode A |
| networksetup, scutil | network-cmds is a different package | | network-cmds is not these tools | public reachability subset. Not built | SystemConfiguration private. Not built | some | planned |
| profiles | none | | no | unsupported | investigate. Not built | yes | unsupported in Mode A |
| codesign | none copied | | no | verify/inspect only, later | ldid for signing | | planned |
| spctl | none | | no | Wawona trust DB. Not built | not host AMFI | | virtual planned |
| tmutil | none | | no | Wawona snapshots. Not built | not host Time Machine | | virtual planned |
| osascript | none | | no | Wawona scripts only, if added. Not OSA | not host AppleScript | | unsupported until a Wawona language exists |
| kmutil, csrutil, systemextensionsctl | none | | no | unsupported. Do not pretend success | no macOS kext/SIP equivalent to clone | | unsupported |
| xcrun | none | | no | Wawona tool name resolver only, if added | same | | unsupported |
| metal | none | | no | do not clone Apple's compiler | not in the app | | unsupported |
| simctl, devicectl | none | | no | not an iOS command. Host-side | not for the guest | | unsupported |
| ditto | Apple adv-cmds / BSD | check before port | adv-cmds package exists | copy inside the container. Not built | wider paths | | planned |
| GetFileInfo, SetFile | adv-cmds | check before port | adv-cmds | getattrlist on accessible files. Not built | wider paths | | planned |
| Unix core (ls, cp, ssh, zsh, ...) | existing Wawona ports | various | many | already in-process. Do not duplicate | Procursus packages on jailbreaks | | existing |

## Filesystem assumptions

Mode A paths are the app container: Documents, Library/Preferences, and the
iCloud container when the user turned that sync on. `defaults -g` writes
`NSGlobalDomain.plist` in that container. It does not write the host global
domain.

Mode B must not hard-code `/var/jb`. A later `JailbreakEnvironment` should
distinguish rootful, rootless, and roothide (`jbroot`) layouts. That code stays
out of `src/platform/ios/`.

## Tests

`scripts/darwin-cli-mode-a-test.m` exercises plutil, defaults, xattr, sips, and
sw_vers on the Mac against the same Mode A sources. The compliance script
`.github/scripts/verify-darwin-cli-mode-a.py` rejects private and jailbreak
tokens in those sources. Simulator coverage of `open` / pasteboard / `say`
depends on a rebuilt `libwwn-pty.a` plus the rootfs placeholders (template 28).
