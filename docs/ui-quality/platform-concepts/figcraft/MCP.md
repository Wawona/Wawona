# Wire FigCraft MCP into Cursor

FigCraft MCP was **not** in the nix-managed `~/.cursor/mcp.json` when this
design was built. Headless work used `figcraft-cli run` (same engine as MCP).

## Install CLI (macOS)

DMG app alone has no CLI. Download the matching zip:

https://github.com/storytold/figcraft/releases/download/v0.18.1/figcraft-cli-0.18.1-macos-universal.zip

```bash
unzip figcraft-cli-*.zip
cp figcraft-cli-*/figcraft-cli ~/.local/bin/
chmod +x ~/.local/bin/figcraft-cli
```

## Skill

```bash
npx skills add dnviti/artcraft-skills --skill figcraft-design -g -y
```

## Cursor MCP (add via home-manager / Cursor Settings)

```json
"figcraft": {
  "command": "/Users/8amps/.local/bin/figcraft-cli",
  "args": [
    "mcp",
    "--automation-read-root",
    "/Users/8amps/Wawona/Wawona/docs/ui-quality/platform-concepts/figcraft",
    "--automation-write-root",
    "/Users/8amps/Wawona/Wawona/docs/ui-quality/platform-concepts/figcraft"
  ]
}
```

Live window (optional):

```bash
open -a FigCraft --args --control 7979
```

Then MCP args: `["mcp", "--attach", "7979"]` (no automation roots with attach).

## Skill pack

`~/.agents/skills/figcraft-design` (community ArtCraft skill).
