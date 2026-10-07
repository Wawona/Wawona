---
name: wawona-vphone-cli
description: Drive a live vphone-cli 2.6 guest from an agent. Sock-first Mode B package tests. Pair with agent-device MCP only when SSH or verified AX is up. Recover with wawona-vphone-lab-recover.
---

# vphone-cli for agents (Mode B lab)

Not Simulator. Not STARDUST. Proof device: `vphone wawona-jb`.

Rules: `wawona-vphone-control`, `wawona-vphone-mode-b-packages`,
`wawona-trollstore-tipa-dev`. Recover: `wawona-vphone-lab-recover`.
Lab: `wwn-vphone/scripts/vphone-jb-lab.sh`.

## Two processes (never mix)

| Process | What it is | Agent use |
|---|---|---|
| `vphone-cli` / `vphone-vm` | Host hypervisor. Owns the visible window and `vphone.sock`. | Launch once with `nohup`. Then leave it alone. |
| `vphoned` (guest) | Answers JSON on the sock. | `vphone-sock` / sock RPC. |
| agent-device MCP (`user-agent-device`) | Same Interactor as Simulator (`snapshot -i`, `press @eN`, `packages`). | UI refs after a verified frontmost app. `packages apt` only when guest SSH answers. |

`vphone-cli` is not a TTY you type iOS commands into. Navigate the guest
through the Unix socket (or SSH after OwnGoal). The agent-device MCP talks
to that same sock for AX and, when SSH is up, to `mobile@guest:22222`.

## Simple loop

```text
1. Live?   pgrep -lf 'vphone-vm.*machines/wawona-jb/config.plist'
           vphone-sock ping
2. Ready?  vphone-sock unlock
           (setup.skip only if setup.status pending/running. Do not skip twice.)
3. Act.    vphone-sock launch / open-url / ls / write / rpc / tap --points
4. UI.     apps.foreground verified=true, then agent-device snapshot -i / press
5. Deb.    packages apt only if nc guest-ip 22222 is open
```

CLI (VM already running):

```bash
nix run github:Wawona/wwn-vphone#vphone-sock -- ping
# local checkout:
python3 wwn-vphone/scripts/vphone-sock.py ping
python3 wwn-vphone/scripts/vphone-sock.py unlock
python3 wwn-vphone/scripts/vphone-sock.py screenshot "$PWD/.agent-device/test-artifacts/vphone.png"
python3 wwn-vphone/scripts/vphone-sock.py launch wiki.qaq.irisin
python3 wwn-vphone/scripts/vphone-sock.py open-url \
  'irisin://repository/add?url=https%3A%2F%2Frepo.wawona.io%2F'
python3 wwn-vphone/scripts/vphone-sock.py ls /var/jb/usr/bin
python3 wwn-vphone/scripts/vphone-sock.py write /var/jb/etc/apt/sources.list.d/wawona.list ./wawona.list
```

Bring-up (once): `nix run github:Wawona/wwn-vphone#vphone-jb-lab`.
That already does `setup.skip` and the Wawona APT source. Do not foreground
`vphone-cli vm launch`.

## How the sock is navigated

JSON one line in, one line out on
`~/.vphone/machines/wawona-jb/vphone.sock`.

| Need | Call |
|---|---|
| Alive | `{"t":"ping"}` (not `rpc` method `ping`) |
| Lock Screen | `screen.unlock` |
| Auto-lock off | `settings.set` `com.apple.springboard` `SBAutoLockTime` = 2147483647 |
| Setup | `setup.status` then `setup.skip` `{force:true}` only if pending/running |
| Files | `files.list` / `files.read` / `files.write` / `files.mkdir` |
| Apps | `apps.list` / `apps.launch` / `apps.foreground` / `apps.open_url` / `apps.install` |
| AX | `ui.tree` frames are **points**. Sock `t:tap` is **pixels** (`scale` from `device.screen`, 3 on iPhone, 2 on iPad lab) |
| Screenshot | `{"t":"screenshot","path":"…png","screen":false}`. Compact `screen:true` JPEG freezes. `guest agent is not connected` means retry after ping/unlock, do not relaunch. |

`ui.tap_element` needs `apps.foreground` `verified: true`. Home Screen
SpringBoard is never verified. `apps.launch` Irisin (`wiki.qaq.irisin`)
or Settings first.

Irisin add-repo URL (do not HID-type Search):
`irisin://repository/add?url=https%3A%2F%2Frepo.wawona.io%2F`

## agent-device MCP with vphone-cli

Namespace: `user-agent-device`. Device name: `vphone wawona-jb`.
Keep mutating commands serial on one `--session`.

