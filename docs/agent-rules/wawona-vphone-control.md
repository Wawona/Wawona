# vphone control (research Mode B lab)

Indexed mirror of `.cursor/rules/wawona-vphone-control.mdc`.

```bash
nix run github:Wawona/wwn-vphone#vphone-jb-lab
nix run github:Wawona/wwn-vphone#vphone-ipad-lab
agent-device devices
agent-device snapshot -i --device "vphone wawona-jb"
agent-device packages status --device "vphone wawona-jb" --session vphone
```

iPadOS Mode B is `vphone wawona-ipad` (`vphone-ipad-lab`, iPad16,1, API
127.0.0.1:8766, sock scale 2). Tipa without TrollStore SSH uses sock
`files.write` then `apps.install`. Deb/JIT needs rootless Irisin plus
OwnGoal `owngoal-bootstrap-vphone`. Do not stop `wawona-jb` to boot it.

Prefer name `vphone wawona-jb`. Packages over SSH (no sftp). Never commit
Disk.img/IPSW. Never attach to watchdogd/IOWatchdog.

`vphone wawona-jb` is the Mode B TrollStore / IOMFB / open-jit proof
device. Treat it as physical-class. Do not wait for STARDUST or a retail
iPhone. TXM limits (MAP_JIT write+exec `EPERM`, Metal nil) are proven
results. Weston remains own-display.

Stuck lab recover is automatic. Skill `wawona-vphone-lab-recover`. Trust
`vphone-vm` plus `~/.vphone/machines/wawona-jb/config.plist` and a live sock.
vphone-cli 2.6.0 does not boot 1.x disks under `~/.vphone/VMs`. Do not
trust `booted=true`. `nohup` relaunch (`vm launch`, no `-V jb`). Never
foreground `vm launch` in an agent Shell. Never `pkill -f vphone` to stop
a waiter. Guest AX is sock `ui.tree`.

A fresh guest boots into Setup.app. Do not tap it. `setup.skip` with
`force: true` writes the purplebuddy keys and resprings. `screen.unlock`
passes the Lock Screen. The same lab pass writes
`/var/jb/etc/apt/sources.list.d/wawona.list` (`deb https://repo.wawona.io/ ./`)
and opens `irisin://repository/add?url=https://repo.wawona.io/`. When SSH
is up it runs `apt-get update`. Do not HID-type that URL in Irisin Search.
`ui.tree` needs a launched app. SpringBoard on
the Home Screen is not a verified frontmost process.

Live guest: `python3 wwn-vphone/scripts/vphone-sock.py ping` or
`nix run .#vphone-sock -- ping` once the pin exports it. Skill
`wawona-vphone-cli`. `packages apt` needs SSH.

See also: `wawona-trollstore-tipa-iteration`, `wawona-vphone-mode-b-packages`,
`wawona-vphone-lldb`, `wawona-vphone-cli`.
