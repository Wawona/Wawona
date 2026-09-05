import SwiftUI
#if os(macOS)
import AppKit
#endif

struct WWNMachinesGridView: View {
  let onConnect: (() -> Void)?
  let onOpenSettings: (() -> Void)?
  /// When set, the grid shows only machines carrying this tag (sidebar).
  var filterTagID: String? = nil
  var onClearTagFilter: (() -> Void)? = nil

  @StateObject private var model = WWNMachinesViewModel()
  @ObservedObject private var tagStore = WWNMachineTagStore.shared
  @State private var editingProfile: WWNMachineProfile?
  @State private var isCreating = false
  @State private var searchQuery = ""
  @State private var tagEditorTag: WWNMachineTag?
  @State private var showTagEditor = false
  #if os(tvOS)
  @FocusState private var focusedMachineId: String?
  #endif

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
      .sheet(isPresented: $showTagEditor) {
        WWNTagEditorSheet(tag: tagEditorTag) { name, colorHex in
          if let existing = tagEditorTag {
            var updated = existing
            updated.name = name
            updated.colorHex = colorHex
            tagStore.updateTag(updated)
          } else {
            tagStore.createTag(name: name, colorHex: colorHex)
          }
        }
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
          if visibleProfiles.isEmpty {
            ContentUnavailableView(
              "No Machines",
              systemImage: "tv",
              description: Text("Add a Local or Remote machine profile, then Start it with the Siri Remote.")
            )
            .frame(maxWidth: .infinity, minHeight: 420)
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
                .focused($focusedMachineId, equals: profile.machineId)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Machines")
      .onAppear {
        if focusedMachineId == nil {
          focusedMachineId = visibleProfiles.first?.machineId
        }
      }
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    ToolbarItem(placement: .primaryAction) {
      sortMenu
    }
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
    #if !os(tvOS)
    ToolbarItem(placement: .topBarTrailing) {
      sortMenu
    }
    #endif
    if let onOpenSettings {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
        .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
      }
    }
    #endif
  }

  // MARK: - Sort Menu

  /// Finder-style sort control: grid + chevron toolbar button; picking a
  /// criterion switches to it, picking the active one flips the direction.
  #if !os(tvOS)
  @ViewBuilder
  private var sortMenu: some View {
    Menu {
      ForEach(WWNMachinesViewModel.SortKey.allCases, id: \.self) { key in
        Button {
          if model.sortKey == key {
            // Clicking the active criterion flips the direction (Finder-style).
            model.setSortAscending(!model.sortAscending)
          } else {
            model.setSortKey(key)
          }
        } label: {
          HStack {
            Text(key.title)
            Spacer()
            if model.sortKey == key {
              Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
                .font(.caption.weight(.semibold))
            }
          }
        }
      }
      Divider()
      Button {
        model.setSortAscending(!model.sortAscending)
      } label: {
        Label(
          model.sortAscending ? "Ascending" : "Descending",
          systemImage: model.sortAscending ? "arrow.up" : "arrow.down"
        )
      }
    } label: {
      Image(systemName: "line.3.horizontal.decrease")
    }
    .menuIndicator(.hidden)
    .help("Sort — pinned machines stay on top")
    .wwnA11y(WWNA11y.machinesSort, label: "Sort")
  }
  #endif

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

  // MARK: - Filtering

