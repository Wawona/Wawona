---
name: wawona-vphone-lab-recover
description: Recover a dead or stuck vphone wawona-jb lab. Use when sock is stale, SSH wait is scanning, agent-device says booted=true but the VM is off, or a foreground vm launch just died.
---

# Recover stuck vphone lab

Mode B proof device is `vphone wawona-jb`. Not Simulator. Not STARDUST.

Open the rule: `wawona-vphone-control`. Lab script:
`wwn-vphone/scripts/vphone-jb-lab.sh`.

## Detect (do this first)

| Signal | Meaning |
|---|---|
| `pgrep -lf 'vphone-cli --config .*/wawona-jb/config.plist'` | Live. Do not relaunch. |
| Sock accepts JSON | Live. |
| Sock file exists + `Connection refused` + no matching process | **Stale sock. VM is off.** |
| `agent-device devices` `booted=true` | **Not proof.** Profile is stale. |
| Lab log `no vphone process` | **Not proof.** `wait_ssh` pgrep misses real argv. |
| `nix run .#vphone-jb-lab` from Wawona flake | Often **no attr**. Use `wwn-vphone` or github. |

Real live argv:

```text
vphone-cli --config /Users/8amps/.vphone/VMs/wawona-jb/config.plist --variant jb
```

Sock: `/Users/8amps/.vphone/VMs/wawona-jb/vphone.sock`.

## Recover (automatic)

1. **Classify.** Live vs stale. Trust process + sock connect only.
2. **If live.** Leave `vphone-cli` alone. Kill only a stuck lab waiter
   (`nix run …vphone-jb-lab`, `wait_ssh`, `nc` dhcp scans). Match those
   PIDs by command line. Never `pkill -f vphone`. Never kill a process
   group that owns `vphone-cli`.
3. **If dead.** `nohup` relaunch. Visible window. Do **not** attach
   `vm launch` to a cancellable foreground agent Shell.

```bash
VPHONE=/Users/8amps/.vphone/src/vphone-cli/.build/vphone-cli.app/Contents/MacOS/vphone-cli
LOG=/Users/8amps/.vphone/VMs/wawona-jb/launch.recover.serial
caffeinate -dims -t 7200 >/dev/null 2>&1 &
nohup "$VPHONE" vm launch wawona-jb -V jb -p /Users/8amps/.vphone/src/vphone-cli -v \
  >"$LOG" 2>&1 &
disown
```

4. **Prove sock.** Prefer `{"t":"screenshot","path":"…png","screen":false}`.
   Compact JPEG `screen:true` freezes. Keep the window visible.
5. **SSH later.** Guest IPv4 drifts. Do not scan every dhcp `iPhone` lease
   with `nc -G 1` in a 900s agent loop. Probe `guest-ip.txt` / profile
   `sshHost` first. Rewrite both when a new IP answers `:22222`.
6. Then Mode B work as usual (`sbreload`, `uicache -p`, `uiopen --app Wawona`).

Optional cold start when the bundle exists: from `wwn-vphone`,
`nix run .#vphone-jb-lab`. Let that script `nohup` the VM. Do not wait
on its `wait_ssh` from an agent Shell.

## Hard rejects

- Foreground `vphone-cli vm launch` in an agent Shell. Tool cancel or
  exit 13 kills the guest. That is how a "relaunch" dies at ~50s.
- `pkill -f vphone` / `vm stop` / `agent-device shutdown` as recover
- Killing lab parent PIDs that still own `vphone-cli`
- Trusting `booted=true` or lab `no vphone process`
- Headless launch when sock screenshots or taps are needed
- Parking recover on STARDUST or a retail iPhone
