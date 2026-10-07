# Wayland protocol compatibility

Prefer the **newest stable** version of each Wayland protocol that is practical
to support. Rely on Wayland **version negotiation** for backward compatibility.
Do not maintain duplicate implementations of the **same interface** solely for
older clients.

## Hard rules

1. Advertise / implement the highest supported version of an interface. Clients
   bind an older version when they need one.
2. Do **not** fork a second copy of the same interface revision for "legacy".
3. Separately **named** interfaces (`zwp_text_input_v1` vs `…_v3`) are distinct
   protocols. Implement an older named interface only with a **demonstrated**
   client or ecosystem need. Never add legacy names preemptively.
4. Dropping an older named interface requires documenting compatibility impact.

## Review checklist (protocol PRs)

- [ ] Newest practical stable version?
- [ ] Back-compat via bind version, not a parallel same-interface impl?
- [ ] Extra interface name justified by a concrete client/app?
- [ ] `docs/protocol-status.md` / matrix updated (`scripts/gen-protocol-status.sh`)?
- [ ] Drop rationale recorded if removing a named interface?

Canonical prose: [`../PROTOCOLS.md`](../PROTOCOLS.md).
Cursor rule: `wawona-wayland-protocol-compat`.
See also [`../protocol-status.md`](../protocol-status.md),
[`../compliance/wayland-protocol-conformance-matrix.md`](../compliance/wayland-protocol-conformance-matrix.md).
