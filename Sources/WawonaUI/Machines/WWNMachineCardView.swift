import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNMachineCardView: View {
    let profile: WWNMachineProfile
    let status: WWNMachineTransientStatus
    let thumbnailImage: WWNPlatformImage?
    let typeLabel: String
    let scopeLabel: String
    let subtitle: String
    let summary: String
    let isActive: Bool
    var isPinned: Bool = false
    var tags: [WWNMachineTag] = []
    /// When non-empty, matching characters in the machine name are highlighted.
    var searchQuery: String = ""
    /// Opens machine detail (Start/Stop/Focus/Edit/Delete + Tags/Pin).
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 12) {
        headerBanner

        HStack(spacing: 6) {
          statusBadge
          Spacer(minLength: 4)
          MachineStatusChip(text: scopeLabel.uppercased())
          MachineStatusChip(text: typeLabel.uppercased())
          if isActive {
            MachineStatusChip(text: "ACTIVE")
          }
        }

        Text(summary)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      #if os(tvOS)
      // `.card` scales its label on focus, so the surface must live inside it.
      .modifier(cardSurface)
      #endif
    }
    #if os(tvOS)
    .buttonStyle(.card)
    #else
    .buttonStyle(.plain)
    .modifier(cardSurface)
    #endif
    // Hard: no `.shadow`, no Liquid Glass elevation on machine cards.
    #if !os(macOS)
    .animation(.spring(duration: 0.4, bounce: 0.24), value: status)
    #endif
    .wwnA11yContainer(WWNA11y.machinesCard(profile.machineId), label: descriptor)
    .accessibilityHint("Opens machine actions")
  }

  private var cardSurface: WWNMachineCardSurface {
    WWNMachineCardSurface(outline: cardOutlineColor)
  }

  /// What a person reads off this card. See `WWNA11y.machinesDescriptor`.
  private var descriptor: String {
    WWNA11y.machinesDescriptor(name: profile.name, subtitle: subtitle)
  }

  // MARK: - Header Banner

  private var bannerHeight: CGFloat {
    #if os(tvOS)
    140
    #else
    90
    #endif
  }

  private var headerBanner: some View {
    let bannerShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    return ZStack {
      if let thumbnailImage {
        #if os(macOS)
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFill()
          .frame(height: bannerHeight)
          .clipped()
        #else
        Image(uiImage: thumbnailImage)
          .resizable()
          .scaledToFill()
          .frame(height: bannerHeight)
          .clipped()
        #endif
      } else {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(
            LinearGradient(
              colors: [statusColor.opacity(0.32), WWNTagPalette.indigo.opacity(0.18)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(height: bannerHeight)
      }

      // Flat scrim only. A bottom-heavy black gradient reads as a drop
      // shadow under the banner on light Machine Configuration cards.
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.black.opacity(0.28))
        .frame(height: bannerHeight)

      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            highlightedName
              .font(.title3.weight(.bold))
              .foregroundStyle(.white)
              .lineLimit(1)
              .truncationMode(.tail)
            // Finder-style tag dots, inline with the machine name.
            ForEach(tags.prefix(4)) { tag in
              WWNTagDot(colorHex: tag.colorHex, size: 9)
                .offset(y: 1)
                .help(tag.name)
                .accessibilityLabel(tag.name)
            }
            if tags.count > 4 {
              Text("+\(tags.count - 4)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityLabel("\(tags.count - 4) more tags")
            }
          }
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        Spacer()
        Image(systemName: iconName)
          .font(.title2.weight(.bold))
          .foregroundStyle(statusColor)
          .padding(8)
          .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        if isPinned {
          Image(systemName: "pin.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(6)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("Pinned")
        }
      }
      .padding(.horizontal, 12)
    }
    .frame(height: bannerHeight)
    .clipShape(bannerShape)
  }

  // MARK: - Computed Properties

  private var cardOutlineColor: Color {
    #if os(macOS)
    Color(nsColor: .separatorColor)
    #elseif os(tvOS)
    Color.white.opacity(0.22)
    #else
    Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.16)
    #endif
  }

  private var iconName: String {
    switch profile.type {
    case kWWNMachineTypeVirtualMachine:
      return "desktopcomputer"
    case kWWNMachineTypeContainer:
      return "shippingbox"
    default:
      switch WWNNativeShellConfiguration.kind(for: profile) {
      case kWWNNativeShellKindTerminal: return "terminal"
      case kWWNNativeShellKindWasm: return "doc.badge.gearshape"
      case kWWNNativeShellKindWaypipe: return "arrow.triangle.2.circlepath"
      default: return "display"
      }
    }
  }

  private var statusColor: Color {
    switch status {
    case .connected: return .green
    case .connecting: return .blue
    case .preparing: return .blue
    case .degraded: return .orange
    case .error: return .red
    case .disconnected: return .secondary
    }
  }

  private var statusBadge: some View {
    Label {
      MachineFittingLabel(
        text: status.title,
        font: .caption.weight(.semibold),
        alignment: .leading
      )
    } icon: {
      Image(systemName: statusSymbol)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(statusColor)
    .labelStyle(.titleAndIcon)
    .lineLimit(1)
    .minimumScaleFactor(0.35)
    .allowsTightening(true)
    .fixedSize(horizontal: false, vertical: true)
    .frame(minWidth: 0)
    .layoutPriority(1)
  }

  private var statusSymbol: String {
    switch status {
    case .connected:
      return "checkmark.circle.fill"
    case .connecting:
      return "arrow.triangle.2.circlepath.circle.fill"
    case .preparing:
      return "gearshape.2.fill"
    case .degraded:
      return "exclamationmark.triangle.fill"
    case .error:
      return "xmark.octagon.fill"
    case .disconnected:
      return "pause.circle.fill"
    }
  }

  /// Machine name with search-term characters emphasized (pastel highlighter).
  @ViewBuilder
  private var highlightedName: some View {
    let display = profile.name.isEmpty ? "Unnamed Machine" : profile.name
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    if query.isEmpty {
      Text(display)
    } else {
      Text(Self.highlightedNameAttributed(
        display,
        query: query,
        highlight: Self.searchHighlightBackground(colorScheme),
        matchForeground: Self.searchHighlightForeground
      ))
    }
  }

}

/// Machine card chrome. Flat fill + hairline only.
/// Never `.shadow` and never `.glassEffect` on iOS/tvOS: Liquid Glass paints a
/// drop-shadow / elevation halo around cards in the Machines grid.
#if os(iOS)
@available(iOS 16.0, *)
#endif
private struct WWNMachineCardMaterial: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    #if os(macOS)
    // Solid fill: ultraThinMaterial / glassEffect force opaque-region work on
    // every NSWindow move (drag lag) and glass draws an elevation halo.
    content.background {
      shape.fill(Color(nsColor: .controlBackgroundColor))
    }
    #elseif os(visionOS)
    content.background {
      shape.fill(Color.white.opacity(0.05))
        .background(.ultraThinMaterial, in: shape)
    }
    #elseif os(iOS)
    content.background {
      shape.fill(Color(UIColor.secondarySystemGroupedBackground))
    }
    #elseif os(tvOS)
    // Flat fill only. Never `.glassEffect` on cards (Adopting Liquid Glass:
    // glass is for navigation chrome, not content cards).
    // tvOS has no secondarySystemBackground; use an opaque dark surface.
    content.background {
      shape.fill(Color(white: 0.14))
    }
    #else
    content.background {
      shape.fill(Color.secondary.opacity(0.12))
    }
    #endif
  }
}

