import SwiftUI

/// Stable accessibility identifiers shared by WawonaUI (vision / SwiftUI shell).
/// Keep in sync with `WWNA11y` in `src/platform/macos/ui/Machines/`.
enum WawonaA11y {
  static let welcomeRoot = "wwn.welcome.root"
  static let welcomeContinue = "wwn.welcome.continue"
  static let welcomeAddFirst = "wwn.welcome.add_first"

  static let machinesRoot = "wwn.machines.root"
  static let machinesSettings = "wwn.machines.settings"
  static let machinesImages = "wwn.machines.images"
  static let machinesAdd = "wwn.machines.add"
  static let machinesStart = "wwn.machines.start"
  static let machinesConnect = "wwn.machines.connect"
  static let machinesEdit = "wwn.machines.edit"
  static let machinesDelete = "wwn.machines.delete"

  static func machinesCard(_ machineId: String) -> String {
    "wwn.machines.card.\(machineId)"
  }

  static let settingsRoot = "wwn.settings.root"
  static let settingsDisplay = "wwn.settings.display"
}

#if SWIFT_PACKAGE
extension View {
  /// SPM-only. App targets compile `WWNAccessibilityIdentifiers.swift` instead.
  func wwnA11y(_ id: String, label: String? = nil) -> some View {
    self
      .accessibilityIdentifier(id)
      .accessibilityLabel(label ?? id)
  }
}
#endif
