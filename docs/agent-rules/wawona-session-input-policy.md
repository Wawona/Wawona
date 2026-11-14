# Session input policy (Rust)

Start and Focus resolve touch, host cursor, virtual pointer, and cursor grab
in Rust `domain::launch_resolve`. Hosts apply the JSON. They do not keep a
second Swift/Kotlin table for the common cases.

## API

- UniFFI: `launch_session_input_policy_json`
- C: `wawona_launch_session_input_policy`
- Swift: `WawonaDomainBridge.sessionInputPolicy(...)`

Nested-cursor-only helper remains: `launch_nested_cursor_policy_json` /
`nestedCursorPolicy`.

## Defaults

| Case | Touch | Host cursor | Virtual pointer | Grab |
|---|---|---|---|---|
| Nested compositor | Multi-Touch | hide | off | on |
| Normal client | override or Multi-Touch | show | Show Virtual Cursor pref | off |
| Limited touch (CarPlay / external) | Single Touch | (cursor rules) | (cursor rules) | off |
| Pointer remote (AirPlay / phone-as-remote) | Touchpad | (cursor rules) | (cursor rules) | on |

Settings → Touch Input Type and Show Virtual Cursor stay as **overrides**.
New users never pick Vulkan ICD or touch mode for common Starts.

## Surface class

Host passes `primary` | `limited_touch` | `pointer_remote` (or sets
`WWNPresentLimitedTouch` / `WWNPresentPointerRemote` for Active helpers).

## Related

`wawona-nested-compositor-cursor`, `wawona-agent-device-multitouch`,
`wawona-uniffi-domain`.
