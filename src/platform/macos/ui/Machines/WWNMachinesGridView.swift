import SwiftUI
#if os(macOS)
import AppKit
#endif

struct WWNMachinesGridView: View {
  let onConnect: (() -> Void)?
  let onOpenSettings: (() -> Void)?

  @StateObject private var model = WWNMachinesViewModel()
  @State private var editingProfile: WWNMachineProfile?
  @State private var isCreating = false
  @State private var searchQuery = ""
  #if os(iOS)
  @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
  #endif

  var body: some View {
    #if os(macOS)
    applyMacChromeFixes(
      to: splitView
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
        .sheet(item: $editingProfile) { profile in
          WWNMachineEditorView(title: "Edit Machine Profile", initial: profile) { updated in
            model.upsert(updated)
          }
          #if os(iOS)
          .presentationDetents([.medium, .large])
          .presentationContentInteraction(.scrolls)
          #endif
        }
        .animation(.spring(duration: 0.42, bounce: 0.26), value: visibleProfiles.count)
    )
    #else
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
      .sheet(item: $editingProfile) { profile in
        WWNMachineEditorView(title: "Edit Machine Profile", initial: profile) { updated in
          model.upsert(updated)
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        #endif
      }
      .animation(.spring(duration: 0.42, bounce: 0.26), value: visibleProfiles.count)
    #endif
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
    #if os(macOS)
    applyMacToolbarLayout(
      to: detailPane
        .navigationTitle(detailNavigationTitle)
        .toolbar {
          detailToolbarContent
        }
    )
    #else
    detailPane
      .navigationTitle(detailNavigationTitle)
      .toolbar {
        detailToolbarContent
      }
      #if os(iOS)
      .overlay(alignment: .bottomTrailing) {
        iosQuickActions
          .padding(.trailing, 20)
          .padding(.bottom, 20)
      }
      #endif
    #endif
  }

  private var detailNavigationTitle: String {
    #if os(macOS)
    // Short title prevents clipping when sidebar is expanded and toolbar is populated.
    return "Machines"
    #else
    return "Machine Configuration"
    #endif
  }

  @ToolbarContentBuilder
  private var detailToolbarContent: some ToolbarContent {
    #if os(macOS)
    ToolbarItem(placement: .primaryAction) {
      Button {
        toggleSidebar()
      } label: {
        Label("Toggle Sidebar", systemImage: "sidebar.left")
      }
    }
    ToolbarItem(placement: .automatic) {
      Button {
        isCreating = true
      } label: {
        Label("Add", systemImage: "plus")
      }
    }
    if let onOpenSettings {
      ToolbarItem(placement: .automatic) {
        Button("Settings", action: onOpenSettings)
      }
    }
    #else
    if let onOpenSettings {
      ToolbarItem(placement: .automatic) {
        Button("Settings", action: onOpenSettings)
      }
    }
    #endif
  }

  #if os(macOS)
  private func toggleSidebar() {
    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)),
                     to: nil,
                     from: nil)
  }

  @ViewBuilder
  private func applyMacToolbarLayout<V: View>(to view: V) -> some View {
    if #available(macOS 13.0, *) {
      view.toolbar(removing: .sidebarToggle)
    } else {
      view
    }
  }
  #endif

  // MARK: - Sidebar

  private var sidebar: some View {
    Group {
      #if os(macOS)
      List(selection: macSidebarSelection) {
        Section("Machine Scope") {
          ForEach(WWNMachineFilter.allCases) { filter in
            Label(filter.rawValue, systemImage: filterIcon(filter))
              .tag(filter)
          }
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
      #else
      List(selection: compactSidebarSelection) {
        Section("Machine Scope") {
          ForEach(WWNMachineFilter.allCases) { filter in
            Label(filter.rawValue, systemImage: filterIcon(filter))
              .tag(filter)
          }
        }
      }
      #if os(tvOS)
      .listStyle(.plain)
      #else
      .listStyle(.sidebar)
      #endif
      .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
      #endif
    }
    #if os(macOS)
    .navigationTitle("Control Panel")
    #endif
  }

  #if os(macOS)
  private var macSidebarSelection: Binding<WWNMachineFilter?> {
    Binding(
      get: { model.selectedFilter },
      set: { selected in
        guard let selected, selected != model.selectedFilter else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
          model.selectedFilter = selected
        }
      }
    )
  }
  #endif

  #if !os(macOS)
  /// Selection-driven list rows (matches Settings-style sidebar highlight on iPad / compact split).
  private var compactSidebarSelection: Binding<WWNMachineFilter?> {
    Binding(
      get: { model.selectedFilter },
      set: { selected in
        guard let selected, selected != model.selectedFilter else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
          model.selectedFilter = selected
        }
        #if os(iOS)
        preferredColumn = .detail
        #endif
      }
    )
  }
  #endif

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
                  thumbnailImage: model.thumbnailImage(for: profile),
                  typeLabel: model.machineTypeLabel(for: profile),
                  scopeLabel: model.machineScopeLabel(for: profile),
                  subtitle: model.machineSubtitle(for: profile),
                  summary: model.machineConfigurationSummary(for: profile),
                  launchSupported: model.launchSupported(for: profile),
                  isActive: profile.machineId == model.activeMachineId,
                  isRunning: machineStatus == .connected || machineStatus == .connecting,
                  onEdit: {
                    editingProfile = profile
                  },
                  onDelete: { model.delete(profile) },
                  onConnect: {
                    model.connect(profile) {
                      onConnect?()
                    }
                  },
                  onStop: { model.disconnect(profile) },
                  onFocus: { model.focusRunningMachine(profile) }
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
      #if os(macOS)
      // Keep content out of the titlebar zone even if AppKit briefly toggles unified chrome.
      .safeAreaPadding(.top, 6)
      #endif
    }
  }

  // MARK: - Grid Layout

  private func gridColumns(for width: CGFloat) -> [GridItem] {
    let minCardWidth: CGFloat
    #if os(iOS)
    minCardWidth = width < 720 ? max(width - 32, 280) : 320
    #else
    // Prefer a card grid sooner on macOS so ~1000px windows don't feel like a list.
    let availableWidth = width - 32
    if availableWidth >= 680 {
      minCardWidth = 300
    } else {
      minCardWidth = max(availableWidth, 320)
    }
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
    TextField("Search machines or hosts", text: $searchQuery)
      #if os(tvOS)
      .textFieldStyle(.automatic)
      #else
      .textFieldStyle(.roundedBorder)
      #endif
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

  #if os(iOS)
  private var iosQuickActions: some View {
    Menu {
      Button {
        onOpenSettings?()
      } label: {
        Label("Wawona Settings", systemImage: "gearshape")
      }
      Button {
        isCreating = true
      } label: {
        Label("Add Profile", systemImage: "plus")
      }
    } label: {
      Image(systemName: "plus")
        .font(.title2.weight(.semibold))
        .foregroundStyle(Color.white)
        .frame(width: 56, height: 56)
        .background(Color.accentColor, in: Circle())
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
    }
  }
  #endif

  #if os(macOS)
  @ViewBuilder
  private func applyMacChromeFixes<V: View>(to view: V) -> some View {
    if #available(macOS 13.0, *) {
      view
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .background(WWNWindowChromeGuard())
    } else {
      view
        .background(WWNWindowChromeGuard())
    }
  }
  #endif
}

