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
- Wayland catalog guests on runners (container / Colima / nested)

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
- Catalog Wayland clients: real guests via
  `scripts/appium/launch-wayland-client.sh` (container / Colima / nested)
- **Catalog green = machine PNG** in
  `.agent-device/test-artifacts/appium/catalog-gallery/<client>.png`
  (non-blank). DRY is not catalog proof.
- Docs: `docs/testing/appium-ui-matrix.md`

## Hard rejects

- Fix runner UI failures with agent-device / osascript / host screencapture
- Skip Appium skills and guess XCUITest / UiAutomator2 / Mac2 caps
- Invent accessibility ids outside `wwn.*`
- Catalog packaging-card skips instead of Wayland guests
- Cancel tip `ui-appium` / Gate UI jobs to clear the queue (`wawona-ci-no-cancel`)

Cursor rule: `wawona-appium-ui-gh`. Skill: `wawona-appium`. Dendritic: `appium`.
Related: `wawona-test-control` (local agent-device), `wawona-gh`, `wawona-ci-no-cancel`.
