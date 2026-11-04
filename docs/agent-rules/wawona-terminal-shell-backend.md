# Wawona Terminal shell backend (system shell vs Wawona PTY)

Who runs the shell behind a Wawona Terminal tab depends on the product
mode, not on the renderer. Ghostty paints both. Never mix them.

## Matrix

| Product | Backend | Shell |
|---|---|---|
| macOS (every macOS artifact) | **System shell** | user's login shell (`getpwuid(getuid())->pw_shell`, else `/bin/zsh`), `-l`, real `openpty` + spawn |
| Linux | **System shell** | user's login shell, `-l`, real pty |
| iOS / iPadOS Mode B (TrollStore `.tipa`, Sileo `.deb`) | **System shell** | jailbreak / bootstrap login shell (`/var/jb/...` rootless, `/` rootful), real pty + spawn |
| Android Mode B (root / privileged, outside Play) | **System shell** | device shell (Termux or root shell), real pty |
| iOS / iPadOS / tvOS / watchOS / visionOS Mode A (App Store / TestFlight / store-shaped) | **Wawona PTY shell** | in-process `wawona_zsh_main` on a pthread + `wwn_pty`, uutils dispatch, `wawona-rootfs` HOME. No fork / exec / posix_spawn |
| Android Mode A (Play, store-shaped) | **Wawona PTY shell** | bundled zsh + `wwn_pty`, Wawona rootfs |

## Rules

1. Rust owns the decision (`domain::terminal_shell`, UniFFI). Swift and Kotlin
   call it. No hardcoded `/bin/zsh` or `/usr/bin/zsh` choice in host code.
2. The Rust Terminal crate (libghostty-rs) is the grid on both backends.
   - System shell: Rust opens a real pty and spawns the resolved login shell.
     Never a demo or placeholder command.
   - Wawona PTY: Rust attaches the session to `wwn_pty` and the in-process
     zsh. Nothing spawns a process in Mode A.
3. Mode A artifacts must not contain the system-shell spawn path. Store CI
   checks for it.
4. Mode B artifacts may still offer the Wawona PTY shell as a fallback when no
   system shell exists (for example TrollStore with no bootstrap). The
   resolver reports that fallback; hosts do not guess.
5. Relay consoles and SSH sessions are separate byte sources (external IO) on
   every target. They are not "the shell".

## Hard rejects

- Ghostty (or anything) spawning a shell in a Mode A Apple-mobile or Play build
- A system `/bin/zsh` on macOS replaced by the in-process Wawona zsh
- Shell choice decided in Swift / Kotlin
- A Terminal tab that runs a placeholder command instead of a real shell

Canonical: this file. Cursor mirrors: `.cursor/rules/wawona-terminal-shell-backend.mdc`
(Wawona and workspace). Related: `wawona-ghostty-host`, `wawona-ios-native-shell`,
`wawona-apple-mobile-mode-a-backends`, `wawona-mode-a-b`, `wawona-macos-no-appstore`.
