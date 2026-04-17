# Wawona Linux Test Matrix

## Automated checks

- `cargo test` for compositor scene/scale coverage (`src/core/state/tests.rs`).
- `nix flake check` for Linux app package/app wiring.
- `nix run .#wawona-linux -- --help` sanity check for GTK shell startup path.

## Manual E2E checks

1. Run `nix run` on Linux and confirm the GTK shell opens.
2. In Settings, install user units and start host service.
3. Verify runtime state appears in Settings diagnostics (`healthy=true` with socket path).
4. In Machines, launch a **Native** profile and verify app appears in nested session.
5. Launch an **SSH Terminal** profile and verify SSH command execution.
6. Launch an **SSH+Waypipe** profile and verify remote app is rendered locally.
7. Run `nix run .#wawona-linux-tray` and verify host start/stop/restart controls.
8. Resize the app window across phone/tablet/desktop sizes and verify navigation remains usable.

## Compositor behavior checks

- **Stacking order**: bring windows to front and verify draw/hit-test order remains consistent.
- **HiDPI scale**: confirm pointer/touch targeting stays accurate on scale > 1 outputs.
- **Pointer constraints**: run relative-pointer client and verify lock/unlock transitions.
- **Event loop stability**: leave nested compositor active for an extended session and confirm no UI stalls.
