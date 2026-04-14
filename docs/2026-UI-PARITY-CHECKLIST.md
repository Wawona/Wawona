# 2026 UI Parity Checklist

Use this checklist before merging changes that touch shared UI, Android host wrappers, or wearable flows.

## Required builds

- `nix build .#wawona-android`
- `nix build .#wawona-wearos-android`
- Darwin backend/package targets required by the current branch scope

## Screenshot capture matrix

Capture the following screenshots into one folder (example: `artifacts/ui-parity`):

- `ios_phone_home_light.png`
- `android_phone_home_light.png`
- `ios_phone_home_dark.png`
- `android_phone_home_dark.png`
- `ios_phone_settings_light.png`
- `android_phone_settings_light.png`
- `ios_phone_settings_dark.png`
- `android_phone_settings_dark.png`
- `watchos_wear_home_light.png`
- `wearos_wear_home_light.png`
- `watchos_wear_home_dark.png`
- `wearos_wear_home_dark.png`

## Automated diff gate

Run:

```bash
python3 scripts/ui_parity_diff.py --screenshots-dir artifacts/ui-parity --threshold 0.12
```

- Lower threshold means stricter parity.
- If this fails, inspect color/spacing/navigation differences and rerun after fixes.

## Manual review checklist

- Phone navigation hierarchy is equivalent between iOS and Android.
- Global settings sections and machine settings entry points are present and ordered the same.
- Typography scale and card spacing are visually close (no Android-only shell drift).
- Wear root flow (machine list + quick connect action) matches watchOS compact behavior.
- Compositor surface path on Android no longer shows placeholder view.
