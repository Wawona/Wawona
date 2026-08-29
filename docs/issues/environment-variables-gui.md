# Environment Variables Settings GUI

## Status

- **Implemented on `development`**. Tracking issue [#157](https://github.com/Wawona/Wawona/issues/157)
- Children:
  - [#158](https://github.com/Wawona/Wawona/issues/158) catalog + resolver + persistence ✅
  - [#159](https://github.com/Wawona/Wawona/issues/159) Apple Settings + Machine Settings UI ✅
  - [#160](https://github.com/Wawona/Wawona/issues/160) Android Settings + JNI apply ✅
  - [#161](https://github.com/Wawona/Wawona/issues/161) Linux GTK Environment page ✅
- Class: Settings / Machines product surface (all targets)
- Repo: [`Wawona`](https://github.com/Wawona/Wawona) (L4)

Keep this file synchronized with the GitHub issue body when phases change.
Cursor plan: `env_vars_settings_gui_e79f70a7`.

## Related issues

| Issue | Why it matters |
|-------|----------------|
| [#67](https://github.com/Wawona/Wawona/issues/67) | UI contracts. Add `GlobalSettingsSectionID.environment` |
| [#89](https://github.com/Wawona/Wawona/issues/89) | Global + per-machine override pattern |
| [#117](https://github.com/Wawona/Wawona/issues/117) | Settings ↔ Machines pref sync |
| [#90](https://github.com/Wawona/Wawona/issues/90) | Linux Settings parity |
| [#77](https://github.com/Wawona/Wawona/issues/77) | ROADMAP sequencing |

## Summary

Wawona injects dozens of environment variables at launch but they are scattered
across `setenv` sites and invisible except for a read-only Connection snippet.
Add a Windows-style Environment Variables manager:

- **System variables** → Global Wawona Settings → Environment
- **User variables** → Machine Settings → Environment (that machine only)
- **New / Edit / Delete / Reset** with Wawona catalog defaults as the reset target

First-class Settings stay (Vulkan dropdown owns `VK_ICD_FILENAMES`, etc.). The
env table is inventory + override + custom-var surface.

## Precedence

`machine overrides > global user overrides > first-class setting mapping >
catalog default > host process env`

## Persistence

- Global: `wawona.pref.environment.v1`
- Per-machine: `runtimeOverrides.environment` (explicit Codable field. Never
  stash in `settingsOverrides`; Swift drops unknown keys)
- Also add `runtimeOverrides.compositorBackend` so `NIRI_BACKEND` has a typed home
- Shape: `{ "TERM": { "action": "set", "value": "xterm" }, "RUST_LOG": { "action": "unset" } }`

## Hazards

1. Two override bags (Swift typed vs ObjC `settingsOverrides`). Env must be explicit.
2. Process-wide `setenv` on Apple mobile. Re-apply on every connect/focus.
3. Wire resolver into existing apply path, not a third writer.
4. Strip `DYLD_*` / `LD_*` on Apple-mobile local spawn even if user extras set them.
5. Secrets (`SSHPASS`, `WAYPIPE_SSH_PASSWORD`) never shown as values.

## Delivery checklist

- [x] Catalog YAML + model + unit tests (#158)
- [x] Resolver on Apple / Android / Linux apply paths (#158)
- [x] Apple + watchOS UI (#159)
- [x] Android UI + JNI (#160)
- [x] Linux GTK page (#161)
- [x] Docs: `settings.md`, `machine-profiles.md`, mission wording
- [x] Connection no longer duplicates env vars (TCP only); full inventory under **Environment Variables**
- [x] Per-machine: Edit Machine → Environment Variables (draft overrides → `runtimeOverrides.environment`)
- [x] Model smoke: merge / reset-managed / secrets / DYLD strip / prefs
- [ ] agent-device UI smoke after product rebuild with this tip

