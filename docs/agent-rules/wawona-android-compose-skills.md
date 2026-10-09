# Android Compose skills (mandatory)

Wawona Android host UI is Kotlin + Jetpack Compose. Agents **must** install
and use Compose/Android skills for that work. Do not write Android UI from
model priors alone.

## Required personal skills (global)

Install under `~/.agents/skills/` (symlink into `~/.cursor/skills/` if needed):

| Skill | Source |
|-------|--------|
| `compose-agent` | hamen/compose_skill |
| `modern-jetpack-compose` | anhvt52/jetpack-compose-skills |
| `jetpack-compose-audit` | hamen/compose_skill |
| `edge-to-edge`, `styles`, `navigation-3`, `migrate-xml-views-to-jetpack-compose`, `testing-setup` | android/skills |
| `compose-ui-testing-patterns`, `compose-focus-navigation`, `compose-animations`, `kotlin-concurrency-and-flow`, `using-chrisbanes-skills` | chrisbanes/skills |
| `mobile-android-design` | wshobson/agents |
| `android-kotlin` | alinaqi/maggy |

Refresh: re-run the `npx skills add …` lines in skill `wawona-android-compose`.

## When this fires

Any edit or review under:

- `Wawona/android/`, `android/app/src/main/java/**/*.kt`
- Compose Machines / Settings / Present hosts
- Kotlin call sites into JNI / UniFFI domain APIs

**First action:** read skill `wawona-android-compose`, then `compose-agent`
and `modern-jetpack-compose` (plus topic skills when relevant). Then Wawona
rules: `wawona-global-settings-exclusive`, `wawona-android-jbr`,
`wawona-mode-a-b`, `wawona-uniffi-domain`.

## Wawona wins on conflict

Material 3 Expressive is Android 16+ only. In-app Settings only. Rust owns
product policy. Play Mode A firewall. Guest GUI is Wayland into iland.

Canonical skill: `wawona-android-compose`.
Cursor rule: `wawona-android-compose-skills`.
