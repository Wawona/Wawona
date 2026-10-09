---
name: wawona-apple-swift
description: >-
  Mandatory Swift/SwiftUI skill gate for Wawona Apple compositor products.
  Use whenever editing or reviewing Sources/WawonaApple, Sources/WawonaUI,
  Sources/WawonaWatch, Darwin/, Apple Settings/Machines/Present SwiftUI,
  UniFFI Swift glue, or any macOS/iOS/iPadOS/tvOS/watchOS/visionOS host UI.
---

# Apple Swift / SwiftUI (mandatory)

Wawona's Apple compositor host is Rust policy plus Swift/SwiftUI glue. Do not
edit Apple UI from model priors alone.

## Before any Apple Swift / SwiftUI edit

Read these skills **in this order**, then edit:

1. **`swiftui-pro`** (Paul Hudson) at `~/.agents/skills/swiftui-pro/SKILL.md`
   (or `~/.cursor/skills/swiftui-pro`). Open matching `references/*.md` for the
   task (views, data, navigation, design, api).
2. **`swiftui-expert-skill`** (Antoine van der Lee) at
   `~/.agents/skills/swiftui-expert-skill/SKILL.md`. Open only the reference
   files needed (state, lists, sheets, liquid-glass, latest-apis, performance).
3. **Wawona product skills/rules** that always win on conflict:
   - `wawona-swiftui-backports` (iOS **13.0** floor; `WawonaBackport`)
   - `wawona-apple-swift-glue` (Rust + Swift only; no ObjC; 400-line file cap)
   - `wawona-ios-min-os`, `wawona-ios-app-entry`, `wawona-uniffi-domain`
   - `wawona-global-settings-exclusive` for Settings UI

## Also load when relevant

| Topic | Skill |
|-------|--------|
| `async` / actors / Task / MainActor | `swift-concurrency-pro` and `swift-concurrency` |
| Swift Testing / XCTest migration | `swift-testing-pro` and `swift-testing-expert` |
| iOS Simulator dogfood | `wawona-ios-sim-runtime` + xcodebuild MCP |
| Instruments / SwiftUI hitches | `swiftui-expert-skill` trace refs + user-instruments MCP |

## Wawona overrides (hard)

These beat upstream SwiftUI skill advice:

- Deployment floor is **iOS 13.0** on the latest iPhoneOS SDK. Never raise the
  floor to use a modern API. Use `WawonaBackport` or a functional fallback.
- No product `.m` / `.mm`. No new Swift under `src/platform/{macos,ios,watchos}`.
- Policy (prefs, profiles, launch, catalog, caps) stays in Rust / UniFFI, not
  duplicated in SwiftUI.
- `WWNCore*` poll ABI for compositor present. No UniFFI frame callbacks.
- Store IPA: no Mode B / JIT / IOMFB. macOS is never App Store feature-gated.

## Install / refresh (operator machine)

Global Cursor installs (already expected under `~/.agents/skills/`):

```bash
npx skills@latest add https://github.com/twostraws/swiftui-agent-skill --skill swiftui-pro -g -a cursor -y
npx skills@latest add https://github.com/avdlee/swiftui-agent-skill --skill swiftui-expert-skill -g -a cursor -y
npx skills@latest add https://github.com/twostraws/Swift-Concurrency-Agent-Skill --skill swift-concurrency-pro -g -a cursor -y
npx skills@latest add https://github.com/AvdLee/Swift-Concurrency-Agent-Skill --skill swift-concurrency -g -a cursor -y
npx skills@latest add https://github.com/twostraws/Swift-Testing-Agent-Skill --skill swift-testing-pro -g -a cursor -y
npx skills@latest add https://github.com/AvdLee/Swift-Testing-Agent-Skill --skill swift-testing-expert -g -a cursor -y
```

Symlink into `~/.cursor/skills/<name>` if discovery misses `~/.agents/skills`.

## Hard rejects

- Editing Apple SwiftUI without reading `swiftui-pro` and `swiftui-expert-skill`
- Applying iOS 17+ / 26-only APIs without a backport path
- Skipping Wawona glue / UniFFI / entry rules because an upstream skill prefers
  a different architecture
