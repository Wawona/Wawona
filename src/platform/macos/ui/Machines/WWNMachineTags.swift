import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Tag model

/// Finder-style color tag for machines. Identity is a stable UUID so tag
/// renames keep machine assignments intact.
struct WWNMachineTag: Identifiable, Codable, Hashable {
  let id: String
  var name: String
  var colorHex: String
}

// MARK: - Palette

/// Color palette offered when creating / editing tags.
enum WWNTagPalette {
  static let colors: [Color] = [
    .red, .orange, .yellow, .green, .mint, .teal,
    .blue, .indigo, .purple, .pink, .brown, .gray,
  ]

  static func hex(for color: Color) -> String {
    #if os(macOS)
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    #else
    let resolved = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    #endif
  }

  static func color(fromHex hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
      return .gray
    }
    return Color(
      red: Double((value >> 16) & 0xFF) / 255.0,
      green: Double((value >> 8) & 0xFF) / 255.0,
      blue: Double(value & 0xFF) / 255.0
    )
  }
}

// MARK: - Tag store

/// Shared store for machine tags + per-machine assignments. Persists to
/// UserDefaults (per app) so macOS / iOS builds keep their own tag sets,
/// matching the rest of the machine preferences.
final class WWNMachineTagStore: ObservableObject {
  static let shared = WWNMachineTagStore()

  @Published private(set) var tags: [WWNMachineTag] = []
  /// machineId -> tag ids (insertion order preserved).
  @Published private(set) var tagIdsByMachine: [String: [String]] = [:]

  private let tagsDefaultsKey = "wawona.machines.tags"
  private let assignmentsDefaultsKey = "wawona.machines.tagAssignments"

  private init() {
    load()
  }

  // MARK: - Reads

  func tags(for machineId: String) -> [WWNMachineTag] {
    let ids = tagIdsByMachine[machineId] ?? []
    return tags.filter { ids.contains($0.id) }
  }

  func isAssigned(_ tagId: String, to machineId: String) -> Bool {
    tagIdsByMachine[machineId]?.contains(tagId) ?? false
  }

  // MARK: - Writes

  @discardableResult
  func createTag(name: String, colorHex: String) -> WWNMachineTag {
    let tag = WWNMachineTag(
      id: UUID().uuidString,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      colorHex: colorHex
    )
    guard !tag.name.isEmpty else { return tag }
    tags.append(tag)
    persist()
    return tag
  }

  func updateTag(_ tag: WWNMachineTag) {
    guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
    tags[index] = WWNMachineTag(
      id: tag.id,
      name: tag.name.trimmingCharacters(in: .whitespacesAndNewlines),
      colorHex: tag.colorHex
    )
    persist()
  }

  func deleteTag(id: String) {
    tags.removeAll { $0.id == id }
    for machineId in tagIdsByMachine.keys {
      tagIdsByMachine[machineId]?.removeAll { $0 == id }
    }
    persist()
  }

  func setAssigned(_ assigned: Bool, tag: WWNMachineTag, to machineId: String) {
    var ids = tagIdsByMachine[machineId] ?? []
    if assigned {
      if !ids.contains(tag.id) {
        ids.append(tag.id)
      }
    } else {
      ids.removeAll { $0 == tag.id }
    }
    if ids.isEmpty {
      tagIdsByMachine.removeValue(forKey: machineId)
    } else {
      tagIdsByMachine[machineId] = ids
    }
    persist()
  }

  /// Drop assignments for machines that no longer exist.
  func pruneAssignments(keeping machineIds: Set<String>) {
    let stale = tagIdsByMachine.keys.filter { !machineIds.contains($0) }
    guard !stale.isEmpty else { return }
    for machineId in stale {
      tagIdsByMachine.removeValue(forKey: machineId)
    }
    persist()
  }

  // MARK: - Persistence

  private func load() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: tagsDefaultsKey),
       let decoded = try? JSONDecoder().decode([WWNMachineTag].self, from: data) {
      tags = decoded
    }
    if let data = defaults.data(forKey: assignmentsDefaultsKey),
       let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
      tagIdsByMachine = decoded
    }
  }

  private func persist() {
    let defaults = UserDefaults.standard
    if let data = try? JSONEncoder().encode(tags) {
      defaults.set(data, forKey: tagsDefaultsKey)
    }
    if let data = try? JSONEncoder().encode(tagIdsByMachine) {
      defaults.set(data, forKey: assignmentsDefaultsKey)
    }
  }
}

// MARK: - Shared tag UI

/// Small colored dot used in the sidebar, menus, and on machine cards.
struct WWNTagDot: View {
  let colorHex: String
  var size: CGFloat = 10

  var body: some View {
    Circle()
      .fill(WWNTagPalette.color(fromHex: colorHex))
      .frame(width: size, height: size)
  }
}

/// Create / edit sheet for one tag: name field + Finder-style color palette.
struct WWNTagEditorSheet: View {
  /// When nil the sheet creates a new tag; otherwise it edits in place.
  let tag: WWNMachineTag?
  let onSave: (String, String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String = ""
  @State private var colorHex: String = WWNTagPalette.hex(for: .blue)

  init(tag: WWNMachineTag?, onSave: @escaping (String, String) -> Void) {
    self.tag = tag
    self.onSave = onSave
    _name = State(initialValue: tag?.name ?? "")
    _colorHex = State(initialValue: tag?.colorHex ?? WWNTagPalette.hex(for: .blue))
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(tag == nil ? "New Tag" : "Edit Tag")
        .font(.headline)

      TextField("Tag name", text: $name)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(WWNA11y.machinesTagName)

      Text("Color")
        .font(.subheadline.weight(.semibold))

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 10)], spacing: 10) {
        ForEach(WWNTagPalette.colors, id: \.self) { color in
          let hex = WWNTagPalette.hex(for: color)
          Button {
            colorHex = hex
          } label: {
            Circle()
              .fill(color)
              .frame(width: 26, height: 26)
              .overlay {
                if colorHex == hex {
                  Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                }
              }
          }
          .buttonStyle(.plain)
        }
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save") {
          guard !trimmedName.isEmpty else { return }
          onSave(trimmedName, colorHex)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(trimmedName.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 340)
  }
}
