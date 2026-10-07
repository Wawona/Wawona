# Physical-iPhone CarPlay lab

From the Wawona product repository on macOS:

```sh
nix run .#carplay
```

The command opens a terminal menu. Use **Up/Down** and **Enter** to choose:

- **Pair iPhone**: select a discovered device, or choose Enter address manually.
  Pairing progress and the confirmation code stay visible. Success and failure
  remain on screen until you press Enter; cancellation is reported separately.
- **Start CarPlay / Stop CarPlay**: one menu item controls the receiver.
- **Open viewer**: open the private browser session once CarPlay is ready.
- **Help**: view the Mac and iPhone preparation steps.
- **Quit**: stop the receiver and restore your terminal.

Pair your iPhone first, then start CarPlay. Setup runs automatically when needed.
You can rebuild manually with `nix run .#carplay -- setup`.
Press **Q** (or Ctrl+C) to quit. **O** and **S** remain shortcut keys for opening
and stopping. Viewer tokens stay in memory and are not rendered in the terminal.
The selected iPhone address is saved privately and passed to the receiver,
so a custom phone name does not depend on upstream automatic discovery.
Existing `setup`, `doctor`, `scan`, `pair ADDRESS`, and `run [FLAGS]` commands
remain available. `run` uses the original foreground workflow for diagnostics.

This developer tool builds [Playport](https://github.com/youcci/playport) at
`9a0882dd0ffe48e467b59d58b12d81391df55ade`, builds its browser viewer and native
Bluetooth bridge, and privately imports the experimental accessory identity
from the DiPlay v0.2.7 release documented by upstream. Nix supplies Java 21,
Node, Git, curl, and unzip. Xcode Command Line Tools must be installed.
Choose Pair iPhone if your phone is not paired.
Builds and downloads happen at runtime; accessory credentials never enter a
Nix derivation or the Wawona application bundle.

## First connection

1. Enable Bluetooth on Mac and iPhone. Join both to the same Wi-Fi network.
2. Turn off macOS System Settings > General > AirDrop & Handoff > AirPlay Receiver.
3. Allow Bluetooth access for your terminal in Privacy & Security. Allow Java
   incoming connections if macOS asks.
4. Build once and find your phone, with iPhone Settings > Bluetooth open:

   ```sh
   nix run .#carplay -- setup
   nix run .#carplay -- scan
   nix run .#carplay -- pair AA:BB:CC:DD:EE:FF
   ```

   Replace the address with the scan result. Confirm the pairing code on iPhone.
   An already paired phone can skip pairing; do not force re-pair routinely.
5. Run `nix run .#carplay`, choose Start CarPlay, and enter the Wi-Fi details.
   Password input is hidden. Leave it blank if iPhone already knows the network.
6. Press O to open the HTTPS viewer in a browser supporting
   WebCodecs. Accept the local self-signed certificate warning. Accept the
   CarPlay prompt on iPhone; enter `3939` if asked for a PIN.

The receiver is called **Wawona CarPlay Lab** on iPhone. Stop it with Ctrl+C.
Bluetooth privacy prompts and iPhone confirmation require human action.

## Commands

```sh
nix run .#carplay -- doctor
nix run .#carplay -- run --width 1920 --height 720 --fps 60
nix run .#carplay -- run --bt-address AA:BB:CC:DD:EE:FF
```

`doctor` checks local build outputs and identity presence; it does not prove
Bluetooth permissions, certificate validity, or a live iPhone session.
`setup` can be rerun after an interrupted build. The lab source is pinned;
it refuses a different revision rather than resetting developer changes.

## Credentials and repository boundaries

Everything private lives under `~/.playport/wawona-lab/`, outside Git:

- `identity/offline-mfi/`: private accessory key and certificate, owner-only files.
- `state/`: pairing, TLS, and saved receiver settings.
- `launch-PID.args`: owner-only Java argument file, unlinked before Java starts.
- `src/`: pinned Playport checkout and runtime build outputs, containing no
  imported accessory identity.

No credential is embedded in source, a flake input, a store path, shell history,
or the Java process argument list. The launcher rejects credential and private
path flags. It sets a private umask before upstream creates runtime state.
Java reads its argument file through an inherited descriptor after unlinking.
A kill during the brief file-creation step may leave `launch-PID.args`; delete
it locally before sharing diagnostics. Never upload this directory,
index it into RAG, attach it to an issue, or print identity file contents.
The viewer URL contains a session access token; keep it out of shared logs and
screenshots. Do not expose the receiver beyond a trusted development LAN.

You can supply your own matching identity by placing the two files at the
private identity path before setup. Setup preserves an existing complete pair.
The upstream experimental identity can be revoked by Apple. Importing it for
local tests does not authorize redistribution. Wawona does not ship it.

## Testing Wawona

Install the development build on your physical iPhone, then connect this
receiver. Wawona already declares `WWNCarPlaySceneDelegate` in its scene
manifest. That scene remains dormant unless the installed app's signing profile
and entitlements include the Apple-granted CarPlay capability. Playport emulates
the receiver; it does not grant an app entitlement or make Wawona appear in
CarPlay by itself. See `src/resources/app-bundle/Wawona-CarPlay.entitlements.template`.
Do not add the template entitlement to ordinary builds without a matching profile.

Check scene connection/disconnection logs, machine status, running clients,
reconnection, and display presets. While the car scene is connected the seat
is single-touch: one `wl_touch` slot, also sent as `wl_pointer`. Choosing a
row starts that machine. Pixels stay on the phone. A wired or AirPlay display
uses touchpad mode instead, and the phone is the controller. This is a
physical-iPhone lab, independent of vphone-cli. Upstream supports wireless
CarPlay on macOS, not USB or Linux.

## Scan does not reach the address prompt

The launcher bounds Bluetooth scans to 15 seconds and shows a live countdown. macOS device-name resolution
can delay the upstream inquiry-complete callback after devices appear. The lab
stops a stalled scan and lets you select from the devices already discovered.
The foreground `run` command instead prompts for the address. Pairing is bounded to 75 seconds and reports a timeout on failure.

If an older running launcher remains stuck, press Ctrl+C and rerun it. If you
already know the iPhone address, skip discovery with `pair ADDRESS`. Verify
the address on iPhone in Settings > General > About > Bluetooth.
