# Appium UI testing on GitHub runners (mandatory)

Mode A product UI on **GitHub-hosted runners** is **Appium 2**
(`Watch: Appium UI matrix` / `ui-appium.yml`). Agents **must** load and use
the Appium skill pack. Do not invent a second CI UI stack.

**agent-device** stays local dogfood and **vphone Mode B** only. Never replace
Appium Gate/Watch jobs with agent-device, osascript, or host screencapture.

## Required skills (load first)

| Skill | Role |
|-------|------|
| `appium` | Dendritic router (`~/.agents/skills/appium`) |
| `appium-setup` / `appium-setup-xcuitest` / `appium-setup-uiautomator2` / `appium-setup-mac2` | Driver setup |
| `appium-troubleshooting` | Red sessions, selectors, WDA |
| `wawona-appium` | Wawona suite paths + runner loop |

Install / refresh from `/etc/nix-darwin/.dotfiles` (`skills/appium`,
`docs/appium-agents.md`). MCP server name: **`appium`** (`appium-mcp`).

## When this fires

- Editing `Tests/appium/`, `scripts/appium/`, `.github/workflows/ui-appium.yml`
- Touching `wwn.*` a11y ids / `selectors.json` / `matrix.toml`
- Any red or flaky **UI / Appium / GUI smoke** job on GitHub Actions
- Wayland catalog guests on runners (Colima on Darwin; nested on Linux)

## Runner failure loop (hard)

If a GitHub runner UI job fails (Appium, GUI smoke that Appium owns, or a
lane under `ui-appium.yml`):

1. Load skill `appium` + `appium-troubleshooting` (and the driver child for
   that platform).
2. Reproduce with the same driver locally or on the matching runner class
   (`macos-26` Apple, `ubuntu-latest` KVM Android / Xvfb Linux).
3. Fix via Appium suite, selectors, capabilities, guest launcher, or product
   a11y. Re-run until green evidence exists.
4. Do **not** greenwash with skip stubs, `|| true`, or "works on my Simulator
   with osascript".

## Suite contract

- Root: `Wawona/Tests/appium/`
- Gates: `matrix.toml` (PlatformCapabilities)
- Selectors: `wwn.*` only
- **Tip host app (hard):** Darwin Mac2 always runs
  `scripts/appium/ensure-tip-wawona-macos.sh` first (rebuild when HEAD
  drifts, clean launch tip binary, refuse `/Applications`). See
  `wawona-test-tip-app`.
- Catalog Wayland clients: real guests via
  `scripts/appium/launch-wayland-client.sh` (**Colima on Darwin**; nested on
  Linux). Run `ensure-colima.sh` first on macOS. No local-bundle.
- Colima guest SSH must use its generated SSH config (`COLIMA_SSH_CONFIG` or
  `${COLIMA_HOME:-$HOME/.colima}/ssh_config`). Never assume an internal key,
  port, or profile path.
- The macOS CI job creates unique `COLIMA_HOME` and `LIMA_HOME` directories
  and a unique `COLIMA_PROFILE` under `runner.temp` before starting its
  disposable VM. Isolate all three: runner images can inherit stale active
  profile state even when config directories are fresh. Determine status from
  `colima status`'s exit code, not a substring match on output because
  "is not running" contains "running". Local runs keep their normal profile.
- The macOS runner installs Colima, Lima, Docker CLI, and QEMU together. Colima's
  default Docker runtime requires the host `docker` command before VM startup.
  GitHub macOS runners are virtual machines, so the CI profile selects QEMU
  instead of VZ. Lima falls back from HVF to TCG when HVF is not available.
  Local runs keep the normal Colima VM type.
- **Catalog green = Present surface PNG** in
  `.agent-device/test-artifacts/appium/catalog-gallery/<client>.png`
  (non-blank via `require_client_screenshot`). Capture
  `wwn.compositor.surface` after closing Wawona Terminal / Focus. DRY /
  Machines / Settings / desktop PNGs are not catalog proof.
- Docs: `docs/testing/appium-ui-matrix.md`. RAG:
  `wwn-mcp/knowledge/wawona/appium-catalog-colima.md`.

## Hard rejects

- Fix runner UI failures with agent-device / osascript / host screencapture
- Skip Appium skills and guess XCUITest / UiAutomator2 / Mac2 caps
- Invent accessibility ids outside `wwn.*`
- Catalog packaging-card skips instead of Wayland guests
- Claim a catalog client OK without a Present surface screenshot
- Darwin catalog via local-bundle host bins or Apple Containerization
- Launch `/Applications/Wawona.app` or stale DerivedData for Appium
- Set `WAWONA_MAC2_MANAGE_APP=0` for catalog (drops bundleId; no Machines root)
- Ignore WDA `Not authorized for performing UI testing actions` (TCC /
  Automation Mode; see skill `wawona-appium`)
- Cancel tip `ui-appium` / Gate UI jobs to clear the queue (`wawona-ci-no-cancel`)

Cursor rule: `wawona-appium-ui-gh`. Skill: `wawona-appium`. Dendritic: `appium`.
Related: `wawona-test-tip-app`, `wawona-test-control`, `wawona-gh`,
`wawona-ci-no-cancel`.
