# Settings → Dependencies is this target only

Settings → Dependencies lists packages **actually linked or bundled into
that product**. The inventory is generated from
[`dependencies/wawona/settings-deps.nix`](../../dependencies/wawona/settings-deps.nix)
and shipped as `SettingsDependencies.json` (Apple bundle / Android assets /
Linux `include_str!`).

## Hard rejects

- Copying another platform's dep list (macOS OpenSSH/sshpass/MoltenVK onto
  iOS; Apple MoltenVK onto Android; Android OpenSSH portable onto watchOS).
- Hand-editing Compose/GTK/ObjC rows with versions from a different target.
- Adding a flake input or linked archive to a product without updating that
  product's inventory in the same change.
- Showing kernel DRM/KGSL ICDs or packages that are not in the closure.

## Do this

1. Edit `settings-deps.nix` inventories for the product (`ios`, `macos`,
   `android`, `linux`, `watchos`, `tvos`, …).
2. Refresh the matching JSON snapshot:
   `src/resources/settings-deps/<target>/SettingsDependencies.json`,
   `android/app/src/main/assets/SettingsDependencies.json`, or
   `src/linux/ui/settings_dependencies.json`.
3. Keep roles honest: Apple mobile SSH is libssh2; macOS/Android/Linux SSH
   is OpenSSH. watchOS/tvOS GPU stacks stay off the list until the gate
   flips.

Tracked Cursor mirror: `.cursor/rules/wawona-settings-dependencies.mdc`.
