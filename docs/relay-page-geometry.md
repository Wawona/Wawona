# Relay page geometry (4 KiB / 16 KiB)

Canonical for host↔guest page translation in Wawona Relay.

## Product rule

One Relay VM backend. Two guest **kernels** (real `CONFIG_ARM64_16K_PAGES`
vs 4 KiB). Not two VM products.

Apple mobile hosts typically use **16 KiB** process pages. Linux builders often
use **4 KiB**. Relay maps either guest geometry onto the host arena via
`PageTranslate` (`Relay/crates/relay-vm/src/page_translate.rs`).

```text
Guest 4 KiB Image  ─┐
                    ├─► PageTranslate ─► host arena (host page rounded)
Guest 16 KiB Image ─┘
```

## Hard rejects

- Relabeling a 4 KiB Image as 16 KiB
- A second Machines kind or engine solely for page size
- Claiming page translation replaces a correctly built guest kernel

## Code

| Piece | Path |
|-------|------|
| `GuestPageSize` / `HostPageSize` | `Relay/crates/relay-core` |
| `PageTranslate` | `Relay/crates/relay-vm/src/page_translate.rs` |
| Arena allocate | `GuestMemory::allocate_on_host` |

## Related

Mode A benches (1A + 2A+2B): `Relay/docs/mode-a-bench.md`, live charts from
`bench-latest` on `github.com/Wawona/Relay`. Guest recipes:
`wawona-nixos-guest-4k` / `wawona-nixos-guest-16k`.
