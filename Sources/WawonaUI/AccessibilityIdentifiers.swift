import SwiftUI

/// Stable accessibility identifiers shared by WawonaUI (vision / SwiftUI shell).
/// Keep in sync with `WWNA11y` in `src/platform/macos/ui/Machines/`.
enum WawonaA11y {
  static let welcomeRoot = "wwn.welcome.root"
  static let welcomeContinue = "wwn.welcome.continue"
  static let welcomeAddFirst = "wwn.welcome.add_first"

  static let machinesRoot = "wwn.machines.root"
  static let machinesSettings = "wwn.machines.settings"
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

// View.wwnA11y(_:) is defined in
// src/platform/macos/ui/Machines/WWNAccessibilityIdentifiers.swift.
// Wawona-macOS compiles both trees into one module — keep a single extension.
