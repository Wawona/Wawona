# vphone LLDB (system-wide userspace)

Indexed mirror of `.cursor/rules/wawona-vphone-lldb.mdc`.

1. `agent-device packages debug attach <pid|bundle-id>` on vphone.
2. Keep the printed SSH `-L` forward alive.
3. **user-lldb** MCP: connect to `connect://127.0.0.1:<localPort>`.

Deny-list: `watchdogd`, `IOWatchdog`. Companion order: wwn-mcp → agent-device → lldb.
