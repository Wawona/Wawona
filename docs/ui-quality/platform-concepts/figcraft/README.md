# FigCraft: Wawona ALL_TARGETS UI (v4)

Comp-led valley-glass. Concept PNGs = pixel truth. Editable macOS traces
`refs/macOS.png` (wallpaper → veil → glass → chrome).

## Rebuild

```bash
export PATH="$HOME/.local/bin:$PATH"
cd Wawona/docs/ui-quality/platform-concepts/figcraft
bun scripts/build-macos-v4.mjs
figcraft-cli run scripts/build-macos-v4.json \
  --automation-read-root "$PWD" \
  --automation-write-root "$PWD" \
  --out Wawona-ALL_TARGETS.figcraft
open -a FigCraft Wawona-ALL_TARGETS.figcraft
```

## Pages

1. **00 Concept plates** – every platform concept PNG
2. **01 Foundations** – tokens
3. **02 macOS editable** – Machines + concept underlay + Settings cover

## Latest exports

`exports/v4c/machines.png` — side-by-side with `refs/macOS.png` / underlay frame.
