import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
