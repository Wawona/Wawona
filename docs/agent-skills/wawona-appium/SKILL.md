---
name: wawona-appium
description: >-
  Mode A Appium UI matrix on GitHub runners. Use when editing Tests/appium,
  ui-appium.yml, wwn.* selectors, Wayland guest launchers, or when any UI /
  Appium / GUI runner job is red. Load dendritic appium skills first; fix
  failures with Appium, not agent-device.
---

# Wawona Appium (GH runners)

## Load first

1. Dendritic skill `appium` (`~/.agents/skills/appium/SKILL.md`).
2. Driver child: `appium-setup-xcuitest` | `appium-setup-uiautomator2` |
   `appium-setup-mac2` | `appium-troubleshooting`.
3. This skill + rule `wawona-appium-ui-gh`.

## Paths

| Path | Role |
|------|------|
| `Tests/appium/` | pytest + page objects |
| `Tests/appium/matrix.toml` | Platform + catalog guest gates |
| `Tests/appium/selectors.json` | Canonical `wwn.*` ids |
| `scripts/appium/launch-wayland-client.sh` | Container / Colima / nested Wayland guests |
| `scripts/appium/verify-wayland-guest-map.py` | Fail closed on map drift |
| `.github/workflows/ui-appium.yml` | Nightly / path-filtered runners |
| `docs/testing/appium-ui-matrix.md` | Human prose |

## Runner failure loop

Red `ui-appium` (or UI lane Appium owns):

```text
gh run view <id> --log-failed
→ load appium + appium-troubleshooting + driver child
→ reproduce (same caps / platform)
→ fix suite | selectors | guest | product a11y
→ re-run evidence (local pytest or workflow_dispatch)
```

Never greenwash with skip stubs or agent-device/osascript.

## Split vs agent-device

| Surface | Tool |
|---------|------|
| Mode A product UI on GH runners | **Appium** |
| Local dogfood / Mode B vphone tipa/APT | **agent-device** |

## Hard rejects

- Guess driver caps without Appium skills
- Replace runner UI with agent-device
- Invent non-`wwn.*` accessibility ids
- Catalog card skips instead of Wayland guests

Rule: `wawona-appium-ui-gh`. Host install: `/etc/nix-darwin/.dotfiles/docs/appium-agents.md`.
