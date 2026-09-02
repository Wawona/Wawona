# vphone-cli Nix wrap (Darwin Apple Silicon)

Jailbroken iOS 26 lab for Wawona Mode B proof. Not the Xcode Simulator.
Upstream: https://github.com/Lakr233/vphone-cli (`jb` variant).

## Host gates

- Apple Silicon, macOS 15+, Xcode + iOS SDK
- Non-nested host
- SIP Option A: `csrutil disable` + `amfi_get_out_of_my_way=1` (this Mac)
- Partial SIP + amfidont is not enough for Wawona Classic

Do not flip Recovery/nvram from the agent. Operator owns that.

## Usage

```bash
nix run .#vphone-cli -- vm create wawona-jb -V jb
nix run .#vphone-cli -- vm launch wawona-jb
# VNC :5901  SSH :22222 mobile/alpine
```

IPSWs and `~/.vphone/` stay out of git (`VPHONE_ROOT`). First create downloads
tens of GB. Prefer ≥128GB free disk.

## Proof loop

1. Wait `/var/log/vphone_jb_setup.log` for Sileo + TrollStore
2. Sileo: add `https://repo.wawona.io` (test `/jailbreak/test/` while on feature branch)
3. Install rootless Wawona `.deb` + ElleKit tweak
4. TrollStore: install `.tipa`
5. Artifacts: `Wawona/.agent-device/test-artifacts/dmabuf/vphone-jb/`