/// Fill, hairline, and clip for one machine card.
#if os(iOS)
@available(iOS 16.0, *)
#endif
private struct WWNMachineCardSurface: ViewModifier {
  let outline: Color

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    content
      .modifier(WWNMachineCardMaterial(cornerRadius: 20))
      .overlay { shape.strokeBorder(outline, lineWidth: 1) }
      .clipShape(shape)
  }
}

#if os(iOS)
@available(iOS 16.0, *)
#endif
extension WWNMachineCardView {
  /// Pastel highlighter fill. Follows light/dark; macOS uses system find highlight.
  static func searchHighlightBackground(_ scheme: ColorScheme) -> Color {
    #if os(macOS)
    // System find/mark color, softened toward pastel.
    Color(nsColor: .findHighlightColor).opacity(scheme == .dark ? 0.55 : 0.70)
    #else
    // Soft systemYellow: cream in light, amber wash in dark (banner-safe).
    if scheme == .dark {
      Color(red: 0.93, green: 0.78, blue: 0.28).opacity(0.50)
    } else {
      Color(red: 1.0, green: 0.94, blue: 0.55).opacity(0.82)
    }
    #endif
  }

  /// Ink on highlighter for contrast on banner and material cards.
  static var searchHighlightForeground: Color {
    Color(red: 0.12, green: 0.12, blue: 0.12)
  }

  /// Fuzzy-matched characters get pastel background (Android Machines parity).
  /// `AttributedString` background is iOS 15+ / macOS 12+; card is iOS 16+.
  static func highlightedNameAttributed(
    _ name: String,
    query: String,
    highlight: Color,
    matchForeground: Color
  ) -> AttributedString {
    let needle = Array(
      query.lowercased().filter { !$0.isWhitespace }
    )
    guard !needle.isEmpty else {
      return AttributedString(name)
    }
    var attributed = AttributedString()
    var needleIndex = 0
    for character in name {
      var piece = AttributedString(String(character))
      if needleIndex < needle.count,
         String(character).lowercased() == String(needle[needleIndex]) {
        piece.backgroundColor = highlight
        piece.foregroundColor = matchForeground
        piece.inlinePresentationIntent = .stronglyEmphasized
        needleIndex += 1
      }
      attributed.append(piece)
    }
    return attributed
  }
}
