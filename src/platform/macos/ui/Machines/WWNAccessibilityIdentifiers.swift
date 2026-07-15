import SwiftUI

/// Stable accessibility identifiers for Apple UI (agent-device / XCUITest).
/// Prefer `id="wwn.…"` selectors; keep human `accessibilityLabel` for `label="…"`.
enum WWNA11y {
  static let welcomeRoot = "wwn.welcome.root"
  static let welcomeContinue = "wwn.welcome.continue"

  static let machinesRoot = "wwn.machines.root"
  static let machinesTitle = "wwn.machines.title"
  static let machinesSettings = "wwn.machines.settings"
  static let machinesAdd = "wwn.machines.add"
  static let machinesFilter = "wwn.machines.filter"
  static let machinesStart = "wwn.machines.start"
  static let machinesStop = "wwn.machines.stop"
  static let machinesFocus = "wwn.machines.focus"
  static let machinesEdit = "wwn.machines.edit"
  static let machinesDelete = "wwn.machines.delete"

  static func machinesCard(_ machineId: String) -> String {
    "wwn.machines.card.\(machineId)"
  }

  static let settingsRoot = "wwn.settings.root"
  static let settingsDisplay = "wwn.settings.display"
  static let settingsDone = "wwn.settings.done"

  static let compositorSurface = "wwn.compositor.surface"

  static let watchSettings = "wwn.watch.settings"
  static let watchAdd = "wwn.watch.add"
  static let watchConnect = "wwn.watch.connect"
  static let watchDisconnect = "wwn.watch.disconnect"
  static let watchStop = "wwn.watch.stop"
}

extension View {
  /// Attach a stable identifier and optional human-readable label.
  @ViewBuilder
  func wwnA11y(_ id: String, label: String? = nil) -> some View {
    if let label {
      self.accessibilityIdentifier(id).accessibilityLabel(label)
    } else {
      self.accessibilityIdentifier(id)
    }
  }
}
