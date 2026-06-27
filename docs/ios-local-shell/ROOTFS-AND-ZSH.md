# Rootfs and ZSH Packaging (Nix)

How Wawona builds, bundles, and installs the **App Store–compliant zsh userland** for iOS/iPadOS.

---

## Package graph (target)

```
zsh-ios (dependencies/libs/zsh/ios.nix)
    ↓
ios-rootfs (dependencies/wawona/ios-rootfs.nix)
    ↓
wawona-ios-backend / xcodegen (copy into Wawona.app/Resources)
    ↓
WWNRootfsManager (first launch → Application Support)
    ↓
wwn_pty_spawn_shell(WAWONA_ROOTFS/usr/bin/zsh)
```

---

## `zsh-ios` (`dependencies/libs/zsh/ios.nix`)

### Requirements

| Requirement | Detail |
|-------------|--------|
| Version | zsh 5.9+ (match nixpkgs baseline where possible) |
| Triple | `aarch64-apple-ios`, sim variants via `simulator ? true` |
| Linking | Static or mostly-static; no host `/usr/lib` deps |
| Features | Disable setuid, `/etc` assumptions, NIS, gdbm if problematic |
| Size budget | Target <25 MB stripped (adjust after first build) |

### Configure flags (starting point — tune after first compile)

```bash
./configure \
  --host=aarch64-apple-ios \
  --enable-static \
  --disable-dependency-tracking \
  --disable-nls \
  --disable-gdbm \
  --disable-pcre \
  # … add as failures appear
```

### Install outputs

| Path in `$out` | Purpose |
|----------------|---------|
| `bin/zsh` | Spawn target |
| `share/zsh/` | Functions, completion (minimal subset) |
| `etc/zshrc` | Template copied into rootfs |

### Flake outputs

```nix
packages.aarch64-darwin.zsh-ios
packages.aarch64-darwin.zsh-ios-sim
```

---

## `ios-rootfs.nix` (`dependencies/wawona/ios-rootfs.nix`)

Aggregates a **prefix tree** suitable for `WAWONA_ROOTFS`:

```
rootfs/
  usr/bin/zsh          ← from zsh-ios
  usr/share/zsh/...    ← trimmed share
  etc/zsh/zshrc.template
  README.txt           ← "Bundled userland — do not modify in bundle"
```

### Future binaries (Phase 4)

| Tool | Package | Priority |
|------|---------|----------|
| `ls` | coreutils subset | Medium |
| `grep` | grep-ios | Medium |
| `vim` | optional | Low |

Each addition requires [SECURITY-SPAWN-POLICY.md](SECURITY-SPAWN-POLICY.md) review and license entry in [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md).

---

## `.zshrc` template (bundled)

Goals:

- OSC 7 cwd reporting for Weston terminal title (match macOS patch behavior)
- Reasonable prompt without external fonts
- History to `$HOME/.zsh_history`
- No curl-to-bash, no plugin managers, no compinit paths outside rootfs

```zsh
# Template — installed to $HOME/.zshrc on first launch
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=5000
autoload -Uz add-zsh-hook

# OSC 7: report cwd to terminal (weston-terminal title patch)
wwn-report-cwd() {
  print -Pn "\e]7;file://${PWD}\a"
}
add-zsh-hook chpwd wwn-report-cwd
wwn-report-cwd

PS1='%F{green}%n@%m%f:%F{blue}%~%f$ '
```

---

## Xcode / xcodegen integration

In `dependencies/generators/xcodegen.nix`:

1. Add `wawona-rootfs` as build input to iOS app target
2. Copy phase: `"${rootfs}/rootfs" → Wawona.app/Resources/wawona-rootfs`
3. Code sign as resources (same as fonts, xkb, weston assets)

Do **not** mark rootfs binary as executable in a way that triggers AMFI outside spawn path — normal bundle resources are fine.

---

## `WWNRootfsManager` (planned ObjC)

| Responsibility | Detail |
|----------------|--------|
| `+sharedManager` | Singleton |
| `-ensureRootfsInstalled` | Copy Resources → Application Support if missing or version bump |
| `-rootfsPath` | `…/Application Support/wawona-rootfs` |
| `-homePath` | `…/home` writable |
| `-shellPath` | `rootfs/usr/bin/zsh` |
| `-rootfsVersion` | Compare `Resources/wawona-rootfs/VERSION` for upgrades |

Version bump policy: merge user `home/` on upgrade except replace `.zshrc` if user hasn't modified (TBD — document in implementation PR).

---

## Environment wiring

Set in `WWNWaypipeRunner.m` before launching `weston_terminal_main` or nested Weston:

```objc
NSString *rootfs = [[WWNRootfsManager sharedManager] rootfsPath];
NSString *home = [[WWNRootfsManager sharedManager] homePath];
setenv("WAWONA_ROOTFS", rootfs.UTF8String, 1);
setenv("HOME", home.UTF8String, 1);
setenv("ZDOTDIR", home.UTF8String, 1);
setenv("WAWONA_SHELL", [rootfs stringByAppendingPathComponent:@"usr/bin/zsh"].UTF8String, 1);
setenv("PATH", [rootfs stringByAppendingPathComponent:@"usr/bin"].UTF8String, 1);
setenv("TERM", "xterm-256color", 1);
```

---

## Registry

Add to `dependencies/toolchains/common/registry.nix`:

```nix
zsh = { ios = import ../../libs/zsh/ios.nix; };
wawona-pty = { ios = import ../../libs/wawona-pty/ios.nix; };
wawona-rootfs = { ios = import ../../wawona/ios-rootfs.nix; };
```

---

## CI verification

```bash
nix build .#zsh-ios --no-link
nix build .#wawona-rootfs-ios --no-link
# Optional: otool -L on zsh must show no disallowed dylibs
```

Add rows to [everywhere-matrix.md](../testing/everywhere-matrix.md).

---

## Size and memory monitoring

Record in Phase 0/2 spike:

| Metric | Tool |
|--------|------|
| `zsh` binary size | `ls -la`, App Store Connect upload size |
| Rootfs total | `du -sh wawona-rootfs` |
| Idle RSS with shell | Instruments Allocations |
| Peak RSS during completion | zsh loads compinit — measure trimmed share |

If zsh exceeds budget: ship `dash` in rootfs for Phase 2.1, zsh opt-in — **document compliance equivalence** (still bundled binary).
