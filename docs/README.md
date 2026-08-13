# Wawona Documentation

Living map of `docs/`. Facts that go to [wawona.io](https://wawona.io/docs/)
must cite the **canonical** files below, not audits or archives.

**Public subset note:** only the files in the first table are safe to paraphrase
onto the site. Everything else stays in GitHub.

---

## Canonical (cite from wawona.io)

| Document | Role |
|----------|------|
| [wawona-mission-and-architecture.md](wawona-mission-and-architecture.md) | Mission, delivery paths, Mode A/B, decorations |
| [2026-SOURCE-OF-TRUTH.md](2026-SOURCE-OF-TRUTH.md) | Platform scope, X11 story, settings inventory |
| [protocol-status.md](protocol-status.md) | Generated advertised globals (never hand-count) |
| [settings.md](settings.md) | Preference keys and Machines overrides |
| [usage.md](usage.md) | Nested Weston/Niri, bundled clients |
| [machine-profiles.md](machine-profiles.md) | Machine kinds: native, ssh_waypipe, ssh_terminal, VM, container |
| [iland-mode-a-b-desktop.md](iland-mode-a-b-desktop.md) | Mode A vs SIP Mode B; Android anowaW |
| [iland-graphics-stack.md](iland-graphics-stack.md) | GPU/SHM, no Turnip/KGSL |
| [2026-waypipe.md](2026-waypipe.md) | SSH: OpenSSH / libssh2 / OpenSSH portable |
| [ios-local-shell/README.md](ios-local-shell/README.md) | Bundled zsh (not StoreKit apt) |
| [compilation.md](compilation.md) | Flake product attributes |
| [2026-nix-build-system.md](2026-nix-build-system.md) | Nix layers; flake inputs |
| [wwn-repo-dag.md](wwn-repo-dag.md) | L0–L4 acyclic flake DAG |
| [flakehub-registry.md](flakehub-registry.md) | Rolling FlakeHub URLs |
| [2026-wwn-porting-convention.md](2026-wwn-porting-convention.md) | Porting `wwn-*` |
| [ci.md](ci.md) | `development` vs `master`; Gate vs Ship (no secrets) |
| [debugging.md](debugging.md) | agent-device + opt-in LLDB |
| [2026-platform-delivery-matrix.md](2026-platform-delivery-matrix.md) | native / nested / waypipe per target |
| [2026-SOURCE-LAYOUT-RULES.md](2026-SOURCE-LAYOUT-RULES.md) | `src/core` vs `Sources/WawonaUI` |

---

## On-device shell

| Document | Description |
|----------|-------------|
| [ios-local-shell/README.md](ios-local-shell/README.md) | Hub |
| [ios-local-shell/WATCHOS-SCOPE.md](ios-local-shell/WATCHOS-SCOPE.md) | v2: constrained zsh on watchOS (not excluded) |
| [ios-local-shell/ARCHITECTURE.md](ios-local-shell/ARCHITECTURE.md) | Process model |
| [ios-local-shell/APP-STORE-COMPLIANCE.md](ios-local-shell/APP-STORE-COMPLIANCE.md) | Guideline mapping |

`wwn-apt` is not a Wawona flake input. Do not document Debian/`apt install` as shipping.

---

## Keep internal (not the public site)

| Path | Why |
|------|-----|
| [issues/](issues/) | Open work |
| [testing/](testing/) | Harness internals |
| [maintainers/secrets.md](maintainers/secrets.md) | Release secrets |
| [compliance/](compliance/) | Cite only [smithay-adoption-decision.md](compliance/smithay-adoption-decision.md) |
| [agent-rules/](agent-rules/) | Mirrors of `.cursor/rules/` |
| [drivers-how-to/](drivers-how-to/README.md) | Graphics how-to |
| [2026-ARCHITECTURE-STRUCTURE.md](2026-ARCHITECTURE-STRUCTURE.md) | Pointer stub only |
| [goals.md](goals.md) | Pointer stub; mission is canonical |

---

## Legacy (superseded; do not copy to wawona.io)

| Path | Notes |
|------|-------|
| [legacy/](legacy/) | 2025 archive, chat dumps, frozen Android audits |

---

## Agent / Cursor rules

| Document | Description |
|----------|-------------|
| [agent-rules/](agent-rules/) | Tracked mirrors (`/.cursor/` is gitignored) |
| [../AGENTS.md](../AGENTS.md) | Agent entrypoint |
