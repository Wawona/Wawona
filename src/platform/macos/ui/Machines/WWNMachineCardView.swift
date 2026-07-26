import SwiftUI

struct WWNMachineCardView: View {
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
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onConnect: () -> Void
  let onStop: () -> Void
  let onFocus: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerBanner

      HStack {
        statusBadge
        Spacer()
        HStack(spacing: 6) {
          chip(scopeLabel.uppercased())
          chip(typeLabel.uppercased())
          if isActive {
            chip("ACTIVE")
          }
        }
      }

      Text(summary)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(3)

      HStack(spacing: 8) {
        actionButtons
      }
      .controlSize(.small)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        #if os(macOS)
        // Solid fill: ultraThinMaterial forces expensive opaque-region
        // recalculation on every NSWindow move (drag lag on Machines).
        .fill(Color(nsColor: .controlBackgroundColor))
        #else
        .fill(Color.white.opacity(0.05))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        #endif
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    #if !os(macOS)
    .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
    .animation(.spring(duration: 0.4, bounce: 0.24), value: status)
    #endif
    .wwnA11yContainer(WWNA11y.machinesCard(profile.machineId), label: descriptor)
  }

  /// What a person reads off this card — see `WWNA11y.machinesDescriptor`.
  private var descriptor: String {
    WWNA11y.machinesDescriptor(name: profile.name, subtitle: subtitle)
  }

  // MARK: - Header Banner

  private var headerBanner: some View {
    let bannerShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    return ZStack {
      if let thumbnailImage {
        #if os(macOS)
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFill()
          .frame(height: 90)
          .clipped()
        #else
        Image(uiImage: thumbnailImage)
          .resizable()
          .scaledToFill()
          .frame(height: 90)
          .clipped()
        #endif
      } else {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(
            LinearGradient(
              colors: [statusColor.opacity(0.32), Color.indigo.opacity(0.18)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(height: 90)
      }

      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.black.opacity(0.10), Color.black.opacity(0.40)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(height: 90)

      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
            .font(.title3.weight(.bold))
            .lineLimit(1)
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: iconName)
          .font(.title2.weight(.bold))
          .foregroundStyle(statusColor)
          .padding(8)
          .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .padding(.horizontal, 12)
    }
    .frame(height: 90)
    .clipShape(bannerShape)
  }

  // MARK: - Action Buttons

  private var actionButtons: some View {
    Group {
      if isRunning {
        Button {
          onFocus()
        } label: {
          Label("Focus", systemImage: "scope")
        }
        .buttonStyle(.bordered)
        .wwnA11y(WWNA11y.machinesFocus, label: "Focus \(descriptor)")

        Button(role: .destructive) {
          onStop()
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .wwnA11y(WWNA11y.machinesStop, label: "Stop \(descriptor)")
      } else {
        Button {
          onConnect()
        } label: {
          Label("Start", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!launchSupported)
        .wwnA11y(WWNA11y.machinesStart, label: "Start \(descriptor)")
      }

      Button {
        onEdit()
      } label: {
        Label("Edit", systemImage: "slider.horizontal.3")
      }
      .buttonStyle(.bordered)
      .wwnA11y(WWNA11y.machinesEdit, label: "Edit \(descriptor)")

      Button(role: .destructive) {
        onDelete()
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .buttonStyle(.bordered)
      .disabled(isRunning)
      .wwnA11y(WWNA11y.machinesDelete, label: "Delete \(descriptor)")
    }
  }

  // MARK: - Computed Properties

  private var iconName: String {
    switch profile.type {
    case kWWNMachineTypeNative:
      return "desktopcomputer"
    case kWWNMachineTypeVirtualMachine:
      return "shippingbox"
    case kWWNMachineTypeContainer:
      return "cube.box"
    case kWWNMachineTypeSSHTerminal:
      return "terminal"
    default:
      return "network"
    }
  }

  private var statusColor: Color {
    switch status {
    case .connected: return .green
    case .connecting: return .blue
    case .degraded: return .orange
    case .error: return .red
    case .disconnected: return .secondary
    }
  }

  private var statusBadge: some View {
    Label(status.title, systemImage: statusSymbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(statusColor)
      .labelStyle(.titleAndIcon)
  }

  private var statusSymbol: String {
    switch status {
    case .connected:
      return "checkmark.circle.fill"
    case .connecting:
      return "arrow.triangle.2.circlepath.circle.fill"
    case .degraded:
      return "exclamationmark.triangle.fill"
    case .error:
      return "xmark.octagon.fill"
    case .disconnected:
      return "pause.circle.fill"
    }
  }

  private func chip(_ text: String) -> some View {
    Text(text)
      .font(.caption2.weight(.bold))
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color.secondary.opacity(0.16), in: Capsule())
  }
}
