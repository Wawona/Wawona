# vphone-cli Nix wrap (Darwin Apple Silicon)

Jailbroken iOS 26 lab for Wawona Mode B proof. Not the Xcode Simulator.
Upstream: https://github.com/Lakr233/vphone-cli (`jb` variant).

## Host gates

- Apple Silicon, macOS 15+, Xcode + iOS SDK
- Non-nested host
- SIP Option A: `csrutil disable` + `amfi_get_out_of_my_way=1` (this Mac)
- **`csrutil allow-research-guests enable`** (Recovery). Required for PV=3 DFU boot
- Partial SIP + amfidont is not enough for Wawona Classic

Do not flip Recovery/nvram from the agent. Operator owns that.

## One command (preferred)

From the Wawona checkout on Darwin aarch64:

```bash
nix run .#vphone-jb-lab
```

That script:

1. Checks host gates (fails with Recovery instructions; never mutates nvram)
2. Ensures `vphone-cli` + nix tools (`ldid-procursus`, libusb, aria2, sshpass)
3. Creates `wawona-jb` if missing (`-V jb`, iOS 26.1 / cloudOS 26.1, non-interactive IPSW URLs)
4. Resumes restore / CFW when a partial bundle already exists
5. Launches the VM, waits for guest NAT SSH (`mobile@192.168.64.x:22222`)
6. **Disables guest auto-lock** (`SBAutoLockTime=0` / `SBAutoLockDisabled`) so
   SpringBoard never drops to the lock screen mid-automation
7. Smokes Sileo + TrollStore Lite via `/var/log/vphone_jb_setup.log`
8. Writes artifacts under `.agent-device/test-artifacts/dmabuf/vphone-jb/` (or `~/.vphone/artifacts/vphone-jb`)
   plus `.agent-device/vphone-wawona-jb.json` for the Wawona `agent-device` fork

Sock automation needs a **visible** (non-headless) VM window. Host `caffeinate`
runs during launch; guest auto-lock is cleared in bootstrap (see `autolock.txt`).

Flags:

```bash
nix run .#vphone-jb-lab -- --gate-only    # host checks only
nix run .#vphone-jb-lab -- --smoke-only   # SSH smoke against a running guest
```

Env overrides: `VPHONE_ROOT`, `VPHONE_VM_NAME`, `VPHONE_DISK_GB`, `VPHONE_IOS_URL`,
`VPHONE_CLOUDOS_URL`, `VPHONE_ARTIFACTS`, `WAWONA_ROOT`.

Raw CLI (manual stages):

```bash
nix run .#vphone-cli -- vm create wawona-jb -V jb --disk-size 32 \
  -i "$IPHONE_URL" -c "$CLOUDOS_URL"
nix run .#vphone-cli -- vm launch wawona-jb -V jb
```

## Access

After a green lab run:

```bash
# guest IP is also in the artifact guest-ip.txt / ready.txt
ssh -p 22222 mobile@192.168.64.XX   # password alpine
open vnc://192.168.64.XX:5901
```

SSH is on the **guest NAT address**, not `localhost` (VZ NAT). Prefer
`guest-ip.txt` from the lab artifacts.

## agent-device (Wawona fork)

Pin is `nix-darwin` `modules/pkgs/_agent-device.nix` → local
`~/Wawona/agent-device` (`0.18.3-wawona.1`). After pulling fork changes:

```bash
cd ~/Wawona/agent-device && nix shell nixpkgs#pnpm -c pnpm build
# then refresh the home package / MCP wrapper
nh switch   # or your usual darwin-rebuild / home-manager switch
```

Device selector (name works best; colon ids can confuse some shells):

```bash
export WAWONA_ROOT=~/Wawona/Wawona
agent-device devices                    # expect: vphone wawona-jb … booted=true
agent-device open --device "vphone wawona-jb" --session vphone
agent-device screenshot --session vphone --out /tmp/vphone.png
agent-device apps --session vphone
agent-device install path/to/App.tipa --session vphone
agent-device replay .agent-device/vphone-modeb-smoke.ad
```

Install path: SSH + `trollstorehelper install` (guest often has no `sftp-server`,
so the fork pushes via `ssh … cat > file`). Does **not** require vphoned vsock.

### Known guest limits (research iOS 26 jb)

| Surface | Status |
|---|---|
| Host sock screenshot / tap / swipe / home | OK |
| SSH apps / tipa install / uiopen | OK |
| Snapshot refs | SSH icon-grid fallback when sock `ax` / vsock control is down |
| vphoned control (`ipa_install` over vsock 1337) | Often **reset by peer** on this guest (no reliable `/dev/vsock`); use SSH tipa path |
| `MAP_JIT` in Mode B tipa | Entitlements stamp OK; `mmap(MAP_JIT)` may still return `errno=22` on research guests even after `trollstorehelper enable-jit` |

## Disk / tools notes

- First create downloads ~12G+ IPSWs under `~/.vphone/ipsws`. Prefer ≥64G free
  (128G+ for cold create).
- CFW signing needs **ldid-procursus** (nix attribute). Plain `ldid` fails PKCS12.
- DFU restore needs **libusb** on `DYLD_LIBRARY_PATH` (wired by the nix wrap).
- `nix run .#vphone-cli` puts those on PATH automatically.

## Proof loop (Mode B packages)

1. Lab green (`ready.txt` + SSH smoke)
2. Sileo: add `https://repo.wawona.io` (test `/jailbreak/test/` while on feature branch)
3. Install rootless Wawona `.deb` + ElleKit tweak
4. TrollStore: install `.tipa`
5. Artifacts: `Wawona/.agent-device/test-artifacts/dmabuf/vphone-jb/`