  /// Pill shown inline with the summary strip while a sidebar tag filter is
  /// active. Rendered in the strip's own row so nothing moves vertically.
  @ViewBuilder
  private var tagFilterBar: some View {
    if let filterTagID,
       let tag = tagStore.tags.first(where: { $0.id == filterTagID }) {
      HStack(spacing: 6) {
        // Label pairs icon + text with its own optical centering, so the dot
        // sits on the text's true vertical center.
        Label {
          Text(tag.name)
        } icon: {
          WWNTagDot(colorHex: tag.colorHex, size: 9)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel("Showing tag \(tag.name)")
        if let onClearTagFilter {
          Button(action: onClearTagFilter) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Clear tag filter")
        }
      }
      .padding(.leading, 10)
      .padding(.trailing, 6)
      .padding(.vertical, 6)
      .background(Color.secondary.opacity(0.14), in: Capsule())
      .help("Showing machines tagged \(tag.name)")
      .wwnA11y(WWNA11y.machinesTagFilter, label: "Showing tag \(tag.name)")
    }
  }

  private var visibleProfiles: [WWNMachineProfile] {
    var base = model.profiles
    if let filterTagID,
       tagStore.tags.contains(where: { $0.id == filterTagID }) {
      base = base.filter { tagStore.isAssigned(filterTagID, to: $0.machineId) }
    }
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty {
      // Sort by the chosen key; pins stay on top regardless.
      return model.displayOrder(base)
    }

    // Non-empty query always uses fuzzy scoring across searchable corpus.
    // Pinned matches lead; ties break on fuzzy score, then name.
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
        let lhsPinned = model.isPinned($0.profile.machineId)
        let rhsPinned = model.isPinned($1.profile.machineId)
        if lhsPinned != rhsPinned {
          return lhsPinned
        }
        if $0.score == $1.score {
          return $0.profile.name.localizedCaseInsensitiveCompare($1.profile.name) == .orderedAscending
        }
        return $0.score > $1.score
      }
      .map(\.profile)
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
            isPinned: model.isPinned(profile.machineId),
            tags: tagStore.tags(for: profile.machineId),
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
          .contextMenu {
            machineCardContextMenu(for: profile)
          }
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

  // MARK: - Context Menu

  /// Right-click (macOS) / long-press (iOS) menu on a machine card. Card
  /// actions come first; pinning sits under a divider for separation.
  @ViewBuilder
  private func machineCardContextMenu(for profile: WWNMachineProfile) -> some View {
    let machineStatus = model.status(for: profile.machineId)
    let running = machineStatus == .connected || machineStatus == .connecting
    let preparing = machineStatus == .preparing

    if running {
      Button {
        model.focusRunningMachine(profile)
      } label: {
        Label("Focus", systemImage: "scope")
      }
      Button(role: .destructive) {
        model.disconnect(profile)
      } label: {
        Label("Stop", systemImage: "stop.fill")
      }
    } else if !preparing {
      Button {
        model.connect(profile) {
          onConnect?()
        }
      } label: {
        Label("Start", systemImage: "play.fill")
      }
      .disabled(!model.launchSupported(for: profile))
    }

    Button {
      editingProfile = profile
    } label: {
      Label("Edit…", systemImage: "slider.horizontal.3")
    }
    Button(role: .destructive) {
      model.delete(profile)
    } label: {
      Label("Delete", systemImage: "trash")
    }
    .disabled(running || preparing)

    Divider()

    #if !os(tvOS)
    tagsContextMenu(for: profile)

    Divider()
    #endif

    let pinned = model.isPinned(profile.machineId)
    Button {
      model.togglePinned(profile.machineId)
    } label: {
      Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
    }
  }

  /// Finder-style tag assignment submenu (colored dots + checkmarks) with a
  /// "Create Tag…" entry.
  #if !os(tvOS)
  @ViewBuilder
  private func tagsContextMenu(for profile: WWNMachineProfile) -> some View {
    Menu {
      if tagStore.tags.isEmpty {
        Text("No tags yet")
          .font(.caption)
      }
      ForEach(tagStore.tags) { tag in
        let assigned = tagStore.isAssigned(tag.id, to: profile.machineId)
        Button {
          tagStore.setAssigned(!assigned, tag: tag, to: profile.machineId)
        } label: {
          HStack(spacing: 8) {
            WWNTagDot(colorHex: tag.colorHex, size: 9)
            Text(tag.name)
              .frame(maxWidth: .infinity, alignment: .leading)
            if assigned {
              Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      Divider()
      Button {
        tagEditorTag = nil
        showTagEditor = true
      } label: {
        Label("Create Tag…", systemImage: "plus")
      }
    } label: {
      Label("Tags", systemImage: "tag")
    }
  }
  #endif

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
        // Inline with the summary pills so the strip height — and the grid
        // below it — never shifts when a tag filter toggles.
        tagFilterBar
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
          MachineStatusChip(text: scopeLabel, font: .title3.weight(.semibold))
          MachineStatusChip(text: typeLabel, font: .title3.weight(.semibold))
          MachineFittingLabel(
            text: status.title,
            font: .title3.weight(.bold),
            alignment: .leading
          )
          .foregroundStyle(statusColor)
          .frame(minWidth: 0)
          .layoutPriority(1)
          if isActive {
            MachineStatusChip(text: "Active", font: .title3.weight(.semibold))
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
  @FocusState private var focusedActionId: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 40) {
        VStack(alignment: .leading, spacing: 16) {
          Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
            .font(.largeTitle.weight(.bold))
          Text(subtitle)
            .font(.title)
            .foregroundStyle(.secondary)
          Text(summary)
            .font(.title2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 28) {
            Label(scopeLabel, systemImage: "circle.grid.2x2")
            Label(typeLabel, systemImage: "tag")
            Label(status.title, systemImage: "circle.fill")
              .foregroundStyle(statusColor)
          }
          .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 22) {
          ForEach(tvActionItems) { item in
            MachineActionBar(items: [item], layout: .stack)
              .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
              .focused($focusedActionId, equals: item.accessibilityID)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(64)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("Machine")
    .onAppear {
      focusedActionId = tvActionItems.first?.accessibilityID
    }
  }

  private var tvActionItems: [MachineActionItem] {
    var items: [MachineActionItem] = []
    if isRunning {
      items.append(
        MachineActionItem(
          title: "Focus",
          systemImage: "scope",
          prominent: true,
          accessibilityID: WWNA11y.machinesFocus,
          accessibilityLabel: "Focus Session",
          action: onFocus
        )
      )
      items.append(
        MachineActionItem(
          title: "Stop",
          systemImage: "stop.fill",
          role: .destructive,
          accessibilityID: WWNA11y.machinesStop,
          accessibilityLabel: "Stop Session",
          action: onStop
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
          accessibilityLabel: "Start Machine",
          action: onConnect
        )
      )
    }
    items.append(
      MachineActionItem(
        title: "Edit",
        systemImage: "slider.horizontal.3",
        accessibilityID: WWNA11y.machinesEdit,
        accessibilityLabel: "Edit Profile",
        action: onEdit
      )
    )
    items.append(
      MachineActionItem(
        title: "Delete",
        systemImage: "trash",
        role: .destructive,
        enabled: !isRunning,
        accessibilityID: WWNA11y.machinesDelete,
        accessibilityLabel: "Delete Profile",
        action: {
          onDelete()
          dismiss()
        }
      )
    )
    return items
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
    hosting.sizingOptions = []
    #else
    let hosting = UIHostingController(rootView: root)
    hosting.view.backgroundColor = UIColor.systemBackground
    #endif
    return hosting
  }
}

#if os(tvOS)
/// Fills the TV window. SwiftUI owns focus via FocusState on the machine cards.
private final class WWNMachinesTVHostingController<Content: View>: UIHostingController<Content> {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    hideStrayPageControls(in: view.window ?? view)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    hideStrayPageControls(in: view.window ?? view)
    setNeedsFocusUpdate()
    updateFocusIfNeeded()
  }

  /// NavigationStack on tvOS injects a UIPageControl labelled "0 pages".
  private func hideStrayPageControls(in root: UIView) {
    for sub in root.subviews {
      if let pages = sub as? UIPageControl {
        pages.isHidden = true
        pages.alpha = 0
        pages.isUserInteractionEnabled = false
      }
      hideStrayPageControls(in: sub)
    }
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
    // Stable id so reopen / Cmd-Shift-M never spawn a second panel.
    window.identifier = NSUserInterfaceItemIdentifier("wwn.machines.control-panel")
    window.isRestorable = false
    // Keep the window controller as owner across close; coordinator re-shows
    // the same window instead of allocating another.
    window.isReleasedWhenClosed = false
    return NSWindowController(window: window)
  }
}
#endif
