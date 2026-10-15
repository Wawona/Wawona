---
name: wawona-staticcpu-shm-tip
description: >-
  Mode A StaticCpu SHM tip loop on iOS Simulator. waypipe BUFFER_DIFF order,
  wl_buffer.release, guest embed name, exclusive UDID, Metal present proof.
  Open when debugging held buffers, 64x625-only frames, or AUTH without 800x600.
---

# StaticCpu SHM tip (Mode A Simulator)

Authority: `Relay/docs/agentic-graph-staticcpu.md`,
`Relay/crates/relay-vm/src/shm_import.rs`, skill `wawona-ios-sim-runtime`,
rule `wawona-ios-app-entry`. Completely complete stays **0%** until store TF.

## Task graph (stop rule)

Prove in order. Do not rebuild guest for SHM while BUFFER_DIFF already arrives.

```text
exclusive UDID tip
  → lab-synth AUTO_START (guest embed name)
  → READY=1 + AUTH_OK=1
  → held=0 + imported frames
  → Mode A SHM present (prefer 800x600)
  → screenshot
```

N16 / STARDUST / store TF = human gate. Do not park SHM work on them.

## Exclusive tip ownership

| Do | Don't |
|----|-------|
| UDID `63A4C4D6…` for StaticCpu SHM when `9D70E2B7…` contested | Parallel `simctl install` on same UDID |
| `mkdir` lock `/tmp/wawona-sim-install.lock.d` | Ignore overwrite mid-boot |
| Per-UDID `XDG_RUNTIME_DIR` `/tmp/wawona_sim_<uid>_<udid8>` | Shared `/tmp/wawona_sim_<uid>/wayland-0` (bind fail) |
| Tip name `Wawona-smoke-tip.app` + poll checks `grep tip` | Claim green from stale host `/tmp/…/relay-shm.log` |

## Guest embed (lab-synth)

`labSynthesizeStaticCpuProfileIfGuestStaged` looks for Bundle resource
`wawona-nixos-guest-4k` (or `16k`), **not** `guest-4k`.

```bash
# After ditto tip app:
ditto /tmp/wawona-guest-4k-bak /tmp/Wawona-smoke-tip.app/wawona-nixos-guest-4k
chmod -R u+rwX /tmp/Wawona-smoke-tip.app
SIMCTL_CHILD_WWN_AUTO_START_MACHINE=static-smoke-n10b \
  xcrun simctl launch "$UDID" com.aspauldingcode.Wawona
```

Log must say `lab-synthesized static-smoke-n10b guest=4k`.
`no profile static-smoke-n10b` = wrong guest directory name or missing manifest.

## waypipe SHM order (hard-won 2026-10-15)

Live wire often:

```text
OPEN_FILE → BUFFER_DIFF → INJECT_RIDS → PROTOCOL (create_pool / create_buffer / attach / commit)
```

Not the textbook PROTOCOL-then-DIFF order.

| Symptom | Cause | Fix in `shm_import.rs` |
|---------|-------|------------------------|
| `all buffers are held by the server` | Import via `last_file` with empty `buffers` map; no `wl_buffer.release` | Skip import when `buffers.is_empty()`; flush replies after DIFF/FILL |
| Only **64x625**, never 800x600, AUTH dies | Early return after first surface; no release on last_file | Commit **all** surfaces; `release_all_buffers` on last_file path |
| Skip works, still held, no imports | DIFF before create_buffer; release never queued | Catch-up `import_guest_pixels` on `create_buffer`; release even if buffer id missing from map |
| AUTH + held=0 + attach buffer=N, **no** `create_buffer` log | Attach references id MiniCompositor never registered | Synthesize pool+buffer from `last_file` on attach |
| Dim heuristic **64x625** for 160000 bytes | `len % (64*4)==0` wins over square | Prefer 200x200 / near-square factors before 64xN |
| Black screenshot with `present 64x625` | Cursor-sized pool only; no 1.92MiB OPEN_FILE yet | Still a gap: decode unhandled PROTOCOL opcodes; do not claim 800x600 |

## Evidence commands

```bash
# Tip binary must contain current strings
strings …/Wawona | grep -E 'skip import|synthesize buffer|unhandled wl_shm'

# Guest
rg -a 'READY=1|AUTH_OK|buffers are held' "$CONSOLE"

# Host SHM
rg -a 'OPEN_FILE|skip import|synthesize|imported SHM|unhandled|flush replies' "$SHMLOG"

# Present
log show … | rg 'Mode A SHM present'
```

Pass for Metal face proof: `AUTH_OK` **and** `imported SHM frame: 800x600`
(or documented interim dim) **and** non-black Present screenshot.

## Hard rejects

❌ Treat host `/tmp/wawona_sim_503/relay-shm.log` as live tip evidence (stale / wrong UDID)  
❌ `guest-4k` directory name for lab-synth (must be `wawona-nixos-guest-4k`)  
❌ Import BUFFER_DIFF pixels before any `wl_buffer` exists (ghost frame, no release)  
❌ Claim shm-ui green from AUTH alone or from 64x625-only without calling out the gap  
❌ Guest rebuild to "fix" held while DIFF already arrives  
❌ Foreground `nix build` cancel that kills a live tip mid-AUTH  

## Where to edit

| Change | Path |
|--------|------|
| MiniCompositor / waypipe SHM | `Relay/crates/relay-vm/src/shm_import.rs` |
| Graph ticks | `Relay/docs/agentic-graph-staticcpu.md` |
| Lab-synth / AUTO_START | `Wawona/Sources/WawonaApple/Machines/MachineProfileStore.swift`, `SceneDelegate.swift` |
| Per-UDID runtime dir | `WWNPreferencesManager` preferredSharedRuntimeDir |

RAG: `wwn-mcp/knowledge/wawona/staticcpu-shm-tip.md`.
