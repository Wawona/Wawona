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
  static let machinesStop = "wwn.machines.stop"
  static let machinesFocus = "wwn.machines.focus"
  static let machinesConnect = "wwn.machines.connect"
  static let machinesEdit = "wwn.machines.edit"
  static let machinesDelete = "wwn.machines.delete"

  static let machinesEditor = "wwn.machines.editor"
  static let machinesEditorSave = "wwn.machines.editor.save"
  static let machinesEditorCancel = "wwn.machines.editor.cancel"
  static let machinesEditorName = "wwn.machines.editor.name"
  static let machinesEditorType = "wwn.machines.editor.type"
  static let machinesEditorContainerRef = "wwn.machines.editor.container.ref"
  static let machinesEditorContainerCommand = "wwn.machines.editor.container.command"
  static let machinesEditorContainerDesktop = "wwn.machines.editor.container.desktop"
  static let machinesEditorContainerHub = "wwn.machines.editor.container.hub"

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
