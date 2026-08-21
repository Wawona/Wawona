# 2026-08-21: sticky WindowServer `unload -w` → login panic

## Panic (25F80)

```
panic: userspace watchdog timeout: no successful checkins from WindowServer
  (0 induced crashes) in 120 seconds
WindowServer appears to not exist in launchd
Panicked task: watchdogd
```

Operator had to **enable SIP** to get a bootable login after Mode B kmscube
own-display testing.

## What we did

Manual Mode B kmscube script (and the product helper `stop_window_server`)
stopped Apple WindowServer with:

```sh
launchctl bootout system/com.apple.WindowServer
launchctl disable system/com.apple.WindowServer
launchctl unload -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist
```

`disable` / `unload -w` are **persistent**. The hold script was interrupted
before `restore_aqua` / `enable` + `load -w` ran. Next login: no WindowServer
in launchd. Path B / userspace watchdog still expected WS checkins → panic at
~120s.

## Same session: present never worked

`/Library/Application Support/Wawona/modeb-kmscube.log`:

```
[framebufferd] bootstrap_register com.wayland-mac.framebufferd: unknown error code
[inputd] bootstrap_register com.wayland-mac.inputd: unknown error code
```

No `CoreDisplay initialised`, no `presentSurface n=`. Blank panel was empty
Mach registration, not a successful cube present.

## Hard rules (product)

1. **Never** `launchctl disable` or `unload -w` on `com.apple.WindowServer`.
   Session stop = `bootout` + TERM only.
2. Restore = `enable` + `load -w` / `bootstrap` (and `kickstart -k` on WS only
   if pid missing). Never leave disable sticky.
3. Do not Classic / own-display while SIP is enabled; re-arm Path B coverage
   after any SIP change / reboot before Take Over.
4. Fail closed if `bootstrap_register` for framebufferd fails: restore Aqua
   immediately (do not hold a blank WS-less session for tens of seconds).

## Fix

`WWNDesktopReplacementController.m` `stop_window_server`: bootout + kill only
(no disable / unload -w). Incident logged here.

## Aftermath on this host

After SIP-enabled recovery boot: WindowServer was running again; not listed in
`disabled.plist` as disabled. Path B `claim-ok` may still be sticky; re-check
`--doctor` after operator returns SIP to fully disabled for Mode B work.
