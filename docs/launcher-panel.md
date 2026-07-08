# Launcher Panel + Bonjour Discovery ([#32](https://github.com/Wawona/Wawona/issues/32))

Design and status for a dedicated connection launcher — an SSH-client-style
control panel for creating and switching between many connections — plus
zero-config discovery of reachable hosts on the local network.

## Goal

Today a connection is configured largely through Settings. Issue #32 asks for a
first-class launcher: users open Wawona, see their saved machines, discover new
ones on the LAN, and start a session in one or two taps — without treating
Settings as the primary connection surface.

## Model reuse (no schema change)

The launcher operates entirely on the existing
[`MachineProfile`](../Sources/WawonaModel/MachineProfile.swift) model
(`id`, `name`, `type`, `sshHost`, `sshUser`, `sshPort`, …) and
[`MachineProfileStore`](../Sources/WawonaModel/MachineProfile.swift). Discovery
does not persist anything on its own: a discovered host is a transient candidate
that, when the user picks it, pre-fills a new `MachineProfile` (type
`remote`/SSH, `sshHost`/`sshPort` from the resolved service) which the store
then owns like any other. This keeps discovery additive and reversible, and
avoids a parallel persistence path.

## Bonjour / mDNS discovery

Discover standard SSH endpoints and (optionally) Wawona-advertised hosts:

- Browse service type `_ssh._tcp` for generic SSH servers.
- Browse service type `_wawona._tcp` for hosts running a Wawona agent that can
  publish a friendly name and preferred launcher.

Resolution yields host + port + TXT metadata, which maps directly onto
`sshHost` / `sshPort` and a suggested `name`.

### Per-platform API mapping

| Platform | Discovery API | Notes |
|----------|---------------|-------|
| macOS / iOS / iPadOS / tvOS | `Network.framework` `NWBrowser` (`bonjour` descriptor) | Preferred over the deprecated `NetServiceBrowser`. Requires `NSBonjourServices` (`_ssh._tcp`, `_wawona._tcp`) and `NSLocalNetworkUsageDescription` in Info.plist; on iOS the system shows the local-network permission prompt on first browse. |
| Android | `NsdManager.discoverServices` (`_ssh._tcp`) | Needs `INTERNET` + (API 33+) `NEARBY_WIFI_DEVICES`; resolve for host/port. |
| Linux | Avahi (`avahi-browse` / D-Bus) when present | Optional; degrade gracefully when Avahi is absent. |
| watchOS | none | Launcher shows saved machines only; no browsing. |

## Panel UX

- Two sections: **Saved** (from `MachineProfileStore`, favorites first) and
  **Discovered on this network** (live `NWBrowser`/`NsdManager` results not
  already matching a saved host by host:port).
- Selecting a saved machine activates it (`activeMachineId`) and launches.
- Selecting a discovered host opens the editor pre-filled from the resolved
  service, so the user only supplies credentials.
- The panel is the default post-launch surface; Settings stays available but is
  no longer the primary path to connect.

## Status and scope

- [x] Design recorded (this doc); model reuse confirmed — no new persisted schema.
- [ ] Apple `NWBrowser` discovery service in `WawonaModel` (publishes an
      observable list of `DiscoveredHost`), unit-testable in isolation.
- [ ] Info.plist `NSBonjourServices` + `NSLocalNetworkUsageDescription` wiring.
- [ ] SwiftUI launcher panel consuming saved + discovered lists.
- [ ] AppKit (`WWNMachines*`) parity entry point.
- [ ] Android `NsdManager` discovery + Compose panel.
- [ ] Linux Avahi discovery (optional, feature-gated).

**Priority:** Post-campaign feature. Discovery is additive and must never be a
prerequisite for manual connection entry, so saved-machine flows keep working if
mDNS is blocked or unavailable.
