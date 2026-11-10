#if os(tvOS)
import SwiftUI

/// Filled capsule that shows tvOS focus. `.plain` drops the system focus
/// platter, so focus is drawn here: white fill, dark label, lift, shadow.
struct WWNTvCapsuleButtonStyle: ButtonStyle {
  var fill: Color = Color.white.opacity(0.18)
  var expands = false

  func makeBody(configuration: Configuration) -> some View {
    WWNTvCapsuleBody(configuration: configuration, fill: fill, expands: expands)
  }
}

private struct WWNTvCapsuleBody: View {
  let configuration: ButtonStyleConfiguration
  let fill: Color
  let expands: Bool
  @Environment(\.isFocused) private var isFocused
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .foregroundStyle(isFocused ? Color.black : Color.white)
      .padding(.horizontal, 24)
      .padding(.vertical, 14)
      .frame(maxWidth: expands ? .infinity : nil)
      .background(Capsule().fill(isFocused ? Color.white : fill))
      .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1))
      .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 14, y: 8)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(.easeOut(duration: 0.15), value: isFocused)
  }
}

/// Full-width list row with a visible focus background (sidebars, tag rows,
/// search results). Size never changes on focus, so rows never shift.
struct WWNTvRowButtonStyle: ButtonStyle {
  var selected = false

  func makeBody(configuration: Configuration) -> some View {
    WWNTvRowBody(configuration: configuration, selected: selected)
  }
}

private struct WWNTvRowBody: View {
  let configuration: ButtonStyleConfiguration
  let selected: Bool
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    configuration.label
      .foregroundStyle(isFocused ? Color.black : Color.primary)
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(background)
      )
      .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 10, y: 6)
      .animation(.easeOut(duration: 0.15), value: isFocused)
  }

  private var background: Color {
    if isFocused { return Color.white }
    if selected { return Color.white.opacity(0.16) }
    return Color.clear
  }
}

/// Color swatch with a white focus ring and lift (tag editor palette).
struct WWNTvSwatchButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    WWNTvSwatchBody(configuration: configuration)
  }
}

private struct WWNTvSwatchBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    configuration.label
      .padding(6)
      .overlay(Circle().stroke(Color.white, lineWidth: isFocused ? 5 : 0))
      .scaleEffect(isFocused ? 1.12 : 1)
      .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 10, y: 6)
      .animation(.easeOut(duration: 0.15), value: isFocused)
  }
}

/// Filter chip whose label already draws its own capsule. Adds a white ring
/// and lift on focus without changing layout size.
struct WWNTvChipButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    WWNTvChipBody(configuration: configuration)
  }
}

private struct WWNTvChipBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    configuration.label
      .overlay(Capsule().strokeBorder(Color.white, lineWidth: isFocused ? 4 : 0))
      .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.1 : 1))
      .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 10, y: 6)
      .animation(.easeOut(duration: 0.15), value: isFocused)
  }
}
#endif
