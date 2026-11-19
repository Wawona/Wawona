# Relay boot gate (P3)

macOS Machines kinds `virtual_machine` and `container` are **available**
(Virtualization.framework + Apple Containerization). See
`docs/relay-runtime-map.md`.

iOS / Android / visionOS VM and container stay **planned** in Exact and product
UI until this gate is green for those hosts.

## Done when (mobile / non-macOS)

1. Mode A: StaticCpu / store runtime boots a **NixOS prebuilt** far enough for
   waypipe → Wawona Wayland → iland present (SHM first).
2. Guest GUI is Wayland into iland only (`wawona-guest-wayland-iland`).
3. Mode B iOS: `IosHv` only in tipa/Sileo when probe supports; never store.
4. Tier 3 Verification report obligations for VM memory/MMU stay named.

Until (1) is green on a host: that host keeps “planned.” macOS does not wait.

Related: #31, Relay HV milestone, `wawona-staticcpu-shm-tip`,
`wawona-linux-vms-relay-runtime`, `docs/relay-runtime-map.md`.
