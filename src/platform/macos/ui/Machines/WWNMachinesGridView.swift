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

  var body: some View {
    Group {
      #if os(iOS) || os(visionOS)
      iosRoot
      #elseif os(tvOS)
      tvosRoot
      #elseif os(macOS)
      macRoot
        .background(WWNMachineKeyboardInputGate())
      #else
      macRoot
      #endif
    }
    .wwnA11y(WWNA11y.machinesRoot, label: detailNavigationTitle)
    #if !os(tvOS)
    .sheet(isPresented: $isCreating) {
        WWNMachineEditorView(
          title: "Add Machine Profile",
          initial: nil,
          defaultType: kWWNMachineTypeNative
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
    #endif
    #if !os(macOS)
      .animation(.spring(duration: 0.42, bounce: 0.26), value: visibleProfiles.count)
    #endif
  }

  #if os(tvOS)
  /// 10-foot Machines UI: card focusables + NavigationStack (no FAB / split / sheets).
  private var tvosRoot: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          Text("Machines")
            .font(.title2.weight(.bold))
            .foregroundStyle(.secondary)

          if visibleProfiles.isEmpty {
            ContentUnavailableView(
              "No Machines",
              systemImage: "tv",
              description: Text("Add a Local or Remote machine profile, then Start it with the Siri Remote.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
          } else {
            LazyVStack(spacing: 22) {
              ForEach(visibleProfiles, id: \.machineId) { profile in
                let machineStatus = model.status(for: profile.machineId)
                let running = machineStatus == .connected || machineStatus == .connecting
                NavigationLink {
                  WWNMachineTVDetailView(
                    profile: profile,
                    status: machineStatus,
                    typeLabel: model.machineTypeLabel(for: profile),
                    scopeLabel: model.machineScopeLabel(for: profile),
                    subtitle: model.machineSubtitle(for: profile),
                    summary: model.machineConfigurationSummary(for: profile),
                    launchSupported: model.launchSupported(for: profile),
                    isActive: profile.machineId == model.activeMachineId,
                    isRunning: running,
                    onEdit: { editingProfile = profile },
                    onDelete: { model.delete(profile) },
                    onConnect: {
                      model.connect(profile) {
                        onConnect?()
                      }
                    },
                    onStop: { model.disconnect(profile) },
                    onFocus: { model.focusRunningMachine(profile) }
                  )
                } label: {
                  WWNMachineTVRow(
                    profile: profile,
                    status: machineStatus,
                    typeLabel: model.machineTypeLabel(for: profile),
                    scopeLabel: model.machineScopeLabel(for: profile),
                    subtitle: model.machineSubtitle(for: profile),
                    isActive: profile.machineId == model.activeMachineId,
                    isRunning: running
                  )
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(28)
                }
                .buttonStyle(.card)
              }
            }
            .frame(maxWidth: 1100, alignment: .leading)
          }

          Text("\(model.profiles.count) profiles · \(model.connectedCount) connected · \(model.launchableCount) ready")
            .font(.title3)
            .foregroundStyle(.secondary)

          HStack(spacing: 24) {
            Button {
              isCreating = true
            } label: {
              Label("Add Machine", systemImage: "plus")
                .font(.title3.weight(.semibold))
                .frame(minWidth: 260, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")

            if let onOpenSettings {
              Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
                  .font(.title3.weight(.semibold))
                  .frame(minWidth: 220, minHeight: 52)
              }
              .buttonStyle(.bordered)
              .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
            }
          }
        }
        .padding(48)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .navigationTitle("Machines")
      .fullScreenCover(isPresented: $isCreating) {
        WWNMachineEditorView(
          title: "Add Machine Profile",
          initial: nil,
          defaultType: kWWNMachineTypeNative
        ) { profile in
          model.upsert(profile)
        }
        .presentationBackground(Color(white: 0.07))
      }
      .fullScreenCover(item: $editingProfile) { profile in
        WWNMachineEditorView(title: "Edit Machine Profile", initial: profile) { updated in
          model.upsert(updated)
        }
        .presentationBackground(Color(white: 0.07))
      }
    }
    .preferredColorScheme(.dark)
  }
  #endif

  #if os(macOS)
  private var macRoot: some View {
    NavigationStack {
      detailPane
        .modifier(MacDetailTopInsetForTransparentTitlebar())
        .navigationTitle(detailNavigationTitle)
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search machines")
        .toolbar {
          detailToolbarContent
        }
        .modifier(MacUnifiedToolbarMaterial())
    }
  }
  #else
  private var macRoot: some View {
    NavigationStack {
      detailPane
        .navigationTitle(detailNavigationTitle)
        .toolbar {
          detailToolbarContent
        }
    }
  }
  #endif

  #if os(iOS) || os(visionOS)
  private var iosRoot: some View {
    NavigationStack {
      detailPane
        .navigationTitle(detailNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search machines")
        .toolbar {
          detailToolbarContent
        }
        .overlay(alignment: .bottomTrailing) {
          iosAddMachineButton
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }
  }
  #endif

  private var detailNavigationTitle: String {
    #if os(macOS)
    return "Machines"
    #else
    return "Machine Configuration"
    #endif
  }

  @ToolbarContentBuilder
  private var detailToolbarContent: some ToolbarContent {
    #if os(macOS)
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        isCreating = true
      } label: {
        Label("Add Machine", systemImage: "plus")
      }
      .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")

      if let onOpenSettings {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
        .help("Settings")
        .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
      }
    }
    #else
    ToolbarItemGroup(placement: .topBarTrailing) {
      if let onOpenSettings {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
        .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
      }
    }
    #endif
  }

  // MARK: - Detail

  private var detailPane: some View {
    #if os(macOS)
    // Avoid GeometryReader: it re-evaluates the entire grid on every window
    // bounds change during titlebar drag and amplifies move lag.
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        summaryStrip
        machinesGrid(columns: gridColumns(for: 1000))
      }
      .padding(16)
      .frame(maxWidth: 1320, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    #else
    GeometryReader { proxy in
      let detailWidth = max(proxy.size.width, 320)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          summaryStrip
          machinesGrid(columns: gridColumns(for: detailWidth))
        }
        .padding(16)
        .frame(maxWidth: 1320, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
    #endif
  }

  @ViewBuilder
  private func machinesGrid(columns: [GridItem]) -> some View {
    if visibleProfiles.isEmpty {
      ContentUnavailableView(
        "No Matching Machines",
        systemImage: "magnifyingglass",
        description: Text("Adjust search or add a new machine profile.")
      )
      .frame(maxWidth: .infinity)
      .padding(.top, 30)
    } else {
      LazyVGrid(columns: columns, spacing: 14) {
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
            onEdit: { editingProfile = profile },
            onDelete: { model.delete(profile) },
            onConnect: {
              model.connect(profile) {
                onConnect?()
              }
            },
            onStop: { model.disconnect(profile) },
            onFocus: { model.focusRunningMachine(profile) }
          )
          #if !os(macOS)
          .transition(.scale(scale: 0.95).combined(with: .opacity))
          #endif
        }
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
    let base = model.profiles
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

  #if os(iOS) || os(visionOS)
  @ViewBuilder
  private var iosAddMachineButton: some View {
    #if os(iOS)
    if #available(iOS 26, *) {
      Button {
        isCreating = true
      } label: {
        Image(systemName: "plus")
          .font(.title2.weight(.semibold))
          .frame(width: 56, height: 56)
      }
      .buttonStyle(.glassProminent)
      .buttonBorderShape(.circle)
      .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
    } else {
      addMachineCircleButton
    }
    #else
    addMachineCircleButton
    #endif
  }

  private var addMachineCircleButton: some View {
    Button {
      isCreating = true
    } label: {
      Image(systemName: "plus")
        .font(.title2.weight(.semibold))
        .frame(width: 56, height: 56)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.circle)
    .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
  }
  #endif

}

extension WWNMachineProfile: Identifiable {
  public var id: String { machineId }
}

#if os(tvOS)
/// Compact, focusable machine row for the tvOS Machines list.
/// Do not add a trailing chevron. `NavigationLink` already provides one.
struct WWNMachineTVRow: View {
  let profile: WWNMachineProfile
  let status: WWNMachineTransientStatus
  let typeLabel: String
  let scopeLabel: String
  let subtitle: String
  let isActive: Bool
  let isRunning: Bool

  var body: some View {
    HStack(spacing: 28) {
      Image(systemName: iconName)
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(statusColor)
        .frame(width: 72, height: 72)

      VStack(alignment: .leading, spacing: 10) {
        Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
          .font(.title2.weight(.bold))
          .lineLimit(1)
        Text(subtitle.isEmpty ? typeLabel : subtitle)
          .font(.title3)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        HStack(spacing: 14) {
          metaChip(scopeLabel)
          metaChip(typeLabel)
          Text(status.title)
            .font(.title3.weight(.bold))
            .foregroundStyle(statusColor)
          if isActive {
            Text("Active")
              .font(.title3.weight(.bold))
              .foregroundStyle(.yellow)
          }
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 18)
    .wwnA11yContainer(
      WWNA11y.machinesCard(profile.machineId),
      label: WWNA11y.machinesDescriptor(name: profile.name, subtitle: subtitle)
    )
  }

  private var iconName: String {
    switch profile.type {
    case kWWNMachineTypeNative:
      return "desktopcomputer"
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
    case .preparing: return .blue
    case .degraded: return .orange
    case .error: return .red
    case .disconnected: return .secondary
    }
  }

  private func metaChip(_ text: String) -> some View {
    Text(text)
      .font(.title3.weight(.semibold))
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(Color.secondary.opacity(0.22), in: Capsule())
  }
}

/// Detail actions for one machine. Large focusable buttons for Siri Remote.
struct WWNMachineTVDetailView: View {
  let profile: WWNMachineProfile
  let status: WWNMachineTransientStatus
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

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 36) {
        VStack(alignment: .leading, spacing: 14) {
          Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
            .font(.largeTitle.weight(.bold))
          Text(subtitle)
            .font(.title2)
            .foregroundStyle(.secondary)
          Text(summary)
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 24) {
            Label(scopeLabel, systemImage: "circle.grid.2x2")
            Label(typeLabel, systemImage: "tag")
            Label(status.title, systemImage: "circle.fill")
              .foregroundStyle(statusColor)
          }
          .font(.title3.weight(.semibold))
        }

        VStack(spacing: 22) {
          if isRunning {
            Button {
              onFocus()
            } label: {
              Label("Focus Session", systemImage: "scope")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .wwnA11y(WWNA11y.machinesFocus, label: "Focus Session")

            Button(role: .destructive) {
              onStop()
            } label: {
              Label("Stop Session", systemImage: "stop.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .wwnA11y(WWNA11y.machinesStop, label: "Stop Session")
          } else {
            Button {
              onConnect()
            } label: {
              Label("Start Machine", systemImage: "play.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!launchSupported)
            .wwnA11y(WWNA11y.machinesStart, label: "Start Machine")
          }

          Button {
            onEdit()
          } label: {
            Label("Edit Profile", systemImage: "slider.horizontal.3")
              .font(.title3.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 56)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .wwnA11y(WWNA11y.machinesEdit, label: "Edit Profile")

          Button(role: .destructive) {
            onDelete()
            dismiss()
          } label: {
            Label("Delete Profile", systemImage: "trash")
              .font(.title3.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 56)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(isRunning)
          .wwnA11y(WWNA11y.machinesDelete, label: "Delete Profile")
        }
        .frame(maxWidth: 900)
      }
      .padding(48)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Machine")
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
}
#endif

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
        WWNPreferences.shared().show(nil)
      }
    )
    #if os(tvOS)
    let hosting = WWNMachinesTVHostingController(rootView: root)
    hosting.view.backgroundColor = .black
    #else
    let hosting = UIHostingController(rootView: root)
    hosting.view.backgroundColor = UIColor.systemBackground
    #endif
    return hosting
  }
}

#if os(tvOS)
/// Prefers the first focusable control in the Machines list after welcome dismiss.
private final class WWNMachinesTVHostingController<Content: View>: UIHostingController<Content> {
  override var preferredFocusEnvironments: [any UIFocusEnvironment] {
    if let first = view.subviews.first(where: { $0.canBecomeFocused }) {
      return [first]
    }
    return super.preferredFocusEnvironments
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    setNeedsFocusUpdate()
    updateFocusIfNeeded()
  }
}
#endif
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

/// Restores the Tahoe-style unified toolbar blur. The window opts into a
/// transparent titlebar + full-size content view for sidebar-to-top
/// integration, which otherwise removes the toolbar's material; this puts the
/// frosted material back so detail content blurs under the toolbar like modern
/// macOS 26 apps.
private struct MacUnifiedToolbarMaterial: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      // Opaque toolbar fill avoids continuous material sampling while the
      // Machines window is dragged (cheaper than ultraThinMaterial).
      content
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
      if let keyWindow = NSApp.keyWindow,
         let wwnWindowClass = NSClassFromString("WWNWindow"),
         keyWindow.isKind(of: wwnWindowClass) {
        return false
      }
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
      onOpenSettings: { WWNPreferences.shared().show(NSApp) }
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
