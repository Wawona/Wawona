---
name: wawona-waypipe-peer
description: >-
  Planned Rust waypipe peer: stock wire on the far side, Wawona local
  endpoint only. Receive via Machines, send via Swinging Bridge. Open before
  adding waypipe patches.
---

# Waypipe peer (planned)

Rule: `docs/agent-rules/wawona-waypipe-peer.md`.

Local Wawona endpoint. Remote keeps upstream waypipe C or waypipe-rs.
No new patches as the permanent path. No `/dev/dri`. SHM default.

Receive: Machines Waypipe session, user-friendly pick app/desktop.
Send: Swinging Bridge (planned). Not Desktop/LockScreen.

Until green against stock waypipe, stay on `wwn-waypipe`.
