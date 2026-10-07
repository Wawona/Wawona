# Contributing to Wawona

## Wayland protocols

Protocol work follows the **Wayland Protocol Compatibility Policy**:

> Prefer the newest stable version of a Wayland protocol, and rely on Wayland
> version negotiation for backward compatibility. Implement older protocol
> revisions separately only when they have a distinct interface name or are
> required for real-world client compatibility. Avoid maintaining duplicate
> implementations of the same interface revision solely for legacy clients.

Full policy, guidelines, and the **protocol PR checklist**:
[`docs/PROTOCOLS.md`](./docs/PROTOCOLS.md).

Agent / Cursor mirror: `docs/agent-rules/wawona-wayland-protocol-compat.md`
(rule id `wawona-wayland-protocol-compat`).

Before opening a protocol PR, run through that checklist and keep
`docs/protocol-status.md` in sync
(`scripts/gen-protocol-status.sh`).

## Agents and IDE rules

AI agents should load `AGENTS.md` and the rules under `docs/agent-rules/` /
workspace `.cursor/rules/`. For Wayland, Smithay, and platform facts, prefer
**wwn-mcp** over training priors (see `AGENTS.md`).
