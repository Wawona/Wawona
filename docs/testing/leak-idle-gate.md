# Watch: idle memory (CI)

Reproducible **Start → hold → Stop** memory plateau check for product builds.
Converts local agent-device + Instruments dogfood into a GitHub Actions job matrix
that fails with an explicit failing **target** name.

Authority for methodology: [`.agent-device/test-artifacts/instruments/LEAK-IDLE-CAMPAIGN.md`](../../.agent-device/test-artifacts/instruments/LEAK-IDLE-CAMPAIGN.md).

## Why not Instruments MCP / xctrace?

- Instruments MCP is an IDE agent tool. Not available on GitHub runners.
- `xctrace` Allocations traces are often **empty on iOS 26 Simulator** (ISSUE-012).
- The campaign already gates Apple mobile on **`phys_footprint` plateau** and Android on **`dumpsys meminfo` TOTAL PSS**.

CI uses those same metrics.

## What “pass” means

After pressing **Start** on Machines:

1. Sample memory every `WAWONA_LEAK_SAMPLE_SEC` (default 15s) for `WAWONA_LEAK_HOLD_SEC` (default 60s).
2. Fail if `(max − min) > WAWONA_LEAK_PLATEAU_MB` (default 20 MB).
3. Fail if samples are strictly monotonic and total climb ≥ `WAWONA_LEAK_MONO_MB` (default 8 MB).
4. Fail if the process dies or sampling fails.

Idle→Start jump is allowed; **unbounded growth during the hold** is not.

## Targets (CI matrix)

| Target | Runner | Binary | Metric | Job name |
|--------|--------|--------|--------|----------|
| `ios` | `macos-26` + iPhone sim | `product-ios-sim` | `vmmap` phys_footprint | `Leak idle: iOS` |
| `android` | `ubuntu-latest` + API 34 emu | `product-android-apk` | dumpsys TOTAL PSS | `Leak idle: Android` |
| `macos` | `macos-26` | `product-macos-app` | host `vmmap` phys_footprint | `Leak idle: macOS` |

Extended Apple targets (iPadOS / visionOS / tvOS / watchOS) are gated **locally** with the same script patterns and campaign artifacts; they are not on GitHub-hosted runners yet.

## Workflow

[`.github/workflows/leak-idle-gate.yml`](../../.github/workflows/leak-idle-gate.yml) (**Watch: idle memory**)

Triggers:

- **Gate: products** `workflow_call` with `products_ready: true` (product-path push to
  `development` / `master`). Downloads that run’s `product-*` artifacts; does **not**
  re-call `product-build` (avoids tip concurrency cancel against Gate: products)
- `workflow_dispatch` (optional `lanes`: `all|ios|android|macos`). Builds under tip_key
  `leak-idle-*`
- nightly schedule (`30 9 * * *` UTC). Same namespaced product-build tip_key

**Not** a promote blocker. Idle-memory jobs use `continue-on-error` inside the
reusable workflow (`continue-on-error` is invalid on `uses:` callers). The
**Gate: products** rollup job does not `needs:` Watch: idle memory. Promote still requires **Gate: packages** +
**Gate: products** only. Treat red Watch: idle memory as a signal to triage before promote.

### Failure identification

The `Leak idle summary` job prints:

```text
LEAK_GATE_FAIL targets=ios,android
```

and fails the workflow. Per-target artifacts upload as `leak-idle-<target>/` containing:

- `<target>-timeline.txt`. `t_sec mb iso`
- `<target>-plateau.json`. Spread / limits
- `verdict.json`. `{target,status,reason,…}`
- screenshots when Start/hold fails

## Local reproduction

```bash
# iOS (product or Xcode build)
export WAWONA_IOS_APP=/path/to/Wawona.app
export WAWONA_LEAK_STRICT=1
./scripts/leak-idle-gate.sh ios

# Android
export WAWONA_ANDROID_APK=/path/to/Wawona.apk
export WAWONA_ANDROID_SERIAL=emulator-5554   # or device
./scripts/leak-idle-gate.sh android

# macOS
export WAWONA_MACOS_APP=/path/to/Wawona.app
./scripts/leak-idle-gate.sh macos

# Rollup after any combination
./scripts/leak-idle-gate.sh summary
```

Artifacts land under `.agent-device/test-artifacts/leak-idle-gate/<target>/`.

### Threshold knobs

| Env | Default | Meaning |
|-----|---------|---------|
| `WAWONA_LEAK_HOLD_SEC` | `60` | Hold after Start |
| `WAWONA_LEAK_SAMPLE_SEC` | `15` | Sample period |
| `WAWONA_LEAK_PLATEAU_MB` | `20` | Max spread during hold |
| `WAWONA_LEAK_MONO_MB` | `8` | Strict climb fail threshold |
| `WAWONA_LEAK_STRICT` | `0` local / `1` CI | Fail when target skipped (no device/app) |

## Scripts

- [`scripts/leak-idle-gate.sh`](../../scripts/leak-idle-gate.sh). Agent-device Start/Stop + hold
- [`scripts/lib/leak-idle-measure.sh`](../../scripts/lib/leak-idle-measure.sh). Footprint / PSS parse + plateau analyze
