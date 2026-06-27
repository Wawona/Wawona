# TestFlight Checklist — Local Shell (iOS / iPadOS)

Use before external TestFlight or App Review submission. Record **build attr**, **device**, **date**, **pass/fail** in PR or release notes.

Build attrs (target):

```bash
nix build .#wawona-ios-backend
nix build .#weston-ios
nix build .#zsh-ios          # Phase 2+
nix build .#wawona-rootfs-ios # Phase 2+
```

---

## A. Install and rootfs

- [ ] App installs on physical iPhone (not sim-only)
- [ ] App installs on physical iPad
- [ ] First launch: `WWNRootfsManager` copies rootfs without crash
- [ ] Second launch: no duplicate copy / version check works
- [ ] `Application Support/wawona-rootfs/home` writable
- [ ] Bundle `Resources/wawona-rootfs` unchanged after install

---

## B. Terminal UI (Phase 1+)

- [ ] Native profile: **weston-terminal** opens window
- [ ] Nested Weston: launcher → terminal icon opens window
- [ ] Scrollback works (mouse wheel / touch scroll)
- [ ] Window resize updates terminal rows/cols
- [ ] OSC title / cwd updates (if enabled)
- [ ] Colors and cairo rendering correct (no tint regression)
- [ ] Keyboard: `echo`, arrows, backspace in terminal UI (before shell: local echo test if any)

---

## C. Local zsh (Phase 2+)

- [ ] Prompt appears without manual refresh
- [ ] `echo hello` → `hello`
- [ ] `pwd` → under app container
- [ ] `cd` / `ls` (bundled ls if shipped)
- [ ] `.zsh_history` created after commands
- [ ] Ctrl-C interrupts running command (if supported)
- [ ] Terminal resize → `stty size` reflects new geometry
- [ ] Spawn rejection: debug attempt `/bin/sh` fails closed (unit test or internal flag)

---

## D. Session lifecycle

- [ ] Stop session / disconnect → shell reaped (no orphan in Instruments)
- [ ] Relaunch terminal → new shell, no stale fd
- [ ] Background app → foreground: terminal still usable or clean reconnect
- [ ] Low memory warning: document behavior (jetsam acceptable?)

---

## E. Compliance spot checks

- [ ] Airplane mode: local shell still works
- [ ] No network required for local shell
- [ ] grep logs: no `exec` of paths outside rootfs
- [ ] Settings toggle (if present) disables spawn when off
- [ ] Store-safe profile: virtual pointer global not advertised (existing CI script)

---

## F. Regression (existing mobile)

- [ ] `weston-simple-shm` still renders
- [ ] `weston-flower` still renders
- [ ] Nested Weston desktop shell + pointer hover
- [ ] Keyboard keysym test (`KEY_A` → correct symbol)
- [ ] waypipe SSH session (optional parallel path)

---

## G. Logs to attach on failure

```text
Wawona app log (PTY, WESTON, BRIDGE tags)
Phase 0 spike output if spawn fails
Instruments trace if jetsam
ios-local-shell-spike.md filled sections
```

Log tags: `PTY`, `WESTON`, `BRIDGE`, `FFI`, `wwn mobile client`

---

## Sign-off

| Role | Name | Date | Build |
|------|------|------|-------|
| Engineering | | | |
| QA | | | |
| PM (compliance) | | | |
