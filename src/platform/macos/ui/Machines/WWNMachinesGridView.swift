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
  #if os(macOS)
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  #endif
  #if os(iOS)
  @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
  #endif

  var body: some View {
    splitView
      #if os(macOS)
      .background(WWNMachineKeyboardInputGate())
      #endif
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
  }

  @ViewBuilder
  private var splitView: some View {
    #if os(macOS)
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebar
    } detail: {
      detailContent
    }
    #elseif os(iOS)
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
    removeSidebarToggleIfAvailable(
      from: detailPane
      .modifier(MacDetailTopInsetForTransparentTitlebar())
      .navigationTitle(detailNavigationTitle)
      .toolbarTitleDisplayMode(.inline)
      .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search machines")
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
    ToolbarItem(placement: .navigation) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
        }
      } label: {
        Image(systemName: "sidebar.left")
      }
      .help("Toggle Sidebar")
    }
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        isCreating = true
      } label: {
        Label("Add", systemImage: "plus")
      }

      if let onOpenSettings {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
        .help("Settings")
      }
    }
    #else
    if let onOpenSettings {
      ToolbarItem(placement: .automatic) {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
      }
    }
    #endif
  }

  #if os(macOS)
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
      .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
      .toolbar(removing: .sidebarToggle)
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
      .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
      #endif
    }
  }

  #if os(macOS)
  @ViewBuilder
  private func removeSidebarToggleIfAvailable<V: View>(from view: V) -> some View {
    if #available(macOS 13.0, *) {
      view.toolbar(removing: .sidebarToggle)
    } else {
      view
    }
  }

  private var macSidebarSelection: Binding<WWNMachineFilter?> {
    Binding(
      get: { model.selectedFilter },
      set: { selected in
        guard let selected, selected != model.selectedFilter else { return }
        // Defer mutation to next runloop; direct publish during List selection
        // update can trigger "Publishing changes from within view updates".
        DispatchQueue.main.async {
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
        DispatchQueue.main.async {
          model.selectedFilter = selected
          #if os(iOS)
          preferredColumn = .detail
          #endif
        }
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

    // Non-empty query always uses fuzzy scoring across searchable corpus.
    let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let scored: [(profile: WWNMachineProfile, score: Int)] = base.compactMap { profile in
      let haystack = model.searchableText(for: profile)
      var total = 0
      for term in terms {
        guard let score = fzfScore(pattern: term, candidate: haystack) else {
          return nil
        }
        total += score
      }
      return (profile, total)
    }
    return scored
      .sorted {
        if $0.score == $1.score {
          return $0.profile.name.localizedCaseInsensitiveCompare($1.profile.name) == .orderedAscending
        }
        return $0.score > $1.score
      }
      .map(\.profile)
  }

  /// Lightweight fzf-style subsequence matcher with adjacency and boundary bonuses.
  private func fzfScore(pattern: String, candidate: String) -> Int? {
    if pattern.isEmpty { return 0 }
    let p = Array(pattern.lowercased())
    let c = Array(candidate.lowercased())
    if p.count > c.count { return nil }

    let boundaryChars = CharacterSet(charactersIn: " _-/.:")
    var score = 0
    var pi = 0
    var ci = 0
    var lastMatch = -1
    var firstMatch = -1

    while pi < p.count, ci < c.count {
      if p[pi] == c[ci] {
        if firstMatch < 0 { firstMatch = ci }
        score += 8
        if lastMatch >= 0 {
          let gap = ci - lastMatch - 1
          if gap == 0 {
            score += 14 // adjacency bonus
          } else {
            score -= min(gap, 10)
          }
        }
        if ci == 0 {
          score += 10
        } else {
          let prev = String(c[ci - 1]).unicodeScalars
          if let scalar = prev.first, boundaryChars.contains(scalar) {
            score += 9 // token boundary bonus
          }
        }
        lastMatch = ci
        pi += 1
      }
      ci += 1
    }

    if pi != p.count { return nil }
    score += max(0, 24 - firstMatch) // prefer earlier matches
    return score
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
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
        let prefs = WWNPreferences.shared()
        prefs.show(nil as Any)
      }
    )
    let hosting = UIHostingController(rootView: root)
    let nav = UINavigationController(rootViewController: hosting)
    nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
    return nav
  }
}
#endif

// MARK: - macOS Hosting Bridge

#if os(macOS)
private struct MacDetailTopInsetForTransparentTitlebar: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      // Keep primary content below Tahoe-style transparent titlebar while
      // allowing sidebar to visually extend to the top with traffic lights.
      content.safeAreaPadding(.top, 28)
    } else {
      content
    }
  }
}

private struct WWNMachineKeyboardInputGate: NSViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.installMonitorIfNeeded()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.installMonitorIfNeeded()
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.removeMonitor()
  }

  final class Coordinator {
    private var monitor: Any?

    func installMonitorIfNeeded() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        guard Self.shouldSuppress(event) else { return event }
        return nil
      }
    }

    func removeMonitor() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
      monitor = nil
    }

    private static func shouldSuppress(_ event: NSEvent) -> Bool {
      guard event.type == .keyDown else { return false }
      let blockedModifiers = event.modifierFlags.intersection([.command, .control, .option, .function])
      guard blockedModifiers.isEmpty else { return false }
      guard !isTextInputFocused() else { return false }
      return isTypingKey(event)
    }

    private static func isTextInputFocused() -> Bool {
      guard let responder = NSApp.keyWindow?.firstResponder else { return false }
      if let textView = responder as? NSTextView {
        return textView.isEditable
      }
      return responder is NSTextField || responder is NSSearchField
    }

    private static func isTypingKey(_ event: NSEvent) -> Bool {
      guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
        return false
      }
      // Swallow printable typing input only; keep navigation/command keys untouched.
      let controls = CharacterSet.controlCharacters
      for scalar in chars.unicodeScalars {
        if controls.contains(scalar) {
          return false
        }
      }
      return true
    }
  }
}

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
    if #available(macOS 26.0, *) {
      // Tahoe-style sidebar/titlebar integration: sidebar extends to top.
      window.styleMask.insert(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.toolbarStyle = .unified
    }
    window.center()
    window.contentViewController = hosting
    window.title = "Wawona Machine Control Panel"
    window.isRestorable = false
    return NSWindowController(window: window)
  }
}
#endif
