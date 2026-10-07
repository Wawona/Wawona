# Mode B Darwin CLI Debian packages

These packages are not part of the App Store app. xcodegen does not compile
this directory. Install only on a disposable `vphone wawona-jb` guest.

## Groups

| Package | Contents | Upstream |
|---|---|---|
| `wawona-uikit-tools` | uiopen, uicache, uialert, uinotify, uisave, uishoot, uidisplay, lsrebuild, mgask | ProcursusTeam/uikittools-ng, BSD-3/4-Clause |
| `wawona-launch-tools` | launchctl | ProcursusTeam/launchctl v1.2.0, BSD-2-Clause. Nix: `repo.wawona.io#launchctl` |
| `wawona-defaults` | defaults | ProcursusTeam/defaults, MIT |
| `wawona-security-tools` | ldid | ProcursusTeam/ldid, AGPL-3.0 (source offer required) |

Architectures: `iphoneos-arm64` (rootless), `iphoneos-arm` (rootful),
`iphoneos-arm64e` when a RootHide build exists.

`Depends:` on Procursus coreutils and shell. Do not vendor zsh.

## Recorded upstreams

See `UPSTREAMS.txt`. Mach-O `launchctl` is built in
`repo.wawona.io/pkgs/systems/launchctl` (`nix build .#launchctl`).

This directory's `write-debs.py` only writes docs stubs. Do not ship those
stubs once the Nix deb exists.
