# Appium UI matrix

Mode A product UI and Wayland sessions on GitHub-hosted runners. Agent-device
stays for local dogfood and vphone Mode B.

## Agent rule (hard)

Rule `wawona-appium-ui-gh` (alwaysApply). Skill `wawona-appium`. **If a
GitHub runner UI / Appium / GUI job fails, load Appium skills, reproduce, and
fix with Appium.** Do not use agent-device or osascript to paper over runner
reds. agent-device stays local dogfood and vphone Mode B.

## Agent skills (host)

Before local Appium work, load the dendritic Appium skill pack installed from
`/etc/nix-darwin/.dotfiles/skills/appium`:

| Agent | Discovery |
|-------|-----------|
| Cursor | `~/.agents/skills/appium`, `~/.cursor/skills/appium` |
| Antigravity | `~/.gemini/antigravity/skills/appium` |
| Codex / ChatGPT desktop | `~/.codex/skills/appium` + `[mcp_servers.appium]` |

Docs: `/etc/nix-darwin/.dotfiles/docs/appium-agents.md`. Upstream setup skills:
`appium-setup`, `appium-setup-uiautomator2`, `appium-setup-xcuitest`,
`appium-setup-mac2`, `appium-troubleshooting`. MCP server name: `appium`
(`appium-mcp`).

Restart the IDE after `nh darwin switch` or after running
`scripts/configure-appium-agents.py`.

## Suite layout

| Path | Role |
|------|------|
| [`Tests/appium/`](../../Tests/appium/) | pytest + Appium 2 page objects |
| [`Tests/appium/matrix.toml`](../../Tests/appium/matrix.toml) | Platform gates + catalog Wayland guests |
| [`Tests/appium/selectors.json`](../../Tests/appium/selectors.json) | Canonical `wwn.*` ids |
| [`scripts/appium/launch-wayland-client.sh`](../../scripts/appium/launch-wayland-client.sh) | Real Wayland guest launcher |
| [`.github/workflows/ui-appium.yml`](../../.github/workflows/ui-appium.yml) | Nightly / path-filtered `development` |

## Wayland catalog clients (23.A / 23.B)

Catalog rows are **not** packaging-card skips. Each client is a real Wayland
process forwarded into the host Wawona socket. **Pass means a machine
screenshot** of that client in
`.agent-device/test-artifacts/appium/catalog-gallery/<client>.png` (and
`index.html`) locally. DRY skips are not catalog proof. CI writes under
`test-artifacts/appium/` (non-hidden). **macOS catalog fail-closed:** tip
build + Colima smoke clients (`weston_simple_shm foot`); job red if no PNG.
Never `exit 0` with `SKIPPED.txt`. Linux catalog runs only when
`products_ready` (AppImage); otherwise the catalog step is skipped, not
fake-green. Gallery upload uses `if-no-files-found: error` when the catalog
step ran.

Capture locally (Wawona up, Appium on :4723):

```bash
./scripts/appium/capture-catalog-gallery.sh
# or one client:
./scripts/appium/capture-catalog-gallery.sh kde_plasma_de
python3 scripts/appium/verify-catalog-gallery.py
open .agent-device/test-artifacts/appium/catalog-gallery/index.html
```

Each client is a real Wayland process forwarded into the host Wawona socket:

| `guest` | How |
|---------|-----|
| `colima` | **Required on Darwin.** Colima Linux VM + `waypipe-ssh-colima-lab.sh`. No local-bundle, no Apple Containerization shortcut for catalog tests. |
| `nested` | Linux runner only: same-host nested client on `WAYLAND_DISPLAY` (`WAWONA_WAYLAND_GUEST=nested`) |

CI fails closed if `matrix.toml` and `launch-wayland-client.sh` drift
(`scripts/appium/verify-wayland-guest-map.py`). Appium then asserts the host
compositor surface (`wwn.compositor.surface`).

## Runners

| Job | Label |
|-----|-------|
| iOS, iPadOS, tvOS, visionOS, macOS, iPhone+watch | `macos-26` |
| Android emulator | `ubuntu-latest` + KVM |
| Linux desktop + nested Wayland catalog | `ubuntu-latest` + Xvfb |

visionOS job alone downloads the 26.2 runtime. Do not rebuild products in the
test job; download Gate: products artifacts when `products_ready` is set.

## Local

```bash
# Offline gate/selector + guest-map checks (no Appium server):
python3 scripts/appium/verify-matrix.py
python3 scripts/appium/verify-wayland-guest-map.py
cd Tests/appium
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
WAWONA_APPIUM_DRY=1 pytest tests/test_gates_unit.py -q

# Wayland catalog (host compositor must own wayland-0 first):
export WAWONA_APPIUM_PLATFORM=macos   # or linux
# Darwin: tip host + Colima (never /Applications).
eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"
colima start   # once on the host
./scripts/appium/ensure-colima.sh
# Or: ./scripts/appium/capture-catalog-gallery.sh foot
pytest tests/test_catalog_wayland.py -q

# Full native session (Appium server on :4723, tip app):
export WAWONA_APPIUM_PLATFORM=ios
export WAWONA_APP_PATH=/path/to/tip/Wawona.app   # never stale install
pytest tests/test_native_ui.py -q
```

Guest SSH uses a freshly generated Colima config at
`${COLIMA_HOME:-$HOME/.colima}/ssh_config`, or `COLIMA_SSH_CONFIG` when set.
Do not hardcode Colima's internal identity-file path because it can vary by
profile and runner image. The GitHub macOS guest step creates unique
`COLIMA_HOME` and `LIMA_HOME` directories under `runner.temp` before starting
the disposable VM. This avoids inheriting a stale runner profile whose Lima
metadata or SSH config is missing. Local runs use the normal Colima profile.

Tip app rule: [`../agent-rules/wawona-test-tip-app.md`](../agent-rules/wawona-test-tip-app.md).

See also [`everywhere-matrix.md`](./everywhere-matrix.md) and [`../ci.md`](../ci.md).
