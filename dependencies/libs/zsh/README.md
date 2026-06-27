# Wawona zsh (iOS fork)

Static, cross-compiled zsh for iPhone/iPad. Shipped as **`zsh.framework`** inside
`Wawona.app/Frameworks/` so AMFI treats the binary as nested executable code, not
a bundle resource.

## Build outputs

| Flake output | Contents |
|--------------|----------|
| `.#zsh-ios` | Raw `bin/zsh` + `share/zsh` (dev/tests) |
| `.#zsh-framework-ios` | `zsh.framework/` ready for Xcode embed |

## Fork choices (mobile / App Store)

Configured in `ios.nix`:

- **Static link** (`--enable-static`) — no dylibs to load at runtime
- **No NLS, gdbm, pcre, cap** — fewer deps and no plugin surface
- **No `/etc` zsh config** (`--disable-etcdir`) — config from `ZDOTDIR` only
- **No passwd/group** — `getpwuid` / `getpwnam` disabled; `USER=mobile` from env
- **termios** terminal driver — works with `wawona-pty` pipe fallback on iOS
- **termcap stub** — no ncurses dependency

Runtime data (`HOME`, history, `.zshrc`) lives under Application Support via
`WWNRootfsManager`; the framework stays read-only in the app bundle.

## Spawn policy

Only `…/Frameworks/zsh.framework/zsh` is allowlisted in `wawona-pty` on Apple
mobile. Signed at embed time with `com.apple.security.inherit`.
