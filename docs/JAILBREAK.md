# Mode B jailbreak CLI

Mode B is not the App Store product. It is a Debian package set for
jailbroken or otherwise entitled iOS, installed from `repo.wawona.io`.

The primary lab is `vphone wawona-jb` (`vphone-cli`). Destructive tests stay
inside that disposable guest. Do not run them against the host Mac or a
physical phone.

## What Mode B may add later

- Procursus `defaults` where it can see domains the container copy cannot.
- Procursus `launchctl` against the guest `launchd`. The Mode A frontend, when
  it exists, talks only to a Wawona service manager.
- `uikittools-ng` (`uiopen`, `uicache`, `uialert`, `uinotify`, `uisave`,
  `uishoot`, `uidisplay`, `lsrebuild`, `mgask`). `uiopen.m` loads
  LaunchServices and FrontBoardServices. That source stays out of
  `src/platform/ios/`.
- `ldid` as its own package. AGPL-3.0. Not linked into the app.

## Build isolation

xcodegen compiles every file under `src/platform/ios/` into the store targets.
Mode B sources must not be placed there. A static check rejects jailbreak
filenames and private symbols in the Mode A command files.

## Not done yet

No Mode B binary is built. No package has been installed on vphone. The audit
records the upstream candidates so the next package step has a source, a
license, and a reason to stay out of the app.
