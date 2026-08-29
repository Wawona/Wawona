# Security and Spawn Policy

**Non-negotiable rules** for App Store-compliant local shell execution in Wawona. Any PR touching spawn, rootfs, or download code must cite this document.

---

## Threat model

| Threat | Description |
|--------|-------------|
| **T1 Post-review native code** | Attacker or user downloads Mach-O and executes |
| **T2 Path injection** | Malicious `PATH` or shell string points outside bundle |
| **T3 Host binary execution** | Spawning `/usr/bin/*` or jailbreak paths |
| **T4 Writable bundle tampering** | Modified binaries inside `.app` after install |
| **T5 Data exfiltration** | Shell reads outside container without user action |

We mitigate T1-T4 in code. T5 is sandbox + user consent for file picker / share.

---

## Allowlist: executable paths

Only these prefixes are valid for `wwn_pty_spawn_shell()`:

1. `$WAWONA_ROOTFS/usr/bin/` where `WAWONA_ROOTFS` is:
   - `Bundle/Resources/wawona-rootfs`, or
   - `Application Support/wawona-rootfs` (writable copy)
2. Explicit allowlist file (future): `Resources/wawona-rootfs/usr/bin/.wawona-allow` listing basenames

### Validation algorithm (normative)

```
function is_allowed(shell_path):
  rootfs = getenv("WAWONA_ROOTFS")
  if rootfs is empty: return REJECT
  canonical = realpath(shell_path)
  if not canonical.startswith(realpath(rootfs) + "/usr/bin/"): return REJECT
  if not file_exists(canonical): return REJECT
  if not is_regular_file(canonical): return REJECT
  return ALLOW
```

Reject: `..` traversal, symlinks escaping rootfs (use `realpath` + prefix check), `/tmp`, `file://`, `http://`.

---

## Forbidden operations

| Operation | Reason |
|-----------|--------|
| `exec*` on downloaded files | T1 |
| `dlopen(userPath)` | T1 |
| `posix_spawn` with `/bin/sh`, `/usr/bin/env` | T3 |
| Trusting `PATH` from host environment | T2 |
| Trusting `SHELL` from user SSH config for **local** spawn | T2 |
| Writing new Mach-O to Application Support and executing | T1 |
| Disabling sandbox entitlements for shell | Compliance |

---

## Environment sanitization

Before spawn, child environment is **constructed**, not inherited wholesale:

| Variable | Source |
|----------|--------|
| `HOME`, `ZDOTDIR`, `PATH`, `TERM`, `WAWONA_*` | Wawona-set only |
| `WAYLAND_*`, `XDG_RUNTIME_DIR` | Compositor layer (existing) |
| `DYLD_*`, `LD_*` | **Strip**. Do not pass |
| `SSH_*` | Not needed for local shell |

---

## Writable rootfs copy

Application Support copy exists so zsh can write history. **Executables in writable copy:**

- **Option A (preferred):** Executables remain read-only in bundle; only `home/` writable under Application Support
- **Option B:** Copy rootfs but mark `usr/bin` read-only with `chmod` after extract

Do not allow user replace of `usr/bin/zsh` without invalidating allowlist (checksum optional Phase 3).

---

## Relationship to Weston compositor `fork()` stub

`compositor-apple-mobile.nix` defines `fork()` as `-1` to prevent Weston from launching subprocess clients on mobile. **Shell spawn is unrelated:**

- Compositor stub → blocks **Weston compositor** child processes
- `wwn_pty` → **terminal client** spawns shell inside same app

Do not remove compositor stub to "fix" shell.

---

## Relationship to waypipe / SSH

Remote commands over SSH are **store-safe-remote**. They execute on the **remote host**, not via `wwn_pty`. Existing guards on waypipe download paths remain.

Local and remote paths must not share spawn functions.

---

## Session teardown

On `stopActiveIOSBundledClient` / session close:

1. Send SIGHUP to shell process group (if supported)
2. `wwn_pty_reap`. Waitpid, close master fd
3. Clear `WAWONA_SHELL` from env if reused for next session

Prevents zombie shells and fd leaks (jetsam risk).

---

## Audit checklist (per PR)

- [ ] New exec/spawn call site reviewed against this doc
- [ ] No user-controlled string reaches `posix_spawn` path argument without validation
- [ ] Unit test for path rejection (`/bin/zsh`, `../../../foo`)
- [ ] policy-traceability.md updated if new capability
- [ ] App Review notes updated if user-visible behavior changes

---

## Incident response

If App Review or security research reports arbitrary execution:

1. Capture spawn log + rejected path
2. Verify allowlist logic
3. Patch fail-closed; submit expedited review with [APP-REVIEW-NOTES.md](APP-REVIEW-NOTES.md) diff
