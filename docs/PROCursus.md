# Procursus inventory

Procursus (`github.com/ProcursusTeam/Procursus`, repository license 0BSD) is
a cross-compiled Darwin bootstrap. Individual packages have their own
licenses. Do not treat the repo license as the license of `ldid` or
`uikittools`.

| Piece | Upstream | License | Use |
|---|---|---|---|
| bootstrap | ProcursusTeam/Procursus | 0BSD for the repo | package index, not a Mode A dependency |
| defaults | ProcursusTeam/defaults | MIT | Mode B candidate. Mode A uses a container implementation so it cannot read other apps |
| launchctl | ProcursusTeam/launchctl | BSD-2-Clause | Mode B only. Private XPC to launchd |
| plutil | github.com/Diatrus/plutil (Procursus 0.2.2) | check that tree before linking | Mode A uses Foundation instead |
| uikittools-ng | ProcursusTeam/uikittools-ng | BSD-3-Clause and BSD-4-Clause files | Mode B only |
| ldid | ProcursusTeam/ldid | AGPL-3.0 | Mode B package only. Never link into the app |
| sw_vers.c | Procursus `build_misc/darwintools/sw_vers.c` | BSD-3-Clause | Do not compile it. It calls `_CFCopySystemVersionDictionary` |

Build flags, exact commits, and patches get recorded when a package is
actually adopted.

## launchctl (Mode B, done)

Procursus does **not** replace `launchd`. Apple's daemon still owns agents
and daemons. `github.com/ProcursusTeam/launchctl` `v1.2.0` is a BSD-2-Clause
XPC client (`bootstrap`, `bootout`, `load`, `unload`, `list`, `kickstart`,
...).

How they build it (copied by Wawona APT):

1. Compile `arm64` `iphoneos` with `-miphoneos-version-min=13.0`.
2. Overlay macOS SDK headers (`libproc.h`, `xpc`, `sys/proc_info.h`) because
   the iPhoneOS SDK omits them. Same overlay as
   `ProcursusTeam/launchctl` `.github/workflows/build.yml`.
3. `ldid -Icom.apple.xpc.launchctl -Slaunchctl.xml` with Procursus
   `build_misc/entitlements/launchctl.xml` (private `xpc.launchd.*`).
4. Deb: `bin/launchctl` plus `/usr/bin/launchctl`. Rootless prefix `/var/jb`.

Nix recipe: `repo.wawona.io/pkgs/systems/launchctl`. Package id
`wawona-launch-tools` (Provides/Conflicts/Replaces Procursus `launchctl`).
Never link this into the App Store app. Mode A `launchctl` stays the
Wawona-scoped virtual manager.

`roothide/Procursus-roothide` and `roothide/Bootstrap` were not copied.
See `docs/ROOTHIDE.md`.
