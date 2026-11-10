import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Machine detail after selecting a grid / list card. Owns Start/Stop/Focus/
/// Edit/Delete plus Tags and Pin. Grid cards stay display-only.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNMachineDetailView: View {
  let profile: WWNMachineProfile
  let status: WWNMachineTransientStatus
  let thumbnailImage: WWNPlatformImage?
  let typeLabel: String
  let scopeLabel: String
  let subtitle: String
  let summary: String
  let launchSupported: Bool
  let isActive: Bool
  let isRunning: Bool
  let isPinned: Bool
  let pinLimitReached: Bool
  let tags: [WWNMachineTag]
  let allTags: [WWNMachineTag]
  let onBack: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onConnect: () -> Void
  let onStop: () -> Void
  let onFocus: () -> Void
  let onTogglePin: () -> Void
  let onToggleTag: (WWNMachineTag) -> Void
  let onCreateTag: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  private var descriptor: String {
    WWNA11y.machinesDescriptor(name: profile.name, subtitle: subtitle)
  }

  private var isPreparing: Bool { status == .preparing }

  var body: some View {
    #if os(tvOS)
    tvBody
    #else
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        headerBanner
        statusRow
        summaryText

        MachineActionBar(items: actionItems, layout: Self.actionLayout)

        tagsSection

        pinRow
      }
      .padding(20)
      .frame(maxWidth: 720, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .backport.navigationTitle(
      profile.name.isEmpty ? "Machine" : profile.name,
      inline: true
    )
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Back", action: onBack)
          .accessibilityIdentifier(WWNA11y.machinesDetailBack)
          .accessibilityLabel("Back to Machines")
      }
    }
    .wwnA11y(WWNA11y.machinesDetail, label: descriptor)
    #endif
  }

  private var summaryText: some View {
    Text(summary)
      .font(.body)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  #if os(tvOS)
  /// 10-foot: banner + facts on the left, actions + tags + pin on the right.
  /// The banner carries the only title (no navigation title).
  private var tvBody: some View {
    ScrollView {
      HStack(alignment: .top, spacing: 60) {
        VStack(alignment: .leading, spacing: 32) {
          headerBanner
          statusRow
          summaryText
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 32) {
          MachineActionBar(items: actionItems, layout: .stack)
            .focusSection()
          tagsSection
            .focusSection()
          pinRow
        }
        .frame(width: 520, alignment: .topLeading)
      }
      .padding(.horizontal, 60)
      .padding(.vertical, 40)
      .frame(maxWidth: 1400, alignment: .topLeading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .scrollClipDisabled()
    .onExitCommand(perform: onBack)
    .wwnA11y(WWNA11y.machinesDetail, label: descriptor)
  }
  #endif

  private static var actionLayout: MachineActionBarLayout {
    #if os(tvOS) || os(watchOS)
    .stack
    #else
    .flow
    #endif
  }

  // MARK: - Banner

  private var bannerHeight: CGFloat {
    #if os(tvOS)
    300
    #else
    120
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

      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.black.opacity(0.28))
        .frame(height: bannerHeight)

      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
              .font(.title2.weight(.bold))
              .foregroundStyle(.white)
              .lineLimit(2)
            ForEach(tags.prefix(4)) { tag in
              WWNTagDot(colorHex: tag.colorHex, size: 9)
                .help(tag.name)
            }
          }
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(2)
        }
        Spacer()
        if isPinned {
          Image(systemName: "pin.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(8)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      .padding(.horizontal, 16)
    }
    .frame(height: bannerHeight)
    .clipShape(bannerShape)
  }

  private var statusRow: some View {
    HStack(spacing: 8) {
      Label(status.title, systemImage: statusSymbol)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(statusColor)
      Spacer(minLength: 4)
      MachineStatusChip(text: scopeLabel.uppercased())
      MachineStatusChip(text: typeLabel.uppercased())
      if isActive {
        MachineStatusChip(text: "ACTIVE")
      }
    }
  }

  // MARK: - Actions

  private var actionItems: [MachineActionItem] {
    var items: [MachineActionItem] = []
    if isRunning {
      items.append(
        MachineActionItem(
          title: "Focus",
          systemImage: "scope",
          accessibilityID: WWNA11y.machinesFocus,
          accessibilityLabel: "Focus \(descriptor)",
          action: onFocus
        )
      )
      items.append(
        MachineActionItem(
          title: "Stop",
          systemImage: "stop.fill",
          role: .destructive,
          prominent: true,
          tint: .red,
          accessibilityID: WWNA11y.machinesStop,
          accessibilityLabel: "Stop \(descriptor)",
          action: onStop
        )
      )
    } else if isPreparing {
      items.append(
        MachineActionItem(
          title: "Starting…",
          systemImage: "gearshape.2",
          prominent: true,
          enabled: false,
          accessibilityID: WWNA11y.machinesStart,
          accessibilityLabel: "Starting \(descriptor)",
          action: {}
        )
      )
    } else {
      items.append(
        MachineActionItem(
          title: "Start",
          systemImage: "play.fill",
          prominent: true,
          enabled: launchSupported,
          accessibilityID: WWNA11y.machinesStart,
          accessibilityLabel: "Start \(descriptor)",
          action: onConnect
        )
      )
    }
    items.append(
      MachineActionItem(
        title: "Edit",
        systemImage: "slider.horizontal.3",
        accessibilityID: WWNA11y.machinesEdit,
        accessibilityLabel: "Edit \(descriptor)",
        action: onEdit
      )
    )
    items.append(
      MachineActionItem(
        title: "Delete",
        systemImage: "trash",
        role: .destructive,
        enabled: !isRunning && !isPreparing,
        accessibilityID: WWNA11y.machinesDelete,
        accessibilityLabel: "Delete \(descriptor)",
        action: {
          onDelete()
          onBack()
        }
      )
    )
    return items
  }

  // MARK: - Tags / Pin

  private var tagsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Tags")
        .font(.headline)
      if allTags.isEmpty {
        Text("No tags yet. Create one to organize machines.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(allTags) { tag in
          let assigned = tags.contains { $0.id == tag.id }
          Button {
            onToggleTag(tag)
          } label: {
            HStack(spacing: 10) {
              WWNTagDot(colorHex: tag.colorHex, size: 12)
              // tvOS: inherit the row style's focus-aware color.
              #if os(tvOS)
              Text(tag.name)
              #else
              Text(tag.name)
                .foregroundStyle(.primary)
              #endif
              Spacer()
              if assigned {
                Image(systemName: "checkmark")
                  .font(.body.weight(.semibold))
                  #if !os(tvOS)
                  .foregroundStyle(.secondary)
                  #endif
              }
            }
            #if !os(tvOS)
            .padding(.vertical, 6)
            #endif
            .contentShape(Rectangle())
          }
          #if os(tvOS)
          .buttonStyle(WWNTvRowButtonStyle(selected: assigned))
          #else
          .buttonStyle(.plain)
          #endif
          .accessibilityIdentifier(WWNA11y.machinesTagFilter)
          .accessibilityLabel("Tag \(tag.name)")
          .accessibilityAddTraits(assigned ? .isSelected : [])
        }
      }
      Button(action: onCreateTag) {
        Label("Create Tag…", systemImage: "plus")
      }
      #if os(tvOS)
      .buttonStyle(WWNTvCapsuleButtonStyle())
      #endif
      .accessibilityIdentifier(WWNA11y.machinesTagCreate)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(tagSectionFill)
    )
  }

  private var pinRow: some View {
    Button(action: onTogglePin) {
      Label(
        isPinned ? "Unpin" : "Pin",
        systemImage: isPinned ? "pin.slash" : "pin"
      )
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    #if os(tvOS)
    .buttonStyle(WWNTvCapsuleButtonStyle(expands: true))
    #endif
    .disabled(!isPinned && pinLimitReached)
    .accessibilityIdentifier(WWNA11y.machinesPin)
    .accessibilityLabel(isPinned ? "Unpin \(descriptor)" : "Pin \(descriptor)")
  }

  private var tagSectionFill: Color {
    #if os(macOS)
    Color(nsColor: .controlBackgroundColor)
    #elseif os(tvOS)
    Color.white.opacity(0.08)
    #else
    Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
    #endif
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

  private var statusSymbol: String {
    switch status {
    case .connected: return "checkmark.circle.fill"
    case .connecting: return "arrow.triangle.2.circlepath.circle.fill"
    case .preparing: return "gearshape.2.fill"
    case .degraded: return "exclamationmark.triangle.fill"
    case .error: return "xmark.octagon.fill"
    case .disconnected: return "pause.circle.fill"
    }
  }
}
