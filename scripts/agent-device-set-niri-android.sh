#!/usr/bin/env bash
# Force Default Machine nativeLauncher=niri via SharedPreferences so nested
# niri + Mod+D/fuzzel e2e does not depend on the flaky Edit-sheet UI.
#
# Usage: scripts/agent-device-set-niri-android.sh [adb-serial]
set -euo pipefail

PKG=com.aspauldingcode.wawona
PREFS=wawona_prefs.xml
SERIAL="${1:-${WAWONA_ANDROID_SERIAL:-${ANDROID_SERIAL:-}}}"
ADB=(adb)
if [[ -n "$SERIAL" ]]; then
  ADB=(adb -s "$SERIAL")
fi

"${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true

"${ADB[@]}" shell "run-as $PKG mkdir -p shared_prefs" >/dev/null

TMP="$(mktemp)"
OUT="$(mktemp)"
cleanup() { rm -f "$TMP" "$OUT"; }
trap cleanup EXIT

if ! "${ADB[@]}" shell "run-as $PKG cat shared_prefs/$PREFS" >"$TMP" 2>/dev/null; then
  printf '%s\n' '<?xml version='\''1.0'\'' encoding='\''utf-8'\'' standalone='\''yes'\'' ?>' '<map>' '</map>' >"$TMP"
fi

python3 - "$TMP" "$OUT" <<'PY'
import html, json, pathlib, re, sys, time

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")
now = int(time.time() * 1000)

m = re.search(
    r'<string name="wawona\.machineProfiles\.v1">(.*?)</string>',
    text,
    re.S,
)
profiles = []
if m:
    try:
        profiles = json.loads(html.unescape(m.group(1)))
    except json.JSONDecodeError:
        profiles = []

if not profiles:
    profiles = [{
        "id": "e2e-niri-default",
        "name": "Default Machine",
        "type": "native",
        "sshEnabled": False,
        "sshHost": "",
        "sshPort": 22,
        "sshUser": "",
        "sshPassword": "",
        "sshBinary": "ssh",
        "sshAuthMethod": "password",
        "sshKeyPath": "",
        "sshKeyPassphrase": "",
        "nativeLauncher": "niri",
        "remoteCommand": "",
        "customScript": "",
        "waypipeCompress": "lz4",
        "waypipeThreads": "0",
        "waypipeVideo": "none",
        "waypipeDebug": False,
        "waypipeOneshot": False,
        "waypipeDisableGpu": False,
        "waypipeLoginShell": False,
        "waypipeTitlePrefix": "",
        "waypipeSecCtx": "",
        "settingsOverrides": {},
        "runtimeOverrides": {},
        "favorite": False,
        "createdAtMs": now,
        "updatedAtMs": now,
        "vmSettings": {
            "provider": "utm-se",
            "vmIdentifier": "",
            "vsockPort": "",
            "notes": "",
        },
        "containerSettings": {
            "runtime": "docker",
            "containerRef": "",
            "entryCommand": "",
            "notes": "",
        },
    }]
else:
    touched = False
    for p in profiles:
        if p.get("type") == "native" or p.get("name") == "Default Machine":
            p["nativeLauncher"] = "niri"
            p["updatedAtMs"] = now
            touched = True
            break
    if not touched:
        profiles[0]["nativeLauncher"] = "niri"
        profiles[0]["updatedAtMs"] = now

active = profiles[0]["id"]
profiles_json = html.escape(json.dumps(profiles, separators=(",", ":")), quote=True)

def upsert_string(xml: str, name: str, value: str) -> str:
    pat = rf'<string name="{re.escape(name)}">.*?</string>'
    repl = f'<string name="{name}">{value}</string>'
    if re.search(pat, xml, re.S):
        return re.sub(pat, repl, xml, count=1, flags=re.S)
    return re.sub(r"</map>\s*$", repl + "\n</map>\n", xml)

def upsert_bool(xml: str, name: str, value: str) -> str:
    pat = rf'<boolean name="{re.escape(name)}"[^/]*/>'
    repl = f'<boolean name="{name}" value="{value}" />'
    if re.search(pat, xml):
        return re.sub(pat, repl, xml, count=1)
    return re.sub(r"</map>\s*$", repl + "\n</map>\n", xml)

text = upsert_string(text, "nativeLauncher", "niri")
text = upsert_string(text, "wawona.machineProfiles.v1", profiles_json)
text = upsert_string(text, "wawona.activeMachineId.v1", active)
text = upsert_bool(text, "hasSeenWelcome", "true")
text = upsert_bool(text, "wawona.machineProfilesMigrated.v1", "true")
text = upsert_bool(text, "waypipeSSHEnabled", "false")

dst.write_text(text, encoding="utf-8")
print(f"set nativeLauncher=niri active={active} profiles={len(profiles)}")
PY

"${ADB[@]}" shell "run-as $PKG sh -c 'cat > shared_prefs/$PREFS'" <"$OUT"
echo "== Android prefs: nativeLauncher=niri (${SERIAL:-default}) =="
