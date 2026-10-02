# Static CPU / mobile guest completion plan

Engineering judgment checkpoint for Wawona Relay VM support. Not measured
coverage. Do not claim 100% VM support.

## Immediate critical path

1. Reliable boot → required systemd target on **4 KiB and 16 KiB**
2. Authenticated guest frame (vsock + host waypipe)
3. Persistent machine lifecycle (create/save/reopen/boot/stop/grow/restart)
4. Exact signed-device verification

## Current measured boot evidence (host Mac probes)

Prior 1200s priority-image probes (exit 0, liveness only):

- Both complete coldplug, reach Basic System, start serial getty on `hvc0`
  and the real Wayland session.
- Both send real 16-byte waypipe vsock payloads to host port 1024.
- Neither proves required Multi-User target.
- Optional OCI mounts fail when the diagnostic supplies no OCI share
  (expected with `nofail`).
- 16 KiB additionally reports failed `session-1.scope` /
  `session-2.scope`.
- No authenticated readiness or imported guest frame.

## Guest fixes in this branch

Evidence-driven guest changes (not acceptance weakening):

1. **`users.users.wawona.linger = true`** + fixed `uid = 1000` so
   `user@1000` / `user-runtime-dir@1000` create `/run/user/1000` before
   `wawona-session`. Removes the race where the service `mkdir`d the
   runtime dir while getty autologin owned session scopes (16 KiB).
2. **`wawona-session` / `wawona-container`** order after user runtime;
   require the runtime directory to exist; `Restart=on-failure` with start
   limits so restart loops cannot hide Multi-User settling.
3. **`systemd-udev-trigger`** ExecStart drop-in:
   `--type=all --action=add --prioritized-subsystem=block,tty,net,input,module,tpmrm`
   (upstream deadlines/dependencies retained).
4. **Stable init seed** in `guest-artifacts.nix`:
   - `/nix/var/nix/profiles/system-1-link` → toplevel
   - `system` → `system-1-link`
   - `/init` → `/nix/var/nix/profiles/system/init`
   - cmdline `init=/init` so existing disks are not pinned to a newer
     bundled store path for `/init`.

## Still open

- Prove Multi-User with console traces on both page sizes after rebuild.
- Authenticated vsock readiness + real guest frame import.
- Legacy disk migration preserving data when adopting `init=/init`.
- Bundled kernel/initrd compatibility with future guest generations.
- Nix editor guest apply / flake.lock / rebuild / rollback.
- OCI-in-VM full lifecycle, devices, signed-device matrix.

## Verification notes

- Diagnostic smoke exit 0 means **liveness only**.
- Do not attribute improvement solely to udev priority order when probe
  duration also changed (600s → 1200s).
- Formal gate: `scripts/verified-cargo.sh` (Kani/Verus). Prefer
  `scripts/verified-runner.sh` once a proof stamp exists.
