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

### Mac2 Automation Mode + TCC

`appium driver doctor mac2` warning
`Automation Mode requires user authentication` maps to WDA
`Not authorized for performing UI testing actions` even when Accessibility
TCC already allows `WebDriverAgentRunner-Runner`.

Fix (admin GUI password once):

```bash
osascript -e 'do shell script "/usr/bin/automationmodetool enable-automationmode-without-authentication" with administrator privileges'
automationmodetool   # expect: DOES NOT REQUIRE user authentication
appium driver doctor mac2   # Automation Mode check green
```

Non-interactive `automationmodetool …` fails (empty password). Prefer
osascript admin dialog. Also keep Accessibility for
`WebDriverAgentRunner-Runner` after WDA rebuilds.

### Tip app + clean launch (hard)

Rule `wawona-test-tip-app`. Every Appium / test host launch:

```bash
eval "$(scripts/appium/ensure-tip-wawona-macos.sh)"
# rebuilds when git HEAD drifts; quits leftovers; starts tip binary
```

Never `/Applications/Wawona.app` or old `DerivedData-macos*`.
`capture-catalog-gallery.sh` calls ensure-tip first.
`WAWONA_TEST_REBUILD=1` forces xcodebuild. `WAWONA_ALLOW_STALE_TEST_APP=1`
is forbidden for catalog.

`ensure-colima.sh` resolves `nixpkgs#colima` when brew is missing. Use Colima's
freshly generated SSH config (`colima ssh-config`, stored under
`${COLIMA_HOME:-$HOME/.colima}/ssh_config`) for guest commands. Do not assume
the private key lives at `~/.colima/_lima/_config/user`: Colima can use another
home/profile, and an already-running VM can still be reachable through its
generated SSH config when that default key path is absent.
The GitHub macOS catalog job gives Colima and Lima unique homes and sets a
unique `COLIMA_PROFILE` under `runner.temp` before starting the VM. Isolate the
profile as well as both homes: runner images can inherit a stale active profile
even when the config directories are fresh. Determine status from
`colima status`'s exit code, not a substring match on output because "is not
running" contains "running". Local runs use the normal profile.
The macOS runner installs Colima, Lima, Docker CLI, and QEMU together because
Colima's Docker runtime checks for the host `docker` command. GitHub macOS
runners are virtual machines, so the CI job selects QEMU instead of VZ. Lima's
QEMU backend falls back from HVF to TCG when the runner does not expose HVF.
Local runs keep Colima's normal VM type.
`WAWONA_MAC2_MANAGE_APP=1` + `skipAppKill`. `MANAGE_APP=0` drops bundleId.

### Colima guests beyond Ubuntu apt

Ubuntu 24.04 apt covers weston/sway/foot/plasma/gnome/phosh/konsole/…
Non-apt catalog rows (niri, hyprland, mango, cosmic-comp, ghostty) install
via **guest nix-profile** (`nix profile install nixpkgs#…` after single-user
nix in the Colima VM). `launch-wayland-client.sh` sources that profile and
resolves absolute paths. Mango needs `WLR_BACKENDS=wayland` + a config under
`~/.config/mango/`. Phosh binary is `/usr/libexec/phosh`.

### Present reveal (macOS)

Start opens **Wawona Terminal**. A Wayland client attach auto-opens Present (or Close/Focus); 
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

## CI artifacts

CI uses `scripts/appium/ci-prepare-artifacts.sh` → `test-artifacts/appium/`
(non-hidden). Local dogfood stays `.agent-device/test-artifacts/appium`.
macOS catalog: tip + Colima smoke (`weston_simple_shm foot`); **fail closed**
if no PNG. Never `exit 0` + `SKIPPED.txt` (false green on tip `a58384fc`).
Linux catalog only when `products_ready`. Gallery upload
`if-no-files-found: error` when that step ran.

For manual runs with `products_ready=true`, also provide `products_run_id` from
the successful Gate: products run. Cross-workflow artifact downloads must use
that run ID and verify its conclusion and commit SHA before the Appium lanes
start. The workflow fails early when the source run is missing, failed, or for
a different commit.

## Linux Appium driver setup

The Linux runner uses the community Appium Linux driver. Install the pinned
driver and its AT-SPI runtime before starting the server. Start a session
D-Bus bus for AT-SPI, verify the installed driver advertises `atspi2`, then
wait for `/status` to return before running pytest. Do not hide driver or apt
installation errors with `|| true`.

Linux capabilities must use `platformName=Linux`,
`appium:automationName=atspi2`, and `appium:appName` set to the actual AppImage
path. The former `appium-linux-driver` package name was not published, and
`automationName=Linux` selected no driver. CI now downloads the x86-64 runtime
from the pinned upstream release and verifies its SHA-256 before installing.
The runtime package includes a separately distributed native AT-SPI library.
See RAG `appium-linux-driver-ci.md` for the incident and evidence.

## Hard rejects

- Guess driver caps without Appium skills
- Replace runner UI with agent-device
- Invent non-`wwn.*` accessibility ids
- Catalog card skips instead of Wayland guests
- Darwin catalog without Colima
- Appium CI artifacts under `.agent-device/` (use `ci-prepare-artifacts.sh`)
- `exit 0` + `SKIPPED.txt` for catalog (false green)
- Job success without `catalog-gallery/*.png` after a catalog step ran
Rule: `wawona-appium-ui-gh`. Host install: `/etc/nix-darwin/.dotfiles/docs/appium-agents.md`.
RAG: `wwn-mcp/knowledge/wawona/appium-ui-gh.md`,
`appium-catalog-colima.md`.
