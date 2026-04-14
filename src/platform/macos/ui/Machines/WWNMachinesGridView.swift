import SwiftUI

struct WWNMachinesGridView: View {
  let onConnect: (() -> Void)?
  let onOpenSettings: (() -> Void)?

  @StateObject private var model = WWNMachinesViewModel()
  @State private var editingProfile: WWNMachineProfile?
  @State private var isEditing = false
  @State private var isCreating = false
  @State private var searchQuery = ""
  #if os(iOS)
  @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
  #endif

  var body: some View {
    splitView
      .sheet(isPresented: $isCreating) {
        WWNMachineEditorView(
          title: "Add Machine Profile",
          initial: nil,
          defaultType: model.selectedFilter.defaultMachineType
        ) { profile in
          model.upsert(profile)
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        #endif
      }
      .sheet(isPresented: $isEditing) {
        WWNMachineEditorView(title: "Edit Machine Profile", initial: editingProfile) { profile in
          model.upsert(profile)
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        #endif
      }
      .animation(.spring(duration: 0.42, bounce: 0.26), value: visibleProfiles.count)
  }

  @ViewBuilder
  private var splitView: some View {
    #if os(iOS)
    NavigationSplitView(preferredCompactColumn: $preferredColumn) {
      sidebar
    } detail: {
      detailContent
    }
    #else
    NavigationSplitView {
      sidebar
    } detail: {
      detailContent
    }
    #endif
  }

  private var detailContent: some View {
    detailPane
      .navigationTitle("Machine Configuration")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isCreating = true
          } label: {
            Label("Add Profile", systemImage: "plus")
          }
        }
        if let onOpenSettings {
          ToolbarItem(placement: .automatic) {
            Button("Settings", action: onOpenSettings)
          }
        }
      }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List {
      Section("Machine Scope") {
        ForEach(WWNMachineFilter.allCases) { filter in
          sidebarFilterRow(filter)
        }
      }
      Section("Overview") {
        sidebarOverviewRow(
          title: "Profiles",
          value: "\(model.profiles.count)",
          icon: "square.grid.2x2",
          targetFilter: .all
        )
        sidebarOverviewRow(
          title: "Connected",
          value: "\(model.connectedCount)",
          icon: "wave.3.right.circle",
          targetFilter: .remote
        )
        sidebarOverviewRow(
          title: "Ready",
          value: "\(model.launchableCount)",
          icon: "play.circle",
          targetFilter: .local
        )
      }
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.sidebar)
    #endif
    .navigationTitle("Control Panel")
  }

  @ViewBuilder
  private func sidebarFilterRow(_ filter: WWNMachineFilter) -> some View {
    let isSelected = model.selectedFilter == filter
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        model.selectedFilter = filter
      }
      #if os(iOS)
      preferredColumn = .detail
      #endif
    } label: {
      HStack {
        Label(filter.rawValue, systemImage: filterIcon(filter))
          .foregroundStyle(isSelected ? Color.accentColor : .primary)
        Spacer()
        if isSelected {
          Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.accentColor)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .padding(.horizontal, 4)
    )
  }

  @ViewBuilder
  private func sidebarOverviewRow(title: String, value: String, icon: String, targetFilter: WWNMachineFilter) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        model.selectedFilter = targetFilter
      }
      #if os(iOS)
      preferredColumn = .detail
      #endif
    } label: {
      HStack {
        Label(title, systemImage: icon)
        Spacer()
        Text(value)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Detail

  private var detailPane: some View {
    GeometryReader { proxy in
      let detailWidth = max(proxy.size.width, 320)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          summaryStrip
          searchAndLayoutBar

          if visibleProfiles.isEmpty {
            ContentUnavailableView(
              "No Matching Machines",
              systemImage: "magnifyingglass",
              description: Text("Adjust search/filter settings or add a new machine profile.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
          } else {
            LazyVGrid(columns: gridColumns(for: detailWidth), spacing: 14) {
              ForEach(visibleProfiles, id: \.machineId) { profile in
                let machineStatus = model.status(for: profile.machineId)
                WWNMachineCardView(
                  profile: profile,
                  status: machineStatus,
                  typeLabel: model.machineTypeLabel(for: profile),
                  scopeLabel: model.machineScopeLabel(for: profile),
                  subtitle: model.machineSubtitle(for: profile),
                  summary: model.machineConfigurationSummary(for: profile),
                  launchSupported: model.launchSupported(for: profile),
                  isActive: profile.machineId == model.activeMachineId,
                  isRunning: machineStatus == .connected || machineStatus == .connecting,
                  onEdit: {
                    editingProfile = profile
                    isEditing = true
                  },
                  onDelete: { model.delete(profile) },
                  onConnect: {
                    model.connect(profile) {
                      onConnect?()
                    }
                  },
                  onStop: { model.disconnect(profile) }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
              }
            }
          }
        }
        .padding(16)
        .frame(maxWidth: 1320, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }

  // MARK: - Grid Layout

  private func gridColumns(for width: CGFloat) -> [GridItem] {
    let minCardWidth: CGFloat
    #if os(iOS)
    minCardWidth = width < 720 ? max(width - 32, 280) : 320
    #else
    minCardWidth = width < 980 ? max(width - 40, 320) : 360
    #endif
    return [GridItem(.adaptive(minimum: minCardWidth), spacing: 14)]
  }

  // MARK: - Filtering

  private var visibleProfiles: [WWNMachineProfile] {
    let base = model.filteredProfiles
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty { return base }
    return base.filter { profile in
      profile.name.lowercased().contains(query) ||
        profile.sshHost.lowercased().contains(query) ||
        profile.sshUser.lowercased().contains(query) ||
        model.machineTypeLabel(for: profile).lowercased().contains(query)
    }
  }

  // MARK: - Summary Strip

  private var summaryStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        Label("Machines", systemImage: "server.rack")
          .font(.headline.weight(.semibold))
        summaryPill("Profiles", "\(model.profiles.count)")
        summaryPill("Connected", "\(model.connectedCount)")
        summaryPill("Ready", "\(model.launchableCount)")
        Button {
          isCreating = true
        } label: {
          Label("New Machine", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        if let onOpenSettings {
          Button("Settings", action: onOpenSettings)
            .buttonStyle(.bordered)
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Search / Filter Bar

  private var searchAndLayoutBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Search machines, hosts, or type", text: $searchQuery)
        .textFieldStyle(.roundedBorder)
      filterPicker
    }
  }

  private var filterPicker: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        Picker("Scope", selection: $model.selectedFilter) {
          ForEach(WWNMachineFilter.allCases) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.segmented)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Scope")
          .font(.caption)
          .foregroundStyle(.secondary)
        Picker("Scope", selection: $model.selectedFilter) {
          ForEach(WWNMachineFilter.allCases) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.menu)
      }
    }
  }

  // MARK: - Helpers

  private func summaryPill(_ title: String, _ value: String) -> some View {
    HStack(spacing: 6) {
      Text(title)
      Text(value).fontWeight(.bold)
    }
    .font(.caption)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.secondary.opacity(0.14), in: Capsule())
  }

  private func filterIcon(_ filter: WWNMachineFilter) -> String {
    switch filter {
    case .all: return "circle.grid.2x2"
    case .local: return "desktopcomputer"
    case .remote: return "network"
    }
  }
}

// MARK: - iOS Hosting Bridge

#if os(iOS)
import UIKit

@objc(WWNMachinesHostingBridge)
@objcMembers
final class WWNMachinesHostingBridge: NSObject {
  @objc(buildIOSMachinesControllerWithOnConnect:)
  static func buildIOSMachinesController(onConnect: (() -> Void)?) -> UIViewController {
    let root = WWNMachinesGridView(onConnect: onConnect, onOpenSettings: nil)
    let hosting = UIHostingController(rootView: root)
    let nav = UINavigationController(rootViewController: hosting)
    nav.modalPresentationStyle = .fullScreen
    return nav
  }
}
#endif

// MARK: - macOS Hosting Bridge

#if os(macOS)
import AppKit

@objc(WWNMachinesHostingBridge)
@objcMembers
final class WWNMachinesHostingBridge: NSObject {
  @objc(buildMacMachinesWindowControllerWithOnConnect:)
  static func buildMacMachinesWindowController(onConnect: (() -> Void)?) -> NSWindowController {
    let root = WWNMachinesGridView(
      onConnect: onConnect,
      onOpenSettings: { WWNPreferences.shared().show(NSApp as Any) }
    )
    let hosting = NSHostingController(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.minSize = NSSize(width: 1024, height: 720)
    window.center()
    window.contentViewController = hosting
    window.title = "Wawona Machine Control Panel"
    window.isRestorable = false
    return NSWindowController(window: window)
  }
}
#endif
