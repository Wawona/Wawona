# TrollStore `.tipa` development and automation (Wawona)

Authority for **how** to build, install, JIT-enable, and framebuffer-test Mode B
tipas. Product channel table: `wawona-ios-mode-b-channels`. Package CLI:
`wawona-vphone-mode-b-packages`. Lab bring-up: `wawona-vphone-control`.

Upstream references (read when debugging install/JIT/ents):

- [opa334/TrollStore README](https://github.com/opa334/TrollStore) (URL scheme,
  ldid ents, unsandbox, banned ents)
- TrollStore 2.0.12+: **Open with JIT** +
  `apple-magnifier://enable-jit?bundle-id=`
- Helper install argv (TSApplicationsManager):
  `install [force] custom|installd <ipa>`
- Helper JIT: `enable-jit <bundle-id>` (RBS + `PT_ATTACHEXC`)

## Two Mode B delivery paths (never conflate)

| | **TrollStore `.tipa`** | **Sileo `.deb` / jailbreak** |
|---|---|---|
| Install | `trollstorehelper install …` into `/var/containers/Bundle/Application/` | `dpkg` / `packages apt` under `/var/jb` |
| Signing | Host **`ldid -Sents`** then TS resigns with fake CT | Procursus / package scripts |
| JIT | **Open with JIT** / magnifier URL / `enable-jit` → `CS_DEBUGGED` | ElleKit / process / different engines |
| IOMFB | ldid private ents + iokit user-client exceptions | Same SPI possible; often SpringBoard tweak path |
| ElleKit / host APT / Swinging Bridge | **No** | **Yes** (full Mode B) |
| Ship name | `Wawona-{calver}-iOS-arm64.tipa` | `…-rootless.deb` / `…-rootful.deb` |
| Automation | `packages tipa …` | `packages apt …` |

Store IPA is Mode A only. Never mix tipa ents into ASC builds.

## What a tipa must contain

1. `Payload/App.app/{executable,Info.plist}` only. **No** `_CodeSignature/`
   (ldid the binary; do not ldid-sign the `.app` directory).
2. `CFBundleShortVersionString` = marketing CalVer; `CFBundleVersion` = build
   (bump every reinstall).
3. Entitlements via `ldid -Sfile.entitlements` (preserved by TrollStore).

### JIT (required for MAP_JIT)

```xml
<key>get-task-allow</key><true/>
```

Entitlements alone do **not** set `CS_DEBUGGED`. Prefer **one process**:

1. **Pojav-style self-enable** (tipa with `no-sandbox`): short child
   `ptrace(PT_TRACE_ME)`, parent detach. Not a second UI launch.
2. Else **TrollStore Open with JIT** / `trollstorehelper enable-jit` /
   `enable_jit_pid` attach to the **live** `…/App.app/Exe` PID.
3. Else app opens `apple-magnifier://enable-jit?bundle-id=…` **once**;
   TrollStore attaches and returns to the **same** process. Re-probe on
   `applicationDidBecomeActive`.

Do **not** kill + cold-relaunch for JIT. Do **not** match `*$EXE*` in `ps`
(hits SSH `bash -c`). Match only argv ending in `/$EXE`.

Do **not** rely on `dynamic-codesigning` on modern A12+ (TrollStore: banned;
crash on launch). Prefer get-task-allow + attach / self-ptrace.

On **iOS 26 research / TXM** guests (vphone), attach may set `CS_DEBUGGED=1`
while `mmap(MAP_JIT)` still returns `EPERM`. Treat that as **JIT ARMED**
(attach path proven); full MAP_JIT OK remains the real-device tipa target.

### IOMobileFramebuffer (tipa Desktop / FB proof)

Minimum pattern (FBVNCPublic concepts; **never** IOWatchdog):

```xml
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<!-- or no-container; keep a data container if you still need one -->
<key>com.apple.private.IOMobileFramebuffer</key><true/>
<key>com.apple.private.allow-explicit-graphics-priority</key><true/>
<key>com.apple.IOSurface.IOSurface</key><true/>
<key>com.apple.security.iokit-user-client-class</key>
<array>
  <string>IOMobileFramebufferUserClient</string>
  <string>IOSurfaceRootUserClient</string>
</array>
```

Draw path: `GetMainDisplay` (else Secondary) → size → optional
`GetLayerDefaultSurface` → `IOSurfaceCreate` BGRA → lock/base → pixels →
`SwapBegin` / `SwapSetLayer` / `SwapEnd`.

Hard forbid: `com.apple.private.iowatchdog.user-access` and any watchdog disable
(`wawona-mode-b-watchdog-safety`).

## Hard rejects

- Putting the tipa app under `/var/jb/Applications/` (TrollStore **179**: treated
  as system/jb app; install blocked forever for that bundle id until removed)