| MCP / CLI | When it works |
|---|---|
| `snapshot -i` / `press @eN` | Sock `ui.tree` after a launched app is frontmost |
| `screenshot` | Visible VM window. Same sock PNG path |
| `packages tipa install` | Prefers sock `files.write` + `apps.install` when TrollStore SSH is absent |
| `packages status` / `packages apt …` | Guest SSH `:22222`. **Fails** `Connection refused` on stock 2.6 CFW |

SSH is `mobile` / `alpine` port `22222`. IP drifts. Read
`~/.vphone/VMs/wawona-jb/guest-ip.txt` or the profile `sshHost`. Match
the VM MAC in `/var/db/dhcpd_leases` (config `networkConfig.macAddress`).
Do not scan `192.168.64.{2..120}`. After a new IP, rewrite the profile
and **close** the agent-device session (it caches the old host).

`packages apt` is Procursus `apt-get`/`dpkg` over SSH. Irisin itself has
no dpkg (`/var/jb/usr/bin` may only contain `hello` until OwnGoal
`owngoal-bootstrap-vphone`). Apt sources can still be written on the sock:
`/var/jb/etc/apt/sources.list.d/wawona.list`.

## Mode B package tests (pick the row)

| Artifact | Without SSH | With SSH / OwnGoal |
|---|---|---|
| TrollStore `.tipa` | `vphone-sock write` + `rpc apps.install`. Never copy into `/var/jb/Applications` (helper **179**) | `agent-device packages tipa install … --open --jit` |
| Wawona APT source | `vphone-sock write` list + `open-url` Irisin add | `apt-get update` |
| `.deb` install | Irisin UI (native helper). Not `packages apt` | `packages apt install ./pkg.deb` or `apt-get install` |
| `wawona-launch-tools` | Same as `.deb` | `apt-cache policy wawona-launch-tools` then install |

Never mix tipa into `/var/jb/Applications`. Never `packages apt` as the
first probe on a fresh 2.6 guest.

### Irisin dpkg vs vphone-cli

`vphone-cli` never runs `dpkg`. Guest installer is
`/var/jb/usr/libexec/irisin-install`, database
`/var/jb/Library/dpkg` (not `/var/lib/dpkg`).

iOS 26 vphone `/bin` is `df` and `ps` only. No `/bin/sh`. A Debian
`postinst` with `#!/bin/sh` dies `Failure(errno: 2)`. Irisin then
aborts the whole transaction, including an unrelated unpack
(`wawona-launch-tools` never lands; `/var/jb/usr/bin` stays `hello`).

The Mode B demo `com.aspauldingcode.wawona.modeb.demo` can sit
`install ok half-configured`. The next Irisin install tries to
`configure` it first. OwnGoal (real jb shell) or drop the postinst.

### Lakr 2.6.0 (github.com/Lakr233/vphone-cli)

Authority: `Documents/Guides/package-environment.md`, skill
`Skills/vphone-guest-control/references/guest-layout.md`.
`AGENTS.md`: package-manager bootstrap is **outside** vphone-cli.

1. `bootstrap.install` only plants Irisin. No `apt`/`dpkg`. No maintainer
   scripts. Lakr recommends **roothide**. Rootless (`/var/jb`) is deprecated
   there. Wawona Mode B debs stay `iphoneos-arm64` rootless unless we change
   that product.
2. First packages are Irisin UI only. No RPC. Open OwnGoal Packages
   (`https://apt.owngoal.dev/`). Package `owngoal-bootstrap-vphone`.
   URL: `irisin://package/owngoal-bootstrap-vphone`.
3. Add Procursus as an **Advanced Source** first:
   URL `https://apt.procurs.us/`, suite `3000`, components `main`.
   A flat `irisin://repository/add?url=…procurs.us` is Unreachable.
4. Use **Bootstrap Install** (long-press Queue **Execute**). Sock:
   `vphone-sock longpress <x> <y>` (points). Plain **INSTALL** only queues;
   without Bootstrap Install, Depends resolve then fail.
5. Do not install `apt`, `bash`, `openssh-server` one by one.
6. First Bootstrap Install often **unpacks then Fails configure** (no jb
   `sh` yet). On the Failed sheet tap bottom **Try Again** (exact label).
   Never tap **Done** (its value also says "Try again").
7. If still Failed after Try Again: `bootstrap.uninstall` +
   `bootstrap.install`, then OwnGoal again. Script:
   `python3 wwn-vphone/scripts/vphone-owngoal-bootstrap.py --wipe`.
   Do not hand-edit the half dpkg DB. After uninstall, verify
   `apps.search irisin` before `open-url` (tombstone can lie).

## Hard rejects

- Foreground `vm launch`. `pkill -f vphone`
- Trust `agent-device devices` `booted=true`
- `rpc` method `ping` (unknown). Use `t:ping`
- Repeat `setup.skip` on `setup_done` (launchd 144)
- DHCP-scan every lease
- HID-type `repo.wawona.io` in Irisin Search
- Park Mode B packages on Simulator / STARDUST / retail iPhone
