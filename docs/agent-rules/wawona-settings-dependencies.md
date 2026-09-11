# Settings → Dependencies is this target only

Settings → Dependencies lists packages **actually linked or bundled into
that product**. The inventory is generated from
[`dependencies/wawona/settings-deps.nix`](../../dependencies/wawona/settings-deps.nix)
and shipped as `SettingsDependencies.json` (Apple bundle / Android assets /
Linux `include_str!`).

Each package is Okular-style (`KAboutComponent`-like):

| Field | Meaning |
|-------|---------|
| `name` | Display name |
| `version` | Real package / recipe version (not a mode label) |
| `role` | Short description (Mode A/B stays here for iland) |
| `url` | Source repo, or project website if proprietary |
| `license` | SPDX short id |

## Hard rejects

- Copying another platform's dep list (macOS OpenSSH/sshpass/MoltenVK onto
  iOS; Apple MoltenVK onto Android; Android OpenSSH portable onto watchOS).
- Hand-editing Compose/GTK/ObjC rows with versions from a different target.
- Hand-editing `SettingsDependencies.json` / `settings_dependencies.json`
  (always regen from Nix).
- Adding a flake input or linked archive to a product without updating that
  product's inventory in the same change.
- Showing kernel DRM/KGSL ICDs or packages that are not in the closure.
- Placeholder versions: `chromium`, `userland`, `cpu`, `sdk` as the version
  string (use recipe CalVer / Chromium milestone / git rev).

## Do this

1. Edit `settings-deps.nix` (`versions`, `catalog`, and/or `inventories`).
2. Regenerate JSON snapshots:
   `./scripts/regen-settings-deps.sh`
3. Keep roles honest: Apple mobile SSH is libssh2; macOS/Android/Linux SSH
   is OpenSSH. watchOS GPU stays off the list. tvOS lists MoltenVK and
   ANGLE when `WWN_TVOS_GPU` is linked.
4. **iland** version comes from sibling `wwn-iland/VERSION` (CalVer). Bump
   that file in `wwn-iland` when shipping graphics stack changes.

Tracked Cursor mirror: `.cursor/rules/wawona-settings-dependencies.mdc`.
