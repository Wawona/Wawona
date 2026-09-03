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
  static let machinesStart = "wwn.machines.start"
  static let machinesStop = "wwn.machines.stop"
  static let machinesFocus = "wwn.machines.focus"
  static let machinesEdit = "wwn.machines.edit"
  static let machinesDelete = "wwn.machines.delete"
  static let machinesSort = "wwn.machines.sort"
  static let machinesTagCreate = "wwn.machines.tag.create"
  static let machinesTagName = "wwn.machines.tag.name"
  static let machinesTagFilter = "wwn.machines.tag.filter"

  static let machinesEditor = "wwn.machines.editor"
  static let machinesEditorSave = "wwn.machines.editor.save"
  static let machinesEditorCancel = "wwn.machines.editor.cancel"
  static let machinesEditorName = "wwn.machines.editor.name"
  static let machinesEditorType = "wwn.machines.editor.type"
  static let machinesEditorContainerRef = "wwn.machines.editor.container.ref"
  static let machinesEditorContainerCommand = "wwn.machines.editor.container.command"
  static let machinesEditorContainerDesktop = "wwn.machines.editor.container.desktop"
  static let machinesEditorContainerHub = "wwn.machines.editor.container.hub"
  static let machinesContainerImages = "wwn.machines.container.images"

  static func machinesCard(_ machineId: String) -> String {
    "wwn.machines.card.\(machineId)"
  }

  /// Human label for a card and its actions. Profiles created without a name are
  /// stored as the literal "Unnamed Machine", so the name alone is not
  /// distinguishing. The visible subtitle (what the machine runs, e.g. "OpenGL
  /// Cube") is what a person reads off the card, and it belongs in the label.
  ///
  /// The action *identifiers* stay shared across cards on purpose: several CI
  /// smoke scripts press `id="wwn.machines.start"`. Labels are what disambiguate,
  /// so a specific machine is reachable as `label="Start OpenGL Cube"`.
  static func machinesDescriptor(name: String, subtitle: String) -> String {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedSubtitle.isEmpty {
      return trimmedName.isEmpty ? "Unnamed Machine" : trimmedName
    }
    if trimmedName.isEmpty || trimmedName == "Unnamed Machine" {
      return trimmedSubtitle
    }
    return "\(trimmedName). \(trimmedSubtitle)"
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

  /// Same, for a view that *contains* other labelled elements. A plain
  /// `accessibilityLabel` on a container is inherited by its whole subtree, so
  /// every button inside a machine card came back to XCUITest labelled with the
  /// card's own text. Eleven identical matches, none pressable by name.
  /// `children: .contain` keeps the descendants addressable with their own
  /// labels while the container stays findable.
  func wwnA11yContainer(_ id: String, label: String) -> some View {
    self
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(id)
      .accessibilityLabel(label)
  }
}
