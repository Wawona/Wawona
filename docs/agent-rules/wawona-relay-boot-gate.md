# Relay boot gate (P3)

Machines kinds `virtual_machine` and `container` stay **planned** in Exact and
product UI until this gate is green.

## Done when

1. Mode A: StaticCpu / store runtime boots a **NixOS prebuilt** far enough for
   waypipe → Wawona Wayland → iland present (SHM first).
2. Guest GUI is Wayland into iland only (`wawona-guest-wayland-iland`).
3. Mode B iOS: `IosHv` only in tipa/Sileo when probe supports; never store.
4. macOS Container kind may use Apple Containerization; VM stays Relay.
5. Tier 3 Verification report obligations for VM memory/MMU stay named.

Until (1) is green: no Start-success theater for VM/Container. Copy stays
“coming soon” / “planned.”

Related: #31, Relay HV milestone, `wawona-staticcpu-shm-tip`,
`wawona-linux-vms-relay-runtime`.
