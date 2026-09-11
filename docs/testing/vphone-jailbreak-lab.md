# vphone-jb Nix wrap (Darwin Apple Silicon)

Jailbroken iOS research lab for Wawona Mode B proof. **Not** the Xcode Simulator.

Canonical automation lives in **L3′ [`wwn-vphone`](https://github.com/Wawona/wwn-vphone)**
(nixpkgs-only). This doc is the Wawona product pointer.

**Never** commit or GitHub-release a prebuilt iOS VM / `Disk.img` / IPSW.
The lab follows upstream [vphone-cli](https://github.com/Lakr233/vphone-cli):
download IPSWs at runtime, create VM, CFW `jb`, launch, SSH smoke.

## One command (any developer)

```bash
nix run github:Wawona/wwn-vphone#vphone-jb-lab
# or from this Wawona checkout (flake input):
nix run .#vphone-jb-lab
```

Full gates, flags, and artifacts: https://github.com/Wawona/wwn-vphone/blob/development/docs/lab.md

Operator owns Recovery SIP / `allow-research-guests` / `amfi` boot-arg. The
flake checks gates and never mutates them.

Sock automation needs a **visible VM window** (not `--headless`). VNC is ops
only. Do not scrape it as the agent path.

Stuck or stale lab: recover automatically (skill
`wawona-vphone-lab-recover`). Trust `vphone-cli --config …/config.plist`
plus sock connect. `booted=true` is stale. `nohup` relaunch. Never
foreground `vm launch` in an agent Shell. Never `pkill -f vphone` to
stop a waiter. Prefer `nix run .#vphone-jb-lab` from this Wawona flake
(re-exports `wwn-vphone`), or `nix run github:Wawona/wwn-vphone#vphone-jb-lab`.

## agent-device (Wawona fork)

Pin: `github.com/Wawona/agent-device` (`0.18.3-wawona.N+`). MCP stays the
existing `user-agent-device` tools. After lab READY:

```bash
agent-device devices                          # includes vphone wawona-jb
agent-device boot --device "vphone wawona-jb" # vphone-cli vm launch if sock missing
agent-device snapshot -i --session vphone
agent-device press @e12                       # after snapshot -i
agent-device press 645 1400                   # coordinate fallback
agent-device packages status --device "vphone wawona-jb"
agent-device packages tipa install path/to/App.tipa --open --jit
agent-device packages apt install path/to/pkg.deb
agent-device packages debug attach com.example.app
agent-device shutdown --device "vphone wawona-jb"
```

Profile JSON is written by the lab (`vphone-wawona-jb.json`: sock, SSH, VNC).
Prefer device name `vphone wawona-jb`. Guest SSH: `mobile` / `alpine`, port
`22222`. No sftp; file push is `ssh cat`. Guest IPv4 drifts on every
`vphone-cli` relaunch. Rewrite `guest-ip.txt` and the profile `sshHost`,
then close the existing agent-device session (it caches the old host).
Compact sock JPEGs can freeze (clock stops). Focus the visible vphone-cli
window and prefer `screen:false` PNG. Cold `uiopen --bundleid` starts
nothing on this iOS 26 guest. `uicache -p` the container `.app`, then
`uiopen --bundleid` once a live pid exists. Do not `kill -9` Wawona.

### snapshot -i / @eN

Guest `vphoned` advertises `accessibility_tree`. Host sock `{"t":"ax"}` maps
that tree to the same `@eN` refs the Simulator XCTest path uses.

1. AXRuntime / AccessibilityUtilities walk when the research kernel exposes it
2. User-app icon-grid fallback (SpringBoard-ish 4 columns)
3. Full-screen placeholder if both fail: `press x y`

Replay: `scripts/agent-device-smoke.sh vphone` or
`agent-device replay Wawona/.agent-device/wawona-ios-vphone-smoke.ad`

Mode B Desktop evidence belongs under
`.agent-device/test-artifacts/modeb-ios/`. UIKit screenshots are black while
IOMFB owns the display. That is expected, not a crash. Xcode Simulator is
not IOMFB or JIT proof. `vphone wawona-jb` is the physical-class TrollStore
proof device. Do not wait for STARDUST or a retail iPhone. TXM limits on
this guest (MAP_JIT write+exec `EPERM`, Metal nil) are proven results.

## Mode B tipa: slim vs official

| Attr | Guests | Verifier | When |
|---|---|---|---|
| `.#wawona-ios-modeb-tipa-slim` | None | `--iteration` | Greeter / IOMFB / compositor iteration on 32 GB vphone |
| `.#wawona-ios-modeb-tipa` | None until Relay frames | `--mode-b` | Product tipa. Same slim guest rule. Relay NixOS disks later |

Bump `WAWONA_BUILD_NUMBER` every reinstall (`nix build --impure`). Keep
`CFBundleDisplayName=Wawona`. Install recipe:

```bash
# aarch64-darwin only. Starts the existing vphone VM if SSH is down, builds
# the slim artifact, installs, launches. Not the Xcode Simulator
# (`nix run .#wawona-ios`). Create the VM once with `nix run .#vphone-jb-lab`.

# TrollStore .tipa (JIT + IOMFB Desktop). Short alias: .#wawona-ios-ts
nix run .#wawona-ios-trollstore
nix run .#wawona-ios-ts -- --no-install
# Legacy alias of trollstore:
nix run .#wawona-ios-modeb

# Sileo / Procursus rootless .deb (full jailbreak Mode B). Short: .#wawona-ios-jb
nix run .#wawona-ios-jailbreak
nix run .#wawona-ios-jb -- --no-install

# Slim tipa (build 10+). Safe on a 32 GB guest with a few GB free.
WAWONA_BUILD_NUMBER=10 nix build --impure .#wawona-ios-modeb-tipa-slim
scripts/install-ios-modeb-tipa.sh --slim result-modeb-slim/Wawona-*-iOS-arm64.tipa

# Slim rootless deb (same binary, /var/jb/Applications).
nix build --impure .#wawona-ios-modeb-deb-rootless-slim -o result-modeb-deb-slim
scripts/install-ios-modeb-deb.sh --rootless result-modeb-deb-slim/Wawona-*-iOS-arm64-rootless.deb

# Official tipa. Same slim guest rule until Relay boots NixOS. Uninstall first
# if a leftover 5.7 G zip is still on the guest. Helper 176 is disk-full.
scripts/install-ios-modeb-tipa.sh --official result/Wawona-*-iOS-arm64.tipa
```

`vm` / `container` tokens fail closed on Relay (`No QEMU`). Do not prove
those cards with `wwn-qemu-run`. Guest GUI stays Wayland into iland.

`install-ios-modeb-tipa.sh` fails closed on low disk (helper-176 class) before
`trollstorehelper install force custom`. Kill `WawonaModeBDemo` before product
IOMFB tests. Unlock SpringBoard before claiming greeter failure. After replace:
`uicache -p` then `uiopen --app Wawona`. `uiopen --bundleid` returns 0 and
starts nothing on this iOS 26 guest.

Sock HID does not hit IOMFB greeter cards. After the greeter is up, write
tokens **as mobile**. Do not `chmod` the file after write:

```bash
su mobile -c 'printf replace >/tmp/wwn-modeb-select'
su mobile -c 'printf weston >/tmp/wwn-modeb-select'
# then: niri / vm / container
```

`replace` claims IOMFB (HID steal, last-surface hold, no SpringBoard park).
Named tokens start the card. Compact sock `{"t":"screenshot","screen":true}`
is the live frame; a 59 KB all-black JPEG is a stale IOMFB compact, not a
crash. Focus the `vphone-cli` window.

Do not `SwapWait` after every commit on this guest (paravirt never
CommandWakes). Do not SIGSTOP SpringBoard or `backboardd`. Home during a
live session must log `resign ignored phase=2` with no new `3735883980`
ips. Niri GLES needs a Metal device; vphone `MTLCreateSystemDefaultDevice`
is nil. That is the physical-class result. Do not spin ANGLE. Weston
remains the own-display compositor. Do not defer niri to STARDUST.

## Mode B channels (do not conflate)

| Channel | Artifact | Tool |
|---|---|---|
| TrollStore | `.tipa` + ldid | `packages tipa` |
| Sileo / APT | `.deb` / tweaks | `packages apt` |
| App Store Mode A | IPA | Xcode Simulator / physical, not vphone |

See `docs/mode-a-b.md` and agent rules `wawona-vphone-mode-b-packages`.
