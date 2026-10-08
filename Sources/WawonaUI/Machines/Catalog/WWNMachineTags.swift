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
  static var colors: [Color] {
    if #available(iOS 15.0, *) {
      return [.red, .orange, .yellow, .green, .mint, .teal,
              .blue, .indigo, .purple, .pink, .brown, .gray]
    }
    return [.red, .orange, .yellow, .green,
            Color(red: 0, green: 0.78, blue: 0.65), Color(red: 0.19, green: 0.69, blue: 0.78),
            .blue, Color(red: 0.35, green: 0.34, blue: 0.84), .purple, .pink,
            Color(red: 0.64, green: 0.52, blue: 0.37), .gray]
  }

  static var indigo: Color { colors[7] }
  static var teal: Color { colors[5] }

  static func hex(for color: Color) -> String {
    #if os(macOS)
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    #else
    guard #available(iOS 14.0, *) else {
      let hex = ["FF3B30", "FF9500", "FFCC00", "34C759", "00C7A6", "30B0C7",
                 "007AFF", "5957D6", "AF52DE", "FF2D55", "A3855E", "8E8E93"]
      return colors.firstIndex(of: color).map { hex[$0] } ?? "8E8E93"
    }
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

/// Small colored dot used in the sidebar and on machine cards.
struct WWNTagDot: View {
  let colorHex: String
  var size: CGFloat = 10

  var body: some View {
    Circle()
      .fill(WWNTagPalette.color(fromHex: colorHex))
      .frame(width: size, height: size)
  }
}

#if os(macOS)
/// Finder-style tag swatch for `NSMenu` / SwiftUI `Menu` items.
/// Context menus only keep `Label` icons that are real `NSImage`s; a SwiftUI
/// `Circle` is dropped, so colors never appear unless we rasterize here.
/// `isTemplate` must stay false or AppKit tints the swatch to the menu ink.
enum WWNTagSwatchImage {
  static func make(colorHex: String, diameter: CGFloat = 12) -> NSImage {
    let size = NSSize(width: diameter, height: diameter)
    let image = NSImage(size: size, flipped: false) { rect in
      let nsColor = NSColor(WWNTagPalette.color(fromHex: colorHex))
        .usingColorSpace(.sRGB) ?? NSColor(WWNTagPalette.color(fromHex: colorHex))
      nsColor.setFill()
      // Inset slightly so the edge is not clipped by menu icon masks.
      let inset = rect.insetBy(dx: 0.5, dy: 0.5)
      NSBezierPath(ovalIn: inset).fill()
      return true
    }
    image.isTemplate = false
    return image
  }
}
#endif

/// Create / edit sheet for one tag: name field + Finder-style color palette.
struct WWNTagEditorSheet: View {
  /// When nil the sheet creates a new tag; otherwise it edits in place.
  let tag: WWNMachineTag?
  let onSave: (String, String) -> Void

  @Environment(\.presentationMode) private var presentationMode
  private func dismiss() { presentationMode.wrappedValue.dismiss() }
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

      WawonaTextField("Tag name", text: $name)
        .textFieldStyle(.roundedBorder)
        .accessibility(identifier: WWNA11y.machinesTagName)

      Text("Color")
        .font(.subheadline.weight(.semibold))

      if #available(iOS 14.0, macOS 11.0, tvOS 14.0, visionOS 1.0, *) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 10)], spacing: 10) {
          colorButtons(WWNTagPalette.colors)
        }
      } else {
        VStack(spacing: 10) {
          HStack(spacing: 10) { colorButtons(Array(WWNTagPalette.colors.prefix(6))) }
          HStack(spacing: 10) { colorButtons(Array(WWNTagPalette.colors.suffix(6))) }
        }
      }

      HStack {
        Spacer()
        WawonaButton("Cancel") { dismiss() }
          #if !os(tvOS)
          .backport.cancelShortcut()
          #endif
        WawonaButton("Save") {
          guard !trimmedName.isEmpty else { return }
          onSave(trimmedName, colorHex)
          dismiss()
        }
        #if !os(tvOS)
        .backport.defaultShortcut()
        #endif
        .backport.borderedButton(prominent: true)
        .disabled(trimmedName.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 340)
  }
  private func colorButtons(_ colors: [Color]) -> some View {
        ForEach(colors, id: \.self) { color in
          let hex = WWNTagPalette.hex(for: color)
          WawonaButton {
            colorHex = hex
          } label: {
            Circle()
              .fill(color)
              .frame(width: 26, height: 26)
              .backport.overlay {
                if colorHex == hex {
                  Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                }
              }
          }
          .buttonStyle(.plain)
        }
  }

}
