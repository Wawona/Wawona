# Wayland Protocol Compatibility Policy

Wawona should generally implement the **newest stable version** of each Wayland
protocol that is practical to support.

For protocols that use Wayland's normal interface versioning mechanism, Wawona
should expose the highest supported version and allow clients to **bind to an
older version when required**. We should not maintain separate implementations
of the same interface solely to support older clients.

When a protocol revision uses a **different interface name** (for example,
`zwp_text_input_v1` and `zwp_text_input_v3`), treat these as distinct protocols.
Multiple interface names may be implemented when there is a meaningful
compatibility reason or when applications in the ecosystem still depend on the
older interface.

## Guidelines

* Prefer the newest stable protocol version available.
* Use Wayland's built-in version negotiation for backwards compatibility.
* Avoid duplicate implementations of the same interface revision.
* Support older, separately named protocol interfaces only when there is a
  demonstrated compatibility need.
* Do not add legacy protocol support preemptively without a concrete client or
  ecosystem requirement.
* When dropping an older protocol interface, document the compatibility impact
  and rationale.

The goal is to keep Wawona's protocol implementation **modern, maintainable, and
interoperable** without accumulating unnecessary legacy code.

## Protocol addition / change checklist

Use this on every PR that adds, bumps, or removes a Wayland global or
handler:

1. **Newest stable first.** Is this the highest practical stable version for
   this interface family?
2. **Negotiation, not forks.** If an older client must work, can it bind a lower
   version of the same interface instead of a parallel implementation?
3. **Named interface justification.** If adding a second interface name (v1 vs
   v3 style), cite the concrete client, toolkit, or ecosystem need.
4. **No speculative legacy.** Do not land an older named interface "just in
   case."
5. **Status docs.** Refresh `docs/protocol-status.md` via
   `scripts/gen-protocol-status.sh` (or the cargo test that generates it). Update
   `docs/compliance/wayland-protocol-conformance-matrix.md` when behavior gates
   change.
6. **Removals.** If removing an older named interface, note which clients break
   and why the drop is acceptable.

## Related

* Agent / Cursor rule: `wawona-wayland-protocol-compat`
  (`docs/agent-rules/wawona-wayland-protocol-compat.md`)
* Live advertisement table: [`protocol-status.md`](./protocol-status.md)
* Conformance behaviors: [`compliance/wayland-protocol-conformance-matrix.md`](./compliance/wayland-protocol-conformance-matrix.md)
* Contributor entry: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
