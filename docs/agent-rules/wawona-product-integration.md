# This repo: `Wawona` (L4 product)

Integrate lower layers. Enforce the product map in UI, gates, packaging, and docs.

## Gates (must stay aligned)

- `PlatformCapabilities.swingingBridgeGate` — macOS planned; iOS store **forbidden**
- Desktop/LockScreen — planned macOS/Android; forbidden App Store Apple-mobile
- VM/container kinds — planned where allowed; **forbidden** tvOS/watchOS/visionOS
- Wasm/`wpm` — Mode A path only inside store builds

## Shipping firewall

| In App Store / Play IPA/AAB | Outside store |
|---|---|
| Mode A only | Mode B IPA / `.deb` / desktop-host |
| `repo.wawona.io/wasm` OK | `/jailbreak/` never from store app |
| No jailbreak/JIT pitch in UI strings | Website + repo may document Mode B |

## Naming

- Product: **Wawona Swinging Bridge** (formerly anowaW).
- Flake: `wwn-swinging-bridge`. Legacy `anowaw_*` ABI OK until renamed.
- Do not call Swinging Bridge Desktop or LockScreen.

Canonical docs under `docs/`; agent rules under `docs/agent-rules/` and
`.cursor/rules/`. See `wawona-product-map`.
