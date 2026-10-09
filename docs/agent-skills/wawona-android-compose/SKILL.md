---
name: wawona-android-compose
description: >-
  Mandatory Kotlin/Jetpack Compose skill gate for Wawona Android. Use whenever
  editing or reviewing android/app Compose UI, SettingsDialog, Machines Compose,
  JNI glue call sites from Kotlin, or Material 3 host chrome.
---

# Android Kotlin / Compose (mandatory)

Wawona Android host UI is Kotlin + Jetpack Compose. Rust still owns policy
(prefs, profiles, launch, compositor). Do not edit Compose from model priors
alone.

## Before any Android Compose / Kotlin UI edit

Read these skills **in this order**, then edit:

1. **`compose-agent`** (hamen) at `~/.agents/skills/compose-agent/SKILL.md`
2. **`modern-jetpack-compose`** at `~/.agents/skills/modern-jetpack-compose/SKILL.md`
3. **`using-chrisbanes-skills`** when several Kotlin/Compose concerns overlap
4. **Wawona product rules** that always win on conflict:
   - `wawona-global-settings-exclusive` (in-app `SettingsDialog` only)
   - `wawona-uniffi-domain` / Rust domain (no policy forks in Compose)
   - `wawona-mode-a-b` / Play Mode A firewall (no Mode B in Play AAB)
   - `wawona-android-jbr` (Gradle JVM is JBR 21)
   - `wawona-product-map`, `wawona-platform-targets`

## Also load when relevant

| Topic | Skill |
|-------|--------|
| Material / theming | `styles`, `mobile-android-design` |
| Edge-to-edge / insets / IME | `edge-to-edge` |
| Navigation | `navigation-3`, `compose-focus-navigation` |
| Animation | `compose-animations` |
| Coroutines / Flow | `kotlin-concurrency-and-flow` |
| Kotlin language shape | `android-kotlin` |
| UI tests | `compose-ui-testing-patterns`, `testing-setup` |
| XML → Compose migration | `migrate-xml-views-to-jetpack-compose` |
| Repo-wide Compose review | `jetpack-compose-audit` |
| agent-device Android dogfood | `wawona-test-control`, `wawona-agent-device` |

## Wawona overrides (hard)

- **Material 3 Expressive** is Android **16+** only. Do not require Expressive
  APIs on older Play devices without a fallback.
- Global Settings: one in-app Compose `SettingsDialog`. Never
  `APPLICATION_PREFERENCES` / App Info Preferences as a second catalog.
- Policy (prefs, profiles, launch, catalog, caps) stays in Rust / UniFFI.
  Compose mirrors frozen fields; lift new fields to Rust.
- Play / Mode A: no Mode B, JIT, jailbreak, or privileged desktop engines.
- Guest GUI stays Wayland into Wawona (iland). Not UTM Spice paths.
- Prefer Compose over new XML Views. Migrate with the official migrate skill.

## Install / refresh (operator machine)

```bash
npx skills@latest add https://github.com/hamen/compose_skill --skill compose-agent --skill jetpack-compose-audit -g -a cursor -y
npx skills@latest add https://github.com/anhvt52/jetpack-compose-skills --skill modern-jetpack-compose -g -a cursor -y
npx skills@latest add https://github.com/android/skills --skill edge-to-edge --skill styles --skill navigation-3 --skill migrate-xml-views-to-jetpack-compose --skill testing-setup -g -a cursor -y
npx skills@latest add https://github.com/chrisbanes/skills --skill compose-ui-testing-patterns --skill compose-focus-navigation --skill compose-animations --skill kotlin-concurrency-and-flow --skill using-chrisbanes-skills -g -a cursor -y
npx skills@latest add https://github.com/wshobson/agents --skill mobile-android-design -g -a cursor -y
npx skills@latest add https://github.com/alinaqi/maggy --skill android-kotlin -g -a cursor -y
```

Symlink into `~/.cursor/skills/<name>` if discovery misses `~/.agents/skills`.

## Hard rejects

- Editing `android/app` Compose without reading `compose-agent` and
  `modern-jetpack-compose`
- Shipping Mode B / privileged APIs in Play AAB
- A second Global Settings host outside in-app Compose
- Duplicating Rust prefs/profile policy only in Kotlin
