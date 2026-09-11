# vphone control (research Mode B lab)

Indexed mirror of `.cursor/rules/wawona-vphone-control.mdc`.

```bash
nix run github:Wawona/wwn-vphone#vphone-jb-lab
agent-device devices
agent-device snapshot -i --device "vphone wawona-jb"
agent-device packages status --device "vphone wawona-jb" --session vphone
```

Prefer name `vphone wawona-jb`. Packages over SSH (no sftp). Never commit
Disk.img/IPSW. Never attach to watchdogd/IOWatchdog.

`vphone wawona-jb` is the Mode B TrollStore / IOMFB / open-jit proof
device. Treat it as physical-class. Do not wait for STARDUST or a retail
iPhone. TXM limits (MAP_JIT write+exec `EPERM`, Metal nil) are proven
results. Weston remains own-display.

Stuck lab recover is automatic. Skill `wawona-vphone-lab-recover`. Trust
`vphone-cli --config …/wawona-jb/config.plist` plus sock connect. Do not
trust `booted=true`. `nohup` relaunch. Never foreground `vm launch` in an
agent Shell. Never `pkill -f vphone` to stop a waiter.

See also: `wawona-trollstore-tipa-iteration`, `wawona-vphone-mode-b-packages`,
`wawona-vphone-lldb`.
