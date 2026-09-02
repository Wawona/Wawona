# vphone Mode B packages (tipa / Sileo apt)

Indexed mirror of `.cursor/rules/wawona-vphone-mode-b-packages.mdc`.

| Channel | Command |
|---|---|
| TrollStore tipa | `packages tipa install\|open-jit\|uninstall\|info` |
| Sileo/APT deb | `packages apt update\|install\|remove\|list\|policy\|sources` |
| LLDB handoff | `packages debug attach` → user-lldb |

Lab: `nix run github:Wawona/wwn-vphone#vphone-jb-lab` (installs Procursus
debugserver). Tipa rebuilds: `wawona-trollstore-tipa-iteration`. Control:
`wawona-vphone-control`.
