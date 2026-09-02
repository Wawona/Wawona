# vphone control (research Mode B lab)

Indexed mirror of `.cursor/rules/wawona-vphone-control.mdc`.

```bash
nix run github:Wawona/wwn-vphone#vphone-jb-lab
agent-device packages status --device "vphone wawona-jb" --session vphone
```

Prefer name `vphone wawona-jb`. Packages over SSH (no sftp). Never commit
Disk.img/IPSW. Never attach to watchdogd/IOWatchdog.

See also: `wawona-trollstore-tipa-iteration`, `wawona-vphone-mode-b-packages`,
`wawona-vphone-lldb`.
