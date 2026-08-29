import SwiftUI

/// One machine action (Start, Stop, Focus, Edit, Delete). Title stays on a
/// single line. The bar wraps *buttons* onto the next row when the card is
/// narrow. It never wraps letters inside a button.
struct MachineActionItem: Identifiable {
  let id: String
  var title: String
  var systemImage: String
  var role: ButtonRole?
  var prominent: Bool
  var enabled: Bool
  var tint: Color?
  var accessibilityID: String
  var accessibilityLabel: String
  var action: () -> Void

  init(
    title: String,
    systemImage: String,
    role: ButtonRole? = nil,
    prominent: Bool = false,
    enabled: Bool = true,
    tint: Color? = nil,
    accessibilityID: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) {
    self.id = accessibilityID + "." + title
    self.title = title
    self.systemImage = systemImage
    self.role = role
    self.prominent = prominent
    self.enabled = enabled
    self.tint = tint
    self.accessibilityID = accessibilityID
    self.accessibilityLabel = accessibilityLabel
    self.action = action
  }
}

enum MachineActionBarLayout {
  /// Fit as many one-line chips as the width allows, then wrap to the next row.
  case flow
  /// One full-width one-line button per row (tvOS, watchOS).
  case stack
}

struct MachineActionBar: View {
  let items: [MachineActionItem]
  var layout: MachineActionBarLayout = MachineActionBar.defaultLayout

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      switch layout {
      case .stack:
        VStack(spacing: stackSpacing) {
          ForEach(items) { item in
            MachineActionChip(item: item, expands: true)
          }
        }
        .frame(maxWidth: .infinity)
      case .flow:
        ViewThatFits(in: .horizontal) {
          HStack(spacing: chipSpacing) {
            ForEach(items) { item in
              MachineActionChip(item: item, expands: false)
            }
          }
          MachineActionFlow(spacing: chipSpacing, lineSpacing: chipSpacing) {
            ForEach(items) { item in
              MachineActionChip(item: item, expands: false)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  static var defaultLayout: MachineActionBarLayout {
    #if os(tvOS) || os(watchOS)
    .stack
    #else
    .flow
    #endif
  }

  private var chipSpacing: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 10 : 8
  }

  private var stackSpacing: CGFloat {
    #if os(tvOS)
    22
    #else
    dynamicTypeSize.isAccessibilitySize ? 10 : 8
    #endif
  }
}

private struct MachineActionChip: View {
  let item: MachineActionItem
  var expands: Bool

  var body: some View {
    Group {
      if item.prominent {
        Button(role: item.role, action: item.action) { label }
          .buttonStyle(.borderedProminent)
          .tint(item.tint)
      } else {
        Button(role: item.role, action: item.action) { label }
          .buttonStyle(.bordered)
          .tint(item.tint)
      }
    }
    .disabled(!item.enabled)
    .controlSize(controlSize)
    .fixedSize(horizontal: !expands, vertical: true)
    .frame(maxWidth: expands ? .infinity : nil)
    .accessibilityIdentifier(item.accessibilityID)
    .accessibilityLabel(item.accessibilityLabel)
  }

  private var label: some View {
    HStack(spacing: 5) {
      Image(systemName: item.systemImage)
      Text(item.title)
        .lineLimit(1)
        .truncationMode(.tail)
        .allowsTightening(true)
    }
    .font(labelFont)
  }

  private var labelFont: Font {
    #if os(tvOS)
    .title3.weight(.semibold)
    #elseif os(watchOS)
    .body.weight(.semibold)
    #else
    .subheadline.weight(.semibold)
    #endif
  }

  private var controlSize: ControlSize {
    #if os(tvOS)
    .large
    #elseif os(watchOS)
    .regular
    #else
    .small
    #endif
  }
}

/// One-line badge text that shrinks to the width it is given. Never wraps
/// onto a second line and never shows an ellipsis.
struct MachineFittingLabel: View {
  let text: String
  var font: Font
  var alignment: TextAlignment = .center

  var body: some View {
    Text(text)
      .font(font)
      .lineLimit(1)
      .minimumScaleFactor(0.35)
      .allowsTightening(true)
      .multilineTextAlignment(alignment)
      .fixedSize(horizontal: false, vertical: true)
      .frame(minWidth: 0)
  }
}

/// Capsule chip for Local / Remote / Native / Container / Active on a machine
/// card. Shares width with siblings and scales the label to stay inside the
/// module.
struct MachineStatusChip: View {
  let text: String
  var font: Font = .caption2.weight(.bold)

  var body: some View {
    MachineFittingLabel(text: text, font: font)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(minWidth: 0)
      .background(Color.secondary.opacity(0.16), in: Capsule())
      .layoutPriority(1)
  }
}

/// Wraps child views onto additional rows. Each child keeps its intrinsic
/// width, so a button title cannot be squeezed into multiple lines.
struct MachineActionFlow: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 8

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    arrange(proposal: proposal, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let plan = arrange(proposal: proposal, subviews: subviews)
    for (index, subview) in subviews.enumerated() {
      let cell = plan.frames[index]
      subview.place(
        at: CGPoint(x: bounds.minX + cell.origin.x, y: bounds.minY + cell.origin.y),
        proposal: ProposedViewSize(cell.size)
      )
    }
  }

  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (
    size: CGSize, frames: [CGRect]
  ) {
    let maxWidth = proposal.width ?? .infinity
    var frames: [CGRect] = []
    frames.reserveCapacity(subviews.count)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var usedWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0 && maxWidth.isFinite && x + size.width > maxWidth {
        x = 0
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      usedWidth = max(usedWidth, x - spacing)
    }

    let width = maxWidth.isFinite ? min(usedWidth, maxWidth) : usedWidth
    return (CGSize(width: width, height: y + rowHeight), frames)
  }
}