- Fake helper verb `installforce` (Lite often returns 0 and installs nothing)
- Wrong argv: must be `install force custom <path.tipa>` (or `installd`)
- Xcode Simulator / visionOS for tipa/IOMFB/JIT proofs
- VNC as the control plane (use vphone **sock** + SSH + agent-device)
- App Store / TestFlight / Ship: beta for tipa
- Conflating tipa proof with Sileo `.deb` proof

## Agent automation stack (LLM loop)

```text
nix run github:Wawona/wwn-vphone#vphone-jb-lab   # or local .#vphone-jb-lab
  → guest SSH + TrollStore Lite + Sileo + debugserver
agent-device (Wawona fork, 0.18.3-wawona.N+)
  → packages tipa|apt|debug   (device "vphone wawona-jb" only)
vphone-cli (signed .app binary)   → vm launch / stop
sock ~/.vphone/VMs/wawona-jb/vphone.sock   → screenshot/tap (not VNC)
```

Never: `xcrun simctl boot`, visionOS schemes, or `vnc://` for this loop.

### Iterate / test / prove (tipa)

```bash
# 1) Build (auto-bumps CFBundleVersion)
./scripts/build-modeb-demo-tipa.sh

# 2) Install via TrollStore only (agent-device)
node agent-device/bin/agent-device.mjs packages tipa install ./….tipa \
  --device "vphone wawona-jb"

# 3) Confirm container install (not /var/jb/Applications)
packages tipa info com.aspauldingcode.wawona.modeb.demo --device "vphone wawona-jb"
# path must be /var/containers/Bundle/Application/…/*.app

# 4) Open with JIT
packages tipa open-jit com.aspauldingcode.wawona.modeb.demo --device "vphone wawona-jb"

# 5) Evidence: sock screenshot (JIT OK + IOMFB text), optional debug attach
```

Success criteria for the Mode B tipa demo:

1. Installed by **TrollStore** into containers (TS mark / path under Bundle/Application)
2. UI shows **JIT: OK** (MAP_JIT write+exec) after open-jit / magnifier
3. UI / display shows **IOMFB** swap success (FBVNCPublic-style text/checker)

### Fail checklist

| Code / symptom | Meaning | Fix |
|---|---|---|
| helper **166** | IPA path missing/inaccessible | Push tipa; retry |
| helper **171** | Non-TS app same id | `install force custom` |
| helper **179** | Id collides with system/jb app | `rm -rf /var/jb/Applications/That.app`; never reinstall there; new bundle id if LS poisoned |
| helper **3** (enable-jit) | ESRCH / no live PID | Open first; PID path match full `…/Exe$`; magnifier URL |
| MAP_JIT errno 22 | No `CS_DEBUGGED` | open-jit / magnifier while alive |
| GetMainDisplay no device | Ents / not TS-installed / guest FB | Confirm containers install + IOMFB + iokit exceptions |
| Install "OK" but path under `/var/jb` | Not a tipa install | Uninstall; install via helper only |

## Demo tipa (single Mode B proof app)

Builder: `Wawona/scripts/build-modeb-demo-tipa.sh`
Bundle: `com.aspauldingcode.wawona.modeb.demo`
Artifact: `.agent-device/test-artifacts/dmabuf/vphone-jb/WawonaModeBDemo-{calver}-iOS-arm64.tipa`
URL scheme: `wawona-modeb-demo://`
Paint source: `Wawona/scripts/modeb-fb-jit-paint.s`

**One tipa** covers the Mode B proofs (not separate FbJit/probe tipas; not UTM):

1. **IOMFB graphics.** JIT `paint_frame` full-frame plasma + soft orbs into a double-buffered IOSurface, then SwapBegin/Set/End.
2. **Text.** Host glyphs draw **`Hello, Wawona World!`** on the framebuffer each redraw.
3. **JIT showcase.** W^X emit (prefer `vm_allocate` then RX; else MAP_JIT): probe + `fib(n)` every tick; HUD `LIVE … fib(n)=…`.

```bash
./scripts/build-modeb-demo-tipa.sh
packages tipa install ./….tipa --device "vphone wawona-jb"
packages tipa open-jit com.aspauldingcode.wawona.modeb.demo --device "vphone wawona-jb"
# sock screenshot: plasma + orbs + Hello + LIVE fib HUD
```

Legacy `build-modeb-fb-jit-tipa.sh` is obsolete; use the demo tipa above.

## Related

`wawona-ios-mode-b-channels`, `wawona-trollstore-tipa-iteration`,
`wawona-vphone-mode-b-packages`, `wawona-vphone-control`,
`wawona-mode-b-watchdog-safety`.
