# Mode B helpers (macOS Desktop / LockScreen only)

`wwn-iowatchdog` source and other Watchdog CLIs live in the L3′ repo
[`Wawona/wwn-iowatchdog`](https://github.com/Wawona/wwn-iowatchdog).

Wawona's `macos.nix` copies `${iowatchdog}/bin/wwn-iowatchdog` into
`Contents/Library/Wawona/` when bundling `iland-baremetal`. Do not re-add
the C source here.
