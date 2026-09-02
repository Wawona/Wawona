# vphone LLDB (system-wide userspace)

Indexed mirror of `.cursor/rules/wawona-vphone-lldb.mdc`.

1. `packages status` → `debugserver: true`
2. `packages debug attach <pid|bundle|name>`
3. SSH `-L` forward → **user-lldb** `connect://127.0.0.1:<local>`

Deny-list: `watchdogd`, `IOWatchdog`. Companion: wwn-mcp → agent-device → lldb.
