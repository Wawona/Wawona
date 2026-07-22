# Bundled clients matrix gate

One automated pass that exercises **every** Machines bundled native client
(`kBundledClients` in `WWNMachinesViewModel.swift`) on every runnable platform
target. Nested compositors (`weston`, `niri`) and all demo clients are included.

## Run

```bash
# All platforms × all clients (uses /tmp/wawona-*-gate.app when present)
./scripts/bundled-clients-matrix-gate.sh

# Subset
./scripts/bundled-clients-matrix-gate.sh ios ipados
WAWONA_MATRIX_CLIENTS="niri,weston,weston-terminal" ./scripts/bundled-clients-matrix-gate.sh ios
```

Artifacts: `.agent-device/test-artifacts/bundled-clients-matrix/<stamp>/`

- `SUMMARY.md` — PASS/FAIL/SKIP table
- `summary.json` — machine-readable
- `matrix.log` — full run log
- `<platform>/<client>/` — prefs, install, lldb, console, screenshot

Failure line:

```text
MATRIX_FAIL count=3 cells=ios/niri,android/vkcube,visionos/foot
```

## How each cell works (Apple)

1. Write Machine profile prefs (`bundledAppID=<client>`) via `agent-device-set-client-ios.sh`
2. `simctl install` + `launch`
3. LLDB `connectProfile:` (same inject as the leak campaign)
4. Hold N seconds; require process still alive
5. Scan console/lldb for fail markers (`niri_main: panicked`, `Unknown bundled client id`, …)
6. LLDB `disconnectProfile:`

Android uses prefs + agent-device **Start**. macOS uses host `defaults` + LLDB.

## Platform skips

Per [platform-targets](../../.cursor/rules/wawona-platform-targets.mdc): tvOS/watchOS skip
`kmscube` / `opengl-cube` / `vkcube` / `weston-simple-egl` (no Vulkan/OpenGL/ANGLE).

Missing app or device → `SKIP` (CI: set `WAWONA_MATRIX_STRICT=1` to require PASSes).

## Related

- Leak idle plateau: [`leak-idle-gate.md`](./leak-idle-gate.md)
- Prefs helpers: `scripts/agent-device-set-client-{ios,android}.sh`
- Catalog: `scripts/lib/bundled-clients-catalog.sh` (must track `kBundledClients`)