extension WWNMachineProfile: Identifiable {
  public var id: String { machineId }
}

// MARK: - iOS Hosting Bridge

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

@objc(WWNMachinesHostingBridge)
@objcMembers
final class WWNMachinesHostingBridge: NSObject {
  @objc(buildIOSMachinesControllerWithOnConnect:)
  static func buildIOSMachinesController(onConnect: (() -> Void)?) -> UIViewController {
    let root = WWNMachinesGridView(
      onConnect: onConnect,
      onOpenSettings: {
        WWNPreferences.sharedPreferences().showPreferences(nil)
      }
    )
    let hosting = UIHostingController(rootView: root)
    let nav = UINavigationController(rootViewController: hosting)
    nav.modalPresentationStyle = .fullScreen
    return nav
  }
}
#endif

// MARK: - macOS Hosting Bridge

#if os(macOS)
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
    window.styleMask.remove(.fullSizeContentView)
    window.titlebarAppearsTransparent = false
    window.titleVisibility = .visible
    if #available(macOS 11.0, *) {
      window.toolbarStyle = .automatic
    }
    window.center()
    window.contentViewController = hosting
    window.title = "Wawona Machine Control Panel"
    window.isRestorable = false
    return NSWindowController(window: window)
  }
}

private struct WWNWindowChromeGuard: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    DispatchQueue.main.async {
      configureWindow(for: view)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      configureWindow(for: nsView)
    }
  }

  private func configureWindow(for view: NSView) {
    guard let window = view.window else { return }
    window.styleMask.remove(.fullSizeContentView)
    window.titlebarAppearsTransparent = false
    window.titleVisibility = .visible
    window.isOpaque = true
    window.backgroundColor = .windowBackgroundColor
    window.contentView?.wantsLayer = true
    window.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    if #available(macOS 11.0, *) {
      window.toolbarStyle = .automatic
    }
  }
}
#endif
