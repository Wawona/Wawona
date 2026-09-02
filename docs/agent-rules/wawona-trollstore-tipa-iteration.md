# TrollStore tipa iteration (vphone)

Indexed mirror of `.cursor/rules/wawona-trollstore-tipa-iteration.mdc`.

**Hard:** `CFBundleShortVersionString` (marketing) ≠ `CFBundleVersion` (build).
Bump BUILD every tipa you want to replace on guest.

```bash
./scripts/build-modeb-demo-tipa.sh          # auto-increments build
agent-device packages tipa install ./App.tipa --device "vphone wawona-jb"
agent-device packages tipa info <bundle>      # guest build must match tipa
agent-device packages tipa open-jit <bundle>
```

Same-build install is refused. Helper rc 3 = ESRCH (no live PID). Sign with ldid
only. Never ASC/TestFlight for tipa.
