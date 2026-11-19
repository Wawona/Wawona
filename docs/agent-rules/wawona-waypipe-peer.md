# Wawona waypipe peer (planned)

Not implemented in this change. Do not add another Linux-shaped patch to
`wwn-waypipe` as the long-term path.

## Goal

A Rust local endpoint that speaks stock waypipe wire (legacy C waypipe and
waypipe-rs). The far host keeps upstream waypipe. Users do not install a
Wawona fork to receive an app or a desktop.

## Paths

| Direction | Product | Notes |
|-----------|---------|-------|
| Receive | Machines remote / Waypipe session | Pick an app or desktop. SSH, compression, GPU fallback stay behind that choice. Advanced fields stay in Settings. |
| Send | Wawona Swinging Bridge | Cocoa / UIKit / Android apps become Wayland clients and send. Planned. Not Desktop/LockScreen. |

## Placement

- Until the peer talks to stock waypipe end-to-end, stay on the `wwn-waypipe`
  line so Machines receive is not blocked on Swinging Bridge.
- Once wire-compatible, the protocol crate may live with
  `Wawona-Swinging-Bridge`.
- No new Wayland protocol. No `/dev/dri`. SHM everywhere. GPU buffers only
  where iland already has them.
- Compatibility is a version matrix plus interop tests, not a day-one claim
  for every historical waypipe build.

## Hard rejects

- Requiring a Wawona-patched waypipe on the remote host for receive
- Patching waypipe as the permanent ALL_TARGETS strategy
- Conflating Swinging Bridge send with Desktop Replacement
- Calling wasm or containers a waypipe substitute

Related: `docs/2026-waypipe.md`, `docs/swinging-bridge.md`,
`wawona-swinging-bridge`, `wawona-guest-wayland-iland`.
