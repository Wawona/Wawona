# Apple Swift / SwiftUI skills (mandatory)

Wawona Compositor on Apple targets is Rust plus Swift/SwiftUI. Agents **must**
install and use Swift/SwiftUI skills for that work. Do not write Apple UI from
model priors alone.

## Required personal skills (global)

Install under `~/.agents/skills/` (symlink into `~/.cursor/skills/` if needed):

| Skill | Source |
|-------|--------|
| `swiftui-pro` | twostraws/swiftui-agent-skill |
| `swiftui-expert-skill` | AvdLee/SwiftUI-Agent-Skill |
| `swift-concurrency-pro` | twostraws/Swift-Concurrency-Agent-Skill |
| `swift-concurrency` | AvdLee/Swift-Concurrency-Agent-Skill |
| `swift-testing-pro` | twostraws/Swift-Testing-Agent-Skill |
| `swift-testing-expert` | AvdLee/Swift-Testing-Agent-Skill |

Refresh: `npx skills@latest update -g -y` (or re-run the `npx skills add …`
lines in skill `wawona-apple-swift`).

## When this fires

Any edit or review under:

- `Sources/WawonaApple`, `Sources/WawonaUI`, `Sources/WawonaWatch`
- `Darwin/`
- Apple Settings / Machines / Present / compositor host SwiftUI
- UniFFI Swift glue touching Apple UI

**First action:** read skill `wawona-apple-swift`, then `swiftui-pro` and
`swiftui-expert-skill` (plus concurrency/testing skills when those topics
apply). Then Wawona rules: `wawona-swiftui-backports`,
`wawona-apple-swift-glue`, `wawona-ios-min-os`, `wawona-ios-app-entry`.

## Wawona wins on conflict

iOS **13.0** floor + `WawonaBackport`, zero ObjC product classes, Rust policy
ownership, and store Mode A firewall override upstream skill modernization
advice.

Canonical skill: `wawona-apple-swift`.
Cursor rule: `wawona-apple-swift-skills`.
