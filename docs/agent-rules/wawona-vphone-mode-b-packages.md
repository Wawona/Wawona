# vphone Mode B packages (tipa / Sileo apt)

Indexed mirror of `.cursor/rules/wawona-vphone-mode-b-packages.mdc`.

Lab: `nix run github:Wawona/wwn-vphone#vphone-jb-lab` (L3′, no prebuilt VM).

| Channel | Command |
|---|---|
| TrollStore tipa | `agent-device packages tipa install\|open-jit\|uninstall\|info` |
| Sileo/APT deb | `agent-device packages apt update\|install\|remove\|list\|policy\|sources` |
| LLDB handoff | `agent-device packages debug attach` → user-lldb |

Never enable-jit before a live PID (helper exit 3 = ESRCH). Never ship IPSW/Disk.img in git.
