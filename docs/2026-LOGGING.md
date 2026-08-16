# Wawona Logging Format

All logging must follow this format uniformly:

```
2026-01-18 15:02:42 [BRIDGE] Creating WawonaCore via direct C API
```

## Format

- **Date/timestamp**. `YYYY-MM-DD HH:MM:SS`
- **Component**. Inside `[brackets]` (e.g. `[BRIDGE]`, `[CORE]`, `[FFI]`)
- **Message**. Plain text
- **No emojis**