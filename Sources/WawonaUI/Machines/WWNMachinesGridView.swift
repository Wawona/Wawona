import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
/// Public Machines grid. iOS 16+ gets the full UI; iOS 13–15 get a List fallback
/// so the module can compile against the product floor without typechecking
/// post-16 SwiftUI APIs into the always-available surface.
struct WWNMachinesGridView: View {
  let onConnect: (() -> Void)?
  var filterTagID: String? = nil
  var onClearTagFilter: (() -> Void)? = nil

  var body: some View {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      WWNMachinesGridViewModern(
        onConnect: onConnect,
        filterTagID: filterTagID,
        onClearTagFilter: onClearTagFilter
      )
    } else {
      WWNMachinesGridViewLegacy(
        onConnect: onConnect,
        filterTagID: filterTagID,
        onClearTagFilter: onClearTagFilter
      )
    }
    #else
    WWNMachinesGridViewModern(
      onConnect: onConnect,
      filterTagID: filterTagID,
      onClearTagFilter: onClearTagFilter
    )
    #endif
  }
}

#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNMachinesGridViewModern: View {
  let onConnect: (() -> Void)?
  /// When set, the grid shows only machines carrying this tag (sidebar).
  var filterTagID: String? = nil
  var onClearTagFilter: (() -> Void)? = nil

  @ObservedObject private var model = WWNMachinesViewModel.shared
  @ObservedObject private var tagStore = WWNMachineTagStore.shared
  #if os(macOS)
  /// Strip searchable / Machines toolbar while Global Settings owns NSToolbar.
  @ObservedObject private var mainRouter = WWNMainWindowRouter.shared
  #endif
  @State private var editorDestination: MachineEditorDestination?
  @State private var searchQuery = ""
  /// Selected machine for detail (actions + tags/pin). Nil = grid.
  @State private var detailMachineId: String?
  #if os(iOS)
  /// iPad: overlay search (not `.searchable` on the split detail).
  /// iPhone: system `.searchable` in the owning navigation item.
  @State private var isSearchPresented = false
  /// Focus request flag (iOS 15+ applies `.focused`; older hosts ignore).
  @State private var isSearchFocused = false
  #endif
  @State private var tagEditorTag: WWNMachineTag?
  @State private var showTagEditor = false
  /// When set, a newly created tag is assigned to this machine (detail Create Tag).
  @State private var tagEditorAssignToMachineId: String?
  #if os(visionOS)
  /// visionOS `Menu` in a Liquid Glass `ToolbarItemGroup` often swallows the
  /// press (no popover). Drive sort from a Button + popover instead.
  @State private var isSortPopoverPresented = false
  #endif
  #if os(tvOS)
  /// tvOS toolbar `Menu` often swallows presses (same class as visionOS).
  /// Drive sort from a Button + confirmationDialog instead.
  @State private var isSortDialogPresented = false
  /// System `.searchable` toggle remounts the detail tree and breaks the
  /// Liquid Glass NavigationSplitView. Dedicated cover instead.
  @State private var isSearchPresented = false
  #endif

  var body: some View {
    Group {
      #if os(visionOS)
      visionRoot
      #elseif os(iOS)
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
    .modifier(WWNMachineStartPlacementPrompt(model: model))
    #if !os(tvOS)
    // Phone: half sheet (medium) pullable to large. iPad: page/large.
    // iOS 26: system Liquid Glass sheet. Background attachment keeps the
    // sheet reliable on NavigationSplitView detail + bottom search.
    // tvOS uses fullScreenCover inside `machineEditorSheet`.
    .backport.machineEditorSheet(item: $editorDestination) { destination in
      machineEditor(for: destination)
    }
    .sheet(isPresented: $showTagEditor) {
      tagEditorSheet
    }
    #endif
    #if !os(macOS)
      .animation(.spring(duration: 0.42, bounce: 0.26), value: visibleProfiles.count)
    #endif
  }

  #if os(tvOS)
  /// 10-foot Machines: grid or selected-machine detail. Search is a dedicated
  /// fullScreenCover (toggling `.searchable` remounts detail and wrecks the
  /// split). Actions live on the machine detail screen (Tags/Pin included).
  private var tvosRoot: some View {
    detailPane
      .backport.navigationTitle(detailNavigationTitle)
      .fullScreenCover(item: $editorDestination) { destination in
        machineEditor(for: destination)
          .presentationBackground(Color(white: 0.07))
      }
      .fullScreenCover(isPresented: $isSearchPresented) {
        WWNTvMachinesSearchCover(
          results: { filteredProfiles(matching: $0) },
          card: { profile, query in
            machineCard(for: profile, highlight: query) {
              isSearchPresented = false
              detailMachineId = profile.machineId
            }
          },
          onClose: {
            isSearchPresented = false
          }
        )
        .presentationBackground(Color(white: 0.07))
      }
      .fullScreenCover(isPresented: $showTagEditor) {
        tagEditorSheet
          .presentationBackground(Color(white: 0.07))
      }
      .preferredColorScheme(.dark)
  }
  #endif

  private var tagEditorSheet: some View {
    WWNTagEditorSheet(tag: tagEditorTag) { name, colorHex in
      if let existing = tagEditorTag {
        var updated = existing
        updated.name = name
        updated.colorHex = colorHex
        tagStore.updateTag(updated)
      } else {
        let created = tagStore.createTag(name: name, colorHex: colorHex)
        if let machineId = tagEditorAssignToMachineId {
          tagStore.setAssigned(true, tag: created, to: machineId)
        }
      }
      tagEditorAssignToMachineId = nil
    }
  }

  #if os(macOS)
  /// Detail pane only. Nested `NavigationStack` + custom toolbar material
  /// broke the unified titlebar vs Settings sections in the split.
  ///
  /// When Global Settings owns the window toolbar, strip searchable + Machines
  /// items. Sharing an NSToolbar with Settings Done / Env Vars Add SIGTRAPs.
  @ViewBuilder
  private var macRoot: some View {
    Group {
      if mainRouter.settingsOwnsWindowToolbar {
        detailPane
          .navigationTitle(detailNavigationTitle)
          .toolbarTitleDisplayMode(.inline)
      } else if detailMachineId != nil {
        detailPane
          .navigationTitle(detailNavigationTitle)
          .toolbarTitleDisplayMode(.inline)
      } else {
        detailPane
          .navigationTitle(detailNavigationTitle)
          .toolbarTitleDisplayMode(.inline)
          .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search machines")
          .toolbar {
            detailToolbarContent
          }
      }
    }
    .alert(
      "Could not start machine",
      isPresented: Binding(
        get: { model.connectionError != nil },
        set: { if !$0 { model.connectionError = nil } }
      )
    ) {
      Button("OK", role: .cancel) { model.connectionError = nil }
    } message: {
      Text(model.connectionError ?? "")
    }
  }
  #elseif !os(tvOS)
  private var macRoot: some View {
    NavigationStack {
      detailPane
        .navigationTitle(detailNavigationTitle)
        .toolbar {
          detailToolbarContent
        }
        .alert(
          "Could not start machine",
          isPresented: Binding(
            get: { model.connectionError != nil },
            set: { if !$0 { model.connectionError = nil } }
          )
        ) {
          Button("OK", role: .cancel) { model.connectionError = nil }
        } message: {
          Text(model.connectionError ?? "")
        }
    }
  }
  #endif

  #if os(visionOS)
  /// Same chrome as macOS: system toolbar search + grouped trailing actions.
  /// Do not use a custom magnifyingglass that toggles a view-nested overlay.
  private var visionRoot: some View {
    detailPane
      .backport.navigationTitle(detailNavigationTitle, inline: true)
      .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search machines")
      .modifier(WWNVisionMachinesSearchToolbarBehavior())
      .toolbar {
        if detailMachineId == nil {
          detailToolbarContent
        }
      }
  }
  #endif

  #if os(iOS)
  /// Detail pane only. A nested `NavigationStack` made this look like a second
  /// main view and hid the split sidebar on compact iPhone.
  @ViewBuilder
  private var iosRoot: some View {
    if #available(iOS 14.0, *) {
      iosRootChrome
        .background {
          phoneIntegratedSearchToolbar
        }
        .toolbar {
          if detailMachineId == nil {
            detailToolbarContent
            // iPhone iOS 26 search + Add live in `toolbarItems` (see
            // WWNPhoneIntegratedSearchToolbar). A SwiftUI bottom-bar search
            // item vends the placement button from a different navigation item.
            if !isIosPhone {
              iosPadSearchToolbarItem
            }
          }
        }
    } else {
      iosRootChrome
        .navigationBarItems(trailing:
          HStack(spacing: 12) {
            if !isIosPhone {
              Button(action: { editorDestination = .add }) {
                Image(systemName: "plus")
              }
              .accessibilityLabel("Add Machine")
            }
            sortMenu
            Button(action: { WWNMainWindowRouter.shared.showSettings() }) {
              Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            if !isIosPhone {
              Button(action: {
                isSearchPresented = true
                isSearchFocused = true
              }) {
                Image(systemName: "magnifyingglass")
              }
              .accessibilityLabel("Search")
            }
          }
        )
    }
  }

  private var iosRootChrome: some View {
    detailPane
      .backport.navigationTitle(detailNavigationTitle, inline: true)
      .backport.dismissKeyboardOnScroll()
      .modifier(WWNIosPhoneSearchable(
        enabled: isIosPhone && Self.usesNativePhoneSearchToolbar,
        text: $searchQuery
      ))
      .modifier(WWNIosPhoneLegacyBottomChrome(
        enabled: isIosPhone && !Self.usesNativePhoneSearchToolbar
      ) {
        iosPhoneMessagesBottomChrome
      })
      .overlay(alignment: .top) {
        if !isIosPhone && isSearchPresented {
          iosSearchOverlay
        }
      }
      .onDisappear {
        // The iOS 26 search field is vended by the owning navigation item.
        // Do not mutate its state while NavigationSplitView swaps a Settings
        // detail in and out, or UIKit restores a detached bottom toolbar.
        if !isIosPhone || !Self.usesNativePhoneSearchToolbar {
          dismissIosSearch(preserveQuery: true)
        }
      }
  }

  /// Phone only. Idiom, not size class (the split forces regular width).
  private var isIosPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  /// iPhone iOS 26: system search button in the navigation controller toolbar.
  /// Pre-26 keeps the compact safe-area row. iPad stays on the overlay.
  @ViewBuilder
  private var phoneIntegratedSearchToolbar: some View {
    if isIosPhone && Self.usesNativePhoneSearchToolbar {
      if #available(iOS 26.0, *) {
        WWNPhoneIntegratedSearchToolbar(placement: .bottomBar(showsCompose: true)) {
          editorDestination = .add
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
      }
    }
  }

  /// iOS 26+: system Messages-style bottom search + compose +. Pre-26 keeps
  /// the compact safeAreaInset chrome. Never custom Liquid Glass capsule on 26+.
  private static var usesNativePhoneSearchToolbar: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  @ToolbarContentBuilder
  private var iosPadSearchToolbarItem: some ToolbarContent {
    // Order: Add is in detailToolbar / FAB; Settings then Search (trailing).
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        isSearchPresented = true
        DispatchQueue.main.async {
          isSearchFocused = true
        }
      } label: {
        Label("Search", systemImage: "magnifyingglass")
      }
      .backport.glassToolbarButton()
      .accessibilityIdentifier(WWNA11y.machinesSearch)
    }
  }

  /// Shared Add: iPhone bottom bar (`toolbarItems`), or iPad `.primaryAction`.
  /// Call sites must not mount twice.
  private var iosAddMachineToolbarButton: some View {
    Button {
      editorDestination = .add
    } label: {
      Image(systemName: "plus")
    }
    .backport.glassProminentToolbarButton()
    .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
  }

  /// Pre-iOS 26 phone fallback only. Compact 36pt row. Not used on iOS 26+.
  private var iosPhoneMessagesBottomChrome: some View {
    let controlHeight: CGFloat = 36

    return HStack(alignment: .center, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.secondary)
        TextField("Search", text: $searchQuery, prompt: Text("Search"))
          .textFieldStyle(.plain)
          .font(.system(size: 15))
          .modifier(WWNSearchFieldFocus(isFocused: $isSearchFocused))
          .accessibilityLabel("Search machines")
          .accessibilityIdentifier(WWNA11y.machinesSearch)
        if !searchQuery.isEmpty {
          Button {
            searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 14))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: controlHeight)
      .backport.liquidGlassCapsule()

      Button {
        editorDestination = .add
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }
      .backport.blueGlassCircleButton(size: controlHeight)
      .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
    }
    .padding(.horizontal, 16)
    .padding(.top, 4)
    .padding(.bottom, 6)
    .background {
      LinearGradient(
        stops: [
          .init(color: Color.clear, location: 0.0),
          .init(color: systemChromeBackgroundColor.opacity(0.18), location: 0.35),
          .init(color: systemChromeBackgroundColor.opacity(0.70), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
    }
    .accessibilityElement(children: .contain)
  }

  private var systemChromeBackgroundColor: Color {
    #if canImport(UIKit)
    Color(uiColor: .systemBackground)
    #else
    Color(nsColor: .windowBackgroundColor)
    #endif
  }

  private var iosSearchOverlay: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.12)
        .ignoresSafeArea()
        .onTapGesture {
          dismissIosSearch(preserveQuery: true)
        }
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search machines", text: $searchQuery)
          .textFieldStyle(.plain)
          .modifier(WWNSearchFieldFocus(isFocused: $isSearchFocused))
          .onSubmit {
            dismissIosSearch(preserveQuery: true)
          }
        if !searchQuery.isEmpty {
          Button {
            searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
        Button("Cancel") {
          dismissIosSearch(preserveQuery: false)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .backport.liquidGlass(cornerRadius: 18)
      .padding(.horizontal, 16)
      .padding(.top, 6)
    }
  }

  private func dismissIosSearch(preserveQuery: Bool) {
    if !preserveQuery {
      searchQuery = ""
    }
    isSearchFocused = false
    isSearchPresented = false
    WWNHostKeyboard.dismiss()
  }
  #endif

  private var detailNavigationTitle: String {
    #if os(tvOS)
    // The detail banner already shows the machine name; one title only.
    if detailMachineId != nil { return "" }
    #endif
    if let detailMachineId,
       let profile = model.profiles.first(where: { $0.machineId == detailMachineId }) {
      return profile.name.isEmpty ? "Machine" : profile.name
    }
    return "Machine Configuration"
  }

  #if !os(tvOS)
  @ToolbarContentBuilder
  private var detailToolbarContent: some ToolbarContent {
    #if os(macOS)
    // Add is the primary CTA (blue). Sort / Settings stay secondary trailing.
    // Search is `.searchable` in the toolbar.
    ToolbarItem(placement: .primaryAction) {
      Button {
        editorDestination = .add
      } label: {
        Label("Add Machine", systemImage: "plus")
      }
      .backport.glassProminentToolbarButton()
      .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
    }
    ToolbarItemGroup(placement: .automatic) {
      Button {
        WWNMainWindowRouter.shared.showTabOverview()
      } label: {
        Label("Tab Overview", systemImage: "square.on.square")
      }
      .help("Show Tab Overview")
      .accessibility(identifier: "wwn.tabOverview.toolbar")
      sortMenu
      Button {
        WWNMainWindowRouter.shared.showSettings()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
      .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
    }
    #elseif os(visionOS)
    // Match macOS order + grouping: Add (primary), then one glass group of
    // Tab Overview / Sort / Settings. Search is system `.searchable` +
    // `searchToolbarBehavior(.minimize)` (icon expands in-toolbar; not a
    // custom magnifyingglass overlay).
    ToolbarItem(placement: .primaryAction) {
      Button {
        editorDestination = .add
      } label: {
        Label("Add Machine", systemImage: "plus")
      }
      .backport.glassProminentToolbarButton()
      .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
    }
    ToolbarItemGroup(placement: .automatic) {
      Button {
        WWNMainWindowRouter.shared.showTabOverview()
      } label: {
        Label("Tab Overview", systemImage: "square.on.square")
      }
      .accessibility(identifier: "wwn.tabOverview.toolbar")
      visionSortToolbarButton
      Button {
        WWNMainWindowRouter.shared.showSettings()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
      .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
    }
    #else
    // Exactly one Add Machine control per host:
    // - iPhone: bottom compose only (iOS 26 Messages toolbar, or pre-26
    //   safeAreaInset chrome). Never also top-trailing.
    // - iPad: `.primaryAction` only (blue prominent).
    // Top bar on phone is sort + Settings only.
    #if os(iOS)
    if !isIosPhone {
      ToolbarItem(placement: .primaryAction) {
        iosAddMachineToolbarButton
      }
    }
    #endif
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        WWNMainWindowRouter.shared.showTabOverview()
      } label: {
        Label("Tab Overview", systemImage: "square.on.square")
      }
      .backport.glassToolbarButton()
      .accessibility(identifier: "wwn.tabOverview.toolbar")
    }
    ToolbarItem(placement: .topBarTrailing) {
      sortMenu
    }
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        WWNMainWindowRouter.shared.showSettings()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
      .backport.glassToolbarButton()
      .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
    }
    #endif
  }
  #endif

  #if os(tvOS)
  /// Grid actions live in the scroll content, not the navigation bar. tvOS
  /// focus cannot move between nav bar items and this content in either
  /// direction, which stranded Search / Add above the cards.
  private var tvHeaderActions: some View {
    HStack(spacing: 20) {
      Button {
        isSearchPresented = true
      } label: {
        Image(systemName: "magnifyingglass")
      }
      .wwnA11y(WWNA11y.machinesSearch, label: "Search machines")
      Button {
        isSortDialogPresented = true
      } label: {
        Image(systemName: "line.3.horizontal.decrease")
      }
      .wwnA11y(WWNA11y.machinesSort, label: "Sort")
      .confirmationDialog(
        "Sort",
        isPresented: $isSortDialogPresented,
        titleVisibility: .visible
      ) {
        ForEach(WWNMachinesViewModel.SortKey.allCases, id: \.self) { key in
          Button {
            applySortSelection(key)
          } label: {
            if model.sortKey == key {
              Text("\(key.title) (\(model.sortAscending ? "Ascending" : "Descending"))")
            } else {
              Text(key.title)
            }
          }
        }
        Button {
          model.setSortAscending(!model.sortAscending)
        } label: {
          Text(model.sortAscending ? "Switch to Descending" : "Switch to Ascending")
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Pinned machines stay on top.")
      }
      Button {
        WWNMainWindowRouter.shared.showSettings()
      } label: {
        Image(systemName: "gearshape")
      }
      .wwnA11y(WWNA11y.machinesSettings, label: "Settings")
      Button {
        editorDestination = .add
      } label: {
        Image(systemName: "plus")
      }
      .wwnA11y(WWNA11y.machinesAdd, label: "Add Machine")
    }
    .buttonStyle(WWNTvCapsuleButtonStyle())
    .font(.headline.weight(.semibold))
  }
  #endif

  // MARK: - Sort Menu

  /// Finder-style sort control: grid + chevron toolbar button; picking a
  /// criterion switches to it, picking the active one flips the direction.
  /// tvOS uses Button + confirmationDialog (toolbar `Menu` is a no-op there).
  @ViewBuilder
  private var sortMenu: some View {
    Menu {
      sortMenuButtons
    } label: {
      Image(systemName: "line.3.horizontal.decrease")
    }
    .menuIndicator(.hidden)
    .help("Sort: pinned machines stay on top")
    .wwnA11y(WWNA11y.machinesSort, label: "Sort")
  }

  #if os(visionOS)
  /// Button + popover: visionOS Liquid Glass toolbar groups often drop `Menu`
  /// presentation (press does nothing). Same criteria as `sortMenu`.
  private var visionSortToolbarButton: some View {
    Button {
      isSortPopoverPresented.toggle()
    } label: {
      Label("Sort", systemImage: "line.3.horizontal.decrease")
        .labelStyle(.iconOnly)
    }
    .help("Sort: pinned machines stay on top")
    .wwnA11y(WWNA11y.machinesSort, label: "Sort")
    .popover(isPresented: $isSortPopoverPresented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(WWNMachinesViewModel.SortKey.allCases, id: \.self) { key in
          Button {
            applySortSelection(key)
            isSortPopoverPresented = false
          } label: {
            HStack {
              Text(key.title)
              Spacer(minLength: 12)
              if model.sortKey == key {
                Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
                  .font(.caption.weight(.semibold))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        Divider()
        Button {
          model.setSortAscending(!model.sortAscending)
          isSortPopoverPresented = false
        } label: {
          Label(
            model.sortAscending ? "Ascending" : "Descending",
            systemImage: model.sortAscending ? "arrow.up" : "arrow.down"
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }
      .frame(minWidth: 220)
      .padding(.vertical, 8)
    }
  }
  #endif

  @ViewBuilder
  private var sortMenuButtons: some View {
    ForEach(WWNMachinesViewModel.SortKey.allCases, id: \.self) { key in
      Button {
        applySortSelection(key)
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
  }

  private func applySortSelection(_ key: WWNMachinesViewModel.SortKey) {
    if model.sortKey == key {
      // Active criterion flips direction (Finder-style).
      model.setSortAscending(!model.sortAscending)
    } else {
      model.setSortKey(key)
    }
  }

  // MARK: - Detail

  @ViewBuilder
  private var detailPane: some View {
    if let detailMachineId,
       let profile = model.profiles.first(where: { $0.machineId == detailMachineId }) {
      machineDetail(for: profile)
    } else {
      machinesGridPane
        .onAppear {
          // Stale id after delete / import: return to grid.
          if let detailMachineId,
             !model.profiles.contains(where: { $0.machineId == detailMachineId }) {
            self.detailMachineId = nil
          }
        }
    }
  }

  @ViewBuilder
  private func machineDetail(for profile: WWNMachineProfile) -> some View {
    let machineStatus = model.status(for: profile.machineId)
    let running = machineStatus == .connected || machineStatus == .connecting
    let pinned = model.isPinned(profile.machineId)
    WWNMachineDetailView(
      profile: profile,
      status: machineStatus,
      thumbnailImage: model.thumbnailImage(for: profile),
      typeLabel: model.machineTypeLabel(for: profile),
      scopeLabel: model.machineScopeLabel(for: profile),
      subtitle: model.machineSubtitle(for: profile),
      summary: model.machineConfigurationSummary(for: profile),
      launchSupported: model.launchSupported(for: profile),
      isActive: profile.machineId == model.activeMachineId,
      isRunning: running,
      isPinned: pinned,
      pinLimitReached: !pinned && model.pinnedMachineIds.count >= WWNMachinesViewModel.maxPinnedMachines,
      tags: tagStore.tags(for: profile.machineId),
      allTags: tagStore.tags,
      onBack: { detailMachineId = nil },
      onEdit: { editorDestination = .edit(profile) },
      onDelete: { model.delete(profile) },
      onConnect: {
        model.connect(profile) {
          onConnect?()
        }
      },
      onStop: { model.disconnect(profile) },
      onFocus: { model.focusRunningMachine(profile) },
      onTogglePin: { _ = model.togglePinned(profile.machineId) },
      onToggleTag: { tag in
        let assigned = tagStore.isAssigned(tag.id, to: profile.machineId)
        tagStore.setAssigned(!assigned, tag: tag, to: profile.machineId)
      },
      onCreateTag: {
        tagEditorTag = nil
        tagEditorAssignToMachineId = profile.machineId
        showTagEditor = true
      }
    )
  }

  private var machinesGridPane: some View {
    #if os(macOS)
    // Avoid GeometryReader: it re-evaluates the entire grid on every window
    // bounds change during titlebar drag and amplifies move lag.
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        summaryStrip
        machinesGrid(forWidth: 1000)
      }
      .padding(16)
      .frame(maxWidth: 1320, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    #else
    GeometryReader { proxy in
      let detailWidth = max(proxy.size.width, 320)
      #if os(tvOS)
      // Room for `.card` focus lift (~1.1x) so edge cards are not clipped.
      let gridPadding: CGFloat = 60
      let gridSpacing: CGFloat = 48
      #else
      let gridPadding: CGFloat = 16
      let gridSpacing: CGFloat = 16
      #endif
      ScrollView {
        VStack(alignment: .leading, spacing: gridSpacing) {
          #if os(tvOS)
          HStack(alignment: .center, spacing: 24) {
            summaryStrip
            tvHeaderActions
          }
          .focusSection()
          #else
          summaryStrip
          #endif
          #if os(tvOS)
          // Search / Sort sit right of a short card row. A full-width
          // section gives Down from those buttons a target in its beam.
          machinesGrid(forWidth: detailWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
          #else
          machinesGrid(forWidth: detailWidth)
          #endif
        }
        .padding(gridPadding)
        .frame(maxWidth: 1600, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      #if os(tvOS)
      .scrollClipDisabled()
      #endif
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
    filteredProfiles(matching: searchQuery)
  }

  private func filteredProfiles(matching rawQuery: String) -> [WWNMachineProfile] {
    var base = model.profiles
    if let filterTagID,
       tagStore.tags.contains(where: { $0.id == filterTagID }) {
      base = base.filter { tagStore.isAssigned(filterTagID, to: $0.machineId) }
    }
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

  private var pinnedVisibleProfiles: [WWNMachineProfile] {
    visibleProfiles.filter { model.isPinned($0.machineId) }
  }

  private var unpinnedVisibleProfiles: [WWNMachineProfile] {
    visibleProfiles.filter { !model.isPinned($0.machineId) }
  }

  @ViewBuilder
  private func machinesGrid(forWidth width: CGFloat) -> some View {
    if visibleProfiles.isEmpty {
      machinesEmptyState
    } else if #available(iOS 14.0, tvOS 14.0, macOS 11.0, visionOS 1.0, *) {
      let columns = gridColumns(for: width)
      VStack(alignment: .leading, spacing: 20) {
        if !pinnedVisibleProfiles.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("Pinned")
              .font(.headline)
              .foregroundStyle(.secondary)
              .accessibility(addTraits: .isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
              ForEach(pinnedVisibleProfiles, id: \.machineId) { profile in
                machineCard(for: profile)
              }
            }
          }
        }
        if !unpinnedVisibleProfiles.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            if !pinnedVisibleProfiles.isEmpty {
              Text("Machines")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibility(addTraits: .isHeader)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
              ForEach(unpinnedVisibleProfiles, id: \.machineId) { profile in
                machineCard(for: profile)
              }
            }
          }
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(visibleProfiles, id: \.machineId) { profile in
          machineCard(for: profile)
        }
      }
    }
  }

  @ViewBuilder
  private var machinesEmptyState: some View {
    if #available(iOS 17.0, tvOS 17.0, macOS 14.0, visionOS 1.0, *) {
      ContentUnavailableView(
        "No Matching Machines",
        systemImage: "magnifyingglass",
        description: Text("Adjust search or add a new machine profile.")
      )
      .frame(maxWidth: .infinity)
      .padding(.top, 30)
    } else {
      VStack(spacing: 12) {
        Image(systemName: "magnifyingglass")
          .font(.largeTitle)
        Text("No Matching Machines")
          .font(.headline)
        Text("Adjust search or add a new machine profile.")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 30)
    }
  }

  @ViewBuilder
  private func machineCard(
    for profile: WWNMachineProfile,
    highlight: String? = nil,
    onSelect: (() -> Void)? = nil
  ) -> some View {
    let machineStatus = model.status(for: profile.machineId)
    WWNMachineCardView(
      profile: profile,
      status: machineStatus,
      thumbnailImage: model.thumbnailImage(for: profile),
      typeLabel: model.machineTypeLabel(for: profile),
      scopeLabel: model.machineScopeLabel(for: profile),
      subtitle: model.machineSubtitle(for: profile),
      summary: model.machineConfigurationSummary(for: profile),
      isActive: profile.machineId == model.activeMachineId,
      isPinned: model.isPinned(profile.machineId),
      tags: tagStore.tags(for: profile.machineId),
      searchQuery: highlight ?? searchQuery,
      onSelect: onSelect ?? { detailMachineId = profile.machineId }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    #if os(tvOS)
    .padding(20)
    #else
    .padding(1)
    #endif
    .id(profile.machineId)
    #if !os(macOS)
    .transition(.scale(scale: 0.95).combined(with: .opacity))
    #endif
  }

  // MARK: - Grid Layout

  private func gridColumns(for width: CGFloat) -> [GridItem] {
    let minCardWidth: CGFloat
    #if os(iOS)
    minCardWidth = width < 720 ? max(width - 32, 280) : 320
    #elseif os(tvOS)
    // 10-foot: wider cards, still a multi-column thumbnail grid.
    let availableWidth = width - 48
    if availableWidth >= 900 {
      minCardWidth = 360
    } else {
      minCardWidth = max(availableWidth / 2 - 16, 320)
    }
    #else
    // Prefer a card grid sooner on macOS so ~1000px windows don't feel like a list.
    let availableWidth = width - 32
    if availableWidth >= 680 {
      minCardWidth = 300
    } else {
      minCardWidth = max(availableWidth, 320)
    }
    #endif
    #if os(tvOS)
    return [GridItem(.adaptive(minimum: minCardWidth, maximum: 560), spacing: 24)]
    #else
    return [GridItem(.adaptive(minimum: minCardWidth, maximum: 520), spacing: 14)]
    #endif
  }

  @ViewBuilder
  private func machineEditor(for destination: MachineEditorDestination) -> some View {
    switch destination {
    case .add:
      WWNMachineEditorView(
        title: "Add Machine Profile",
        initial: nil,
        defaultType: kWWNMachineTypeNative
      ) { profile in
        model.upsert(profile)
      }
    case .edit(let profile):
      WWNMachineEditorView(title: "Edit Machine Profile", initial: profile) { updated in
        model.upsert(updated)
      }
    }
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
        // The strip and grid below it keep a stable height when a tag filter
        // toggles.
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

}

#if os(visionOS)
/// Liquid Glass minimized toolbar search (visionOS 26+). Expands in-toolbar
/// when selected. Earlier visionOS keeps the always-visible searchable field.
private struct WWNVisionMachinesSearchToolbarBehavior: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(visionOS 26.0, *) {
      content.searchToolbarBehavior(.minimize)
    } else {
      content
    }
  }
}
#endif

#if os(iOS)
/// iPhone: system `.searchable` owned by the split-detail navigation item.
/// Keep dismissing via `WWNHostKeyboard` when the split column changes.
@available(iOS 16.0, *)
private struct WWNIosPhoneSearchable: ViewModifier {
  let enabled: Bool
  @Binding var text: String

  func body(content: Content) -> some View {
    if enabled {
      // Default placement. The bottom-bar slot is the view controller's
      // `searchBarPlacementBarButtonItem` in `toolbarItems`
      // (`WWNPhoneIntegratedSearchToolbar`), not a second `.searchable`
      // placement and not `DefaultToolbarItem`.
      content.searchable(text: $text, prompt: "Search")
    } else {
      content
    }
  }
}

/// Pre-iOS 26 only. Older systems use a safe-area search row.
private struct WWNIosPhoneLegacyBottomChrome<Chrome: View>: ViewModifier {
  let enabled: Bool
  @ViewBuilder var chrome: () -> Chrome

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      if #available(iOS 15.0, *) {
        content.safeAreaInset(edge: .bottom, spacing: 0) { chrome() }
      } else {
        VStack(spacing: 0) {
          content
          chrome()
        }
      }
    } else {
      content
    }
  }
}

/// Applies `.focused` on iOS 15+; older hosts keep the field usable without FocusState.
private struct WWNSearchFieldFocus: ViewModifier {
  @Binding var isFocused: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 15.0, visionOS 1.0, *) {
      content.modifier(WWNSearchFieldFocusStateBridge(isFocused: $isFocused))
    } else {
      content
    }
  }
}

@available(iOS 15.0, visionOS 1.0, *)
private struct WWNSearchFieldFocusStateBridge: ViewModifier {
  @Binding var isFocused: Bool
  @FocusState private var focused: Bool

  func body(content: Content) -> some View {
    content
      .focused($focused)
      .onAppear { focused = isFocused }
      .backport.onChange(of: isFocused) { focused = $0 }
      .backport.onChange(of: focused) { isFocused = $0 }
  }
}
#endif

enum MachineEditorDestination: Identifiable {
  case add
  case edit(WWNMachineProfile)

  var id: String {
    switch self {
    case .add:
      return "add"
    case .edit(let profile):
      return profile.machineId
    }
  }
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
  @objc static func showSettings() {
    WWNMainWindowRouter.shared.showSettings()
  }

  @objc static func showMachinesPane() {
    WWNMainWindowRouter.shared.showMachines()
  }

  @objc(buildIOSMachinesControllerWithOnConnect:)
  static func buildIOSMachinesController(onConnect: (() -> Void)?) -> UIViewController {
    let work = { () -> UIViewController in
      MainActor.assumeIsolated {
        let root = WawonaRootView(onConnect: onConnect)
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
    if Thread.isMainThread {
      return work()
    }
    return DispatchQueue.main.sync(execute: work)
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
      // Wawona Terminal hosts keys on WWNTermSurface inside a plain NSWindow.
      // Swallowing printable keys here left the VT with a dead keyboard.
      if isTerminalKeySurfaceFocused() {
        return false
      }
      let blockedModifiers = event.modifierFlags.intersection([.command, .control, .option, .function])
      guard blockedModifiers.isEmpty else { return false }
      guard !isTextInputFocused() else { return false }
      return isTypingKey(event)
    }

    private static func isTerminalKeySurfaceFocused() -> Bool {
      guard let window = NSApp.keyWindow,
            let surfaceClass = NSClassFromString("WWNTermSurface") else { return false }
      if let content = window.contentView, content.isKind(of: surfaceClass) {
        return true
      }
      if let responder = window.firstResponder as? NSView {
        var view: NSView? = responder
        while let current = view {
          if current.isKind(of: surfaceClass) { return true }
          view = current.superview
        }
      }
      return false
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
    // Standalone fallback window: provide NavigationStack here. The split
    // path in WawonaMainWindowView already owns navigation chrome.
    let root = NavigationStack {
      WWNMachinesGridView(onConnect: onConnect)
    }
    let hosting = NSHostingController(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.minSize = NSSize(width: 1024, height: 720)
    window.toolbarStyle = .unified
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

#if os(iOS)
/// iOS 13–14 Machines list. Full chrome is `WWNMachinesGridViewModern` (iOS 15+).
struct WWNMachinesGridViewLegacy: View {
  let onConnect: (() -> Void)?
  var filterTagID: String? = nil
  var onClearTagFilter: (() -> Void)? = nil

  @ObservedObject private var model = WWNMachinesViewModel.shared
  @ObservedObject private var tagStore = WWNMachineTagStore.shared
  @State private var editorDestination: MachineEditorDestination?
  @State private var searchQuery = ""
  @State private var detailMachineId: String?

  private var profiles: [WWNMachineProfile] {
    let all = model.profiles
    let tagged: [WWNMachineProfile]
    if let filterTagID {
      tagged = all.filter { tagStore.tags(for: $0.machineId).contains { $0.id == filterTagID } }
    } else {
      tagged = all
    }
    let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return tagged }
    return tagged.filter { $0.name.localizedCaseInsensitiveContains(q) }
  }

  var body: some View {
    NavigationView {
      Group {
        if let detailMachineId,
           let profile = model.profiles.first(where: { $0.machineId == detailMachineId }) {
          legacyMachineDetail(profile)
        } else {
          legacyMachineList
        }
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .backport.machineEditorSheet(item: $editorDestination) { destination in
      switch destination {
      case .add:
        WWNMachineEditorView(
          title: "Add Machine Profile",
          initial: nil,
          defaultType: kWWNMachineTypeNative
        ) { model.upsert($0) }
      case .edit(let profile):
        WWNMachineEditorView(title: "Edit Machine Profile", initial: profile) {
          model.upsert($0)
        }
      }
    }
  }

  private var legacyMachineList: some View {
    VStack(spacing: 0) {
      TextField("Search machines", text: $searchQuery)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .padding(12)
      List {
        if filterTagID != nil, let onClearTagFilter {
          Button("Clear tag filter", action: onClearTagFilter)
        }
        ForEach(profiles, id: \.machineId) { profile in
          Button {
            detailMachineId = profile.machineId
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(profile.name.isEmpty ? "Unnamed Machine" : profile.name)
                .font(.headline)
              Text(model.machineSubtitle(for: profile))
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
    }
    .navigationBarTitle("Machines")
    .navigationBarItems(
      trailing: Button(action: { editorDestination = .add }) {
        Image(systemName: "plus")
      }
    )
  }

  private func legacyMachineDetail(_ profile: WWNMachineProfile) -> some View {
    let status = model.status(for: profile.machineId)
    let running = status == .connected || status == .connecting
    return List {
      Section {
        Text(model.machineConfigurationSummary(for: profile))
          .font(.footnote)
          .foregroundColor(.secondary)
      }
      Section {
        if running {
          Button("Focus") { model.focusRunningMachine(profile) }
          Button("Stop") { model.disconnect(profile) }
            .foregroundColor(.red)
        } else {
          Button("Start") {
            model.connect(profile) { onConnect?() }
          }
          .disabled(!model.launchSupported(for: profile))
        }
        Button("Edit") { editorDestination = .edit(profile) }
        Button("Delete") {
          model.delete(profile)
          detailMachineId = nil
        }
        .foregroundColor(.red)
        .disabled(running)
      }
      Section(header: Text("Pin")) {
        let pinned = model.isPinned(profile.machineId)
        Button(pinned ? "Unpin" : "Pin") {
          _ = model.togglePinned(profile.machineId)
        }
      }
      Section(header: Text("Tags")) {
        ForEach(tagStore.tags) { tag in
          let assigned = tagStore.isAssigned(tag.id, to: profile.machineId)
          Button(action: {
            tagStore.setAssigned(!assigned, tag: tag, to: profile.machineId)
          }) {
            HStack {
              Text(tag.name)
              Spacer()
              if assigned {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }
    }
    .navigationBarTitle(profile.name.isEmpty ? "Machine" : profile.name)
    .navigationBarItems(
      leading: Button("Back") { detailMachineId = nil }
    )
  }
}
#endif
