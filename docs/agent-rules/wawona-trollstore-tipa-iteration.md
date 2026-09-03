# TrollStore tipa iteration (vphone)

Short loop for Mode B `.tipa` work. Full design, ents, JIT, IOMFB, tipa vs
Sileo deb, and fail codes: **`wawona-trollstore-tipa-dev`**.

Not App Store IPA. Not Sileo `.deb`.

## Version vs build (hard)

| Field | Meaning | Example |
|---|---|---|
| `CFBundleShortVersionString` | Marketing / CalVer | `26.9.2` |
| `CFBundleVersion` | **Build** (install identity) | `11`, `12`, … |

Reinstalling the **same build** is a no-op / refuse. Bump **BUILD** every tipa
you intend to replace on guest.

```bash
./scripts/build-modeb-demo-tipa.sh
# or: BUILD=12 ./scripts/build-modeb-demo-tipa.sh
```

Sign with **ldid** on the binary only (no `_CodeSignature` in the tipa). Never
Ship: beta / TestFlight / ASC.

## Install / verify loop

```text
1. Build tipa (new CFBundleVersion)
2. packages tipa info <bundle>          # note guest build
3. packages tipa install ./App.tipa --device "vphone wawona-jb"
   # helper: install force custom <path>  (NOT installforce)
4. tipa info: path under /var/containers/Bundle/Application/…
5. packages tipa open-jit <bundle>
6. sock screenshot / UI: JIT OK + IOMFB
```

Never copy the `.app` into `/var/jb/Applications/` (error **179**).

## JIT

- Prefer one process: self-ptrace (no-sandbox), else attach (`enable-jit` /
  `enable_jit_pid`), else magnifier once + re-probe on become active.
- Never kill + cold-relaunch for JIT. PID match `…/$EXE` only (not `*$EXE*`).
- helper_rc **3** = ESRCH: app not running.
- Prefer attach while alive; magnifier is same-PID attach, not a new launch.

## Related

`wawona-trollstore-tipa-dev`, `wawona-vphone-mode-b-packages`,
`wawona-vphone-control`, `wawona-ios-mode-b-channels`.
