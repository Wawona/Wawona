# vphone-cli CFW patches (Wawona)

`vphoned_accessibility.*` implements `accessibility_tree` for agent-device `@eN`
refs (app_list icon-grid heuristic until AXRuntime lands).

Apply into the local vphone-cli tree before `cfw install -V jb`:

```bash
SRC="${VPHONE_ROOT:-$HOME/.vphone}/src/vphone-cli"
cp dependencies/tools/vphone-patches/vphoned_accessibility.* "$SRC/scripts/vphoned/"
# Also ensure vphoned.m advertises accessibility_tree when apps are available.
```

Host sock `{"t":"ax"}` (VPhoneHostControl) falls back to `app_list` even before
guest CFW is rebuilt.
