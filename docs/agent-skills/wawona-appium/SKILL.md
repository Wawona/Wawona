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
| `scripts/appium/launch-wayland-client.sh` | Colima (Darwin) / nested (Linux) guests |
| `scripts/appium/ensure-colima.sh` | Fail closed unless Colima SSH works |
| `scripts/appium/verify-wayland-guest-map.py` | Fail closed on map drift |
| `scripts/appium/capture-catalog-gallery.sh` | Gallery PNGs + verify |
| `.github/workflows/ui-appium.yml` | Nightly / path-filtered runners |
| `docs/testing/appium-ui-matrix.md` | Human prose |

## Catalog Wayland guests (hard)

Darwin / macOS catalog testing is **Colima + waypipe only**.

```text
colima start
./scripts/appium/ensure-colima.sh
# Wawona owns wayland-0, then:
./scripts/appium/capture-catalog-gallery.sh foot
```

| Guest | When |
|-------|------|
| `colima` | Required on Darwin. Matrix rows are `guest = "colima"`. |
| `nested` | Linux CI only (`WAWONA_WAYLAND_GUEST=nested`). |

### Never (catalog)

- Local-bundle host bins (`Wawona.app/Contents/Resources/bin/...`) as catalog proof
- Apple Containerization / `Wawona run` / `container` guest for catalog
- Publish gallery PNG of Machines, Settings, or full desktop
- Label `weston-simple-shm` rainbow as `weston_terminal`
- Claim green without `catalog-gallery/<client>.png` passing
  `require_client_screenshot`

### Present reveal (macOS)

Start opens **Wawona Terminal**. Close that window (or Focus) so
`showSessionSurface` mounts `wwn.compositor.surface`. Without that, Mac2
sees Machines only.

Dark terminals (foot, weston-terminal): blank detector needs **flat AND**
near-black/white. Low mean alone is not blank (`screenshot_evidence.py`).

Nested weston in a Colima guest is the product path. If someone debugs a
host `weston` binary: stale nix `wayland-backend.so` aborts on
`weston_log_set_handler` unless `WESTON_BACKEND_DIR` points at the app
tree. Catalog must not use that host path.

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
- Darwin catalog without Colima

Rule: `wawona-appium-ui-gh`. Host install: `/etc/nix-darwin/.dotfiles/docs/appium-agents.md`.
RAG: `wwn-mcp/knowledge/wawona/appium-ui-gh.md`,
`appium-catalog-colima.md`.
