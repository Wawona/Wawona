# Mode A StaticCpu SHM tip (hard gates)

Authority: skill `wawona-staticcpu-shm-tip`, RAG
`wwn-mcp/knowledge/wawona/staticcpu-shm-tip.md`,
`Relay/crates/relay-vm/src/shm_import.rs`,
`Relay/docs/agentic-graph-staticcpu.md`.

Completely complete Mode A VM stays **0%** until store TestFlight. N16 /
STARDUST are human gates. Do not park SHM engineering on them.

## Hard rejects

1. Import `BUFFER_DIFF` / `last_file` pixels when MiniCompositor `buffers` is
   empty (ghost frame; no `wl_buffer.release` target).
2. Claim shm-ui green from `AUTH_OK` alone, or from **64x625-only** /
   **200x200** imports without an 800x600 / 1.92MiB `OPEN_FILE`. Stock
   `weston-smoke` hardcodes 200x200; guest must ship the 800x600 patch.
3. Lab-synth guest Bundle directory named `guest-4k`. Required name:
   `wawona-nixos-guest-4k` (or `…-16k`).
4. Treat host `/tmp/wawona_sim_<uid>/relay-shm.log` (no UDID suffix) as live tip
   evidence when a per-UDID runtime dir is in use.
5. Rebuild the NixOS guest to "fix" held buffers while `BUFFER_DIFF` already
   arrives on vsock 1024.
6. Shared `XDG_RUNTIME_DIR` / `wayland-0` across two booted simulators.

## Required tip evidence order

```text
exclusive UDID + writable tip
  → lab-synthesized … guest=4k
  → READY=1 + AUTH_OK=1
  → held=0 + imported SHM frame (prefer 800x600)
  → Mode A SHM present log + non-black screenshot
```

## Code ownership

| Layer | Path |
|-------|------|
| MiniCompositor SHM | `Relay/crates/relay-vm/src/shm_import.rs` |
| Graph ticks | `Relay/docs/agentic-graph-staticcpu.md` |
| Lab-synth / AUTO_START | Wawona Apple Machines + SceneDelegate |
| Per-UDID runtime | `preferredSharedRuntimeDir` |

Cursor mirror: `.cursor/rules/wawona-staticcpu-shm-tip.mdc`.
