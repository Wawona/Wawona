# Watch: bundled clients gate

One automated pass that exercises both Machines bundled clients
(`kAllBundledClients` in `WWNMachinesViewModel.swift`) on every runnable
platform target: `wawona-shell` and `wawona-wasm`. Nested compositors and demo
clients are optional software, installed through `wpm` or apt, so this gate
does not treat them as bundled clients.

## Run

```bash
# All platforms × all clients (uses /tmp/wawona-*-gate.app when present)
cargo xtask lab matrix

# Subset
cargo xtask lab matrix ios
WAWONA_MATRIX_CLIENTS="wawona-shell" cargo xtask lab matrix ios
```

Artifacts: `.agent-device/test-artifacts/bundled-clients-matrix/<stamp>/`

- `SUMMARY.md`. PASS/FAIL/SKIP table
- `summary.json`. Machine-readable
- `matrix.log`. Full run log
- `<platform>/<client>/`. Prefs, install, launch, console, screenshot

Failure line:

```text
MATRIX_FAIL count=3 cells=ios/niri,android/vkcube,visionos/foot
```

## How each cell works (Apple)

1. Write Machine profile prefs (`bundledAppID=<client>`): `cargo xtask lab set-client <client> ios`
2. `simctl install`, then `simctl launch` with `WAWONA_AUTO_CLIENT=<client>`; the scene delegate starts the client
   (`WAWONA_MATRIX_USE_AGENT_DEVICE=1` presses **Start** through agent-device instead)
3. Hold N seconds; require the process still alive
4. Scan the console for fail markers (`niri_main: panicked`, `Unknown bundled client id`, ...)

Android writes the prefs, then presses **Start** over UI Automator. macOS writes host `defaults` and
launches its own child with `WAWONA_AUTO_CLIENT`; it refuses to run beside another Wawona.

## Platform skips

Per [platform-targets](../../.cursor/rules/wawona-platform-targets.mdc): tvOS/watchOS skip
`kmscube` / `opengl-cube` / `vkcube` / `weston-simple-egl` (no Vulkan/OpenGL/ANGLE).

Missing app or device → `SKIP` (CI: set `WAWONA_MATRIX_STRICT=1` to require PASSes).

## Related

- Leak idle plateau: [`leak-idle-gate.md`](./leak-idle-gate.md)
- Prefs: `cargo xtask lab set-client <client> ios|android`
- Catalog: `xtask/src/lab/clients.rs` (must track `kBundledClients`)
