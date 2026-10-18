#if os(watchOS)
import SwiftUI
import WawonaModel
import WawonaUIContracts

private struct WatchEnvironmentGroup: Identifiable {
    var category: EnvironmentCategory
    var items: [ResolvedEnvironmentEntry]
    var id: EnvironmentCategory { category }
}

/// Same catalog as iOS `EnvironmentVariablesView`: every resolved variable,
/// set / unset / revert, plus a custom key. Watch pushes a page per variable.
struct WatchEnvironmentList: View {
    @ObservedObject var preferences: WawonaPreferences
    /// Non-nil writes machine draft overrides instead of global prefs.
    var machineEnvironment: Binding<EnvironmentOverrideMap>? = nil

    @State private var category: EnvironmentCategory?
    @State private var confirmReset = false
    @State private var searchQuery = ""
    @State private var presentAdd = false
    /// Row push. A `NavigationLink(value:)` here pops the settings section
    /// instead of opening the variable. Same binding push as the section list.
    @State private var editingName: String?
    @State private var searching = false
    @State private var showsTopItems = true
    @State private var topFaded = false
    @State private var contentWidth: CGFloat = 184
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var perMachine: Bool { machineEnvironment != nil }

    /// Grows the search control into the pill. A tap on the pill edits the query.
    private func searchTapped() {
        withAnimation(WatchSearchInput.animation) {
            searching = true
        }
    }

    private func cancelSearch() {
        withAnimation(WatchSearchInput.animation) {
            searchQuery = ""
            searching = false
        }
    }

    private var rows: [ResolvedEnvironmentEntry] {
        preferences.resolvedEnvironment(
            for: nil,
            machineOverrideMap: perMachine ? (machineEnvironment?.wrappedValue ?? [:]) : [:]
        )
        .filter { !$0.isSecret }
    }

    private var categories: [EnvironmentCategory] {
        let present = Set(rows.map(\.category))
        return EnvironmentCategory.allCases.filter { present.contains($0) && $0 != .secrets }
    }

    private var filteredRows: [ResolvedEnvironmentEntry] {
        let base: [ResolvedEnvironmentEntry]
        if let category {
            base = rows.filter { $0.category == category }
        } else {
            base = rows
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var grouped: [WatchEnvironmentGroup] {
        let present = Dictionary(grouping: filteredRows, by: \.category)
        return categories.compactMap { category in
            guard let items = present[category], !items.isEmpty else { return nil }
            return WatchEnvironmentGroup(category: category, items: items)
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(nil, title: "All")
                        ForEach(categories, id: \.self) { item in
                            chip(item, title: watchEnvironmentCategoryTitle(item))
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(grouped) { group in
                Section {
                    ForEach(group.items) { row in
                        Button {
                            editingName = row.name
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: watchEnvironmentIcon(group.category))
                                    .foregroundStyle(watchEnvironmentAccent(group.category))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(WatchSearchHighlight.name(row.name, query: searchQuery, scheme: colorScheme))
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                    Text(watchEnvironmentStatus(row))
                                        .font(.caption2)
                                        .foregroundStyle(row.isUnset ? .red : .secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.forward")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityIdentifier("wwn.settings.environment.row.\(row.name)")
                    }
                } header: {
                    Label(
                        watchEnvironmentCategoryTitle(group.category),
                        systemImage: watchEnvironmentIcon(group.category)
                    )
                    .foregroundStyle(watchEnvironmentAccent(group.category))
                }
            }
            if !perMachine {
                Section("Compositor") {
                    TextField("Wayland Display", text: $preferences.waylandDisplay)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: preferences.waylandDisplay) { _, _ in preferences.save() }
                    Text("Optional clients install with wpm from Wawona Terminal.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Tint the rows only. Applied before `.toolbar` so the search bar
        // keeps default glass (neutral x, blue plus).
        .tint(WawonaSettingsHubChrome.accentColor(for: .environment))
        .modifier(WatchSearchLift(active: searching))
        // System title, as on Machines. Leaves with reset and back so the bar
        // shrinks to the clock row.
        .navigationTitle(showsTopItems ? "Environment Variables" : "")
        // Own back button: the system one cannot fade with the other items.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if showsTopItems {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("wwn.settings.environment.back")
                    .modifier(WatchSearchHiddenWhileSearching(searching: topFaded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmReset = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset Environment")
                    .accessibilityIdentifier("wwn.settings.environment.reset")
                    .modifier(WatchSearchHiddenWhileSearching(searching: topFaded))
                }
            }
            ToolbarItem(id: "wwn.settings.environment.bottom", placement: .bottomBar) {
                WatchSearchBottomBar(
                    query: $searchQuery,
                    searching: searching,
                    rowWidth: max(120, contentWidth - 30),
                    addLabel: "Add Variable",
                    addIdentifier: "wwn.settings.environment.add",
                    onSearch: searchTapped,
                    onAdd: { presentAdd = true },
                    onCancel: cancelSearch
                )
            }
        }
        // The reset dialog covers this page but not its live bottom bar.
        .toolbar(confirmReset ? .hidden : .automatic, for: .bottomBar)
        .task(id: searching) {
            if searching {
                topFaded = true
                try? await Task.sleep(for: .seconds(WatchSearchInput.expandDuration))
                guard !Task.isCancelled else { return }
                showsTopItems = false
            } else {
                // Re-added items need a moment to mount in the bar before
                // the fade-in, or they appear at full opacity.
                showsTopItems = true
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                withAnimation(WatchSearchInput.animation) { topFaded = false }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: WatchContentWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(WatchContentWidthKey.self) { width in
            guard width > 1, abs(width - contentWidth) > 0.5 else { return }
            contentWidth = width
        }
        .navigationDestination(isPresented: $presentAdd) {
            WatchEnvironmentAdd(
                preferences: preferences,
                machineEnvironment: machineEnvironment
            )
        }
        .navigationDestination(item: $editingName) { name in
            WatchEnvironmentDetail(
                name: name,
                preferences: preferences,
                machineEnvironment: machineEnvironment
            )
        }
        .confirmationDialog("Reset environment", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Wawona Defaults") { resetManaged() }
            Button("Reset All Overrides", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(perMachine
                ? "Reset this machine to Wawona defaults, or clear every override."
                : "Reset Wawona-managed variables, or clear every global override.")
        }
    }

    private func chip(_ value: EnvironmentCategory?, title: String) -> some View {
        let selected = category == value
        let tint = value.map(watchEnvironmentAccent) ?? Color.secondary
        let icon = value.map(watchEnvironmentIcon) ?? "square.grid.2x2"
        return Button {
            category = value
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(selected ? 0.22 : 0.10)))
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("wwn.settings.environment.chip.\(title)")
    }

    private func resetManaged() {
        if let machineEnvironment {
            var next = machineEnvironment.wrappedValue
            EnvironmentResolver.resetWawonaManaged(&next)
            machineEnvironment.wrappedValue = next
            return
        }
        preferences.resetEnvironmentManaged()
    }

    private func resetAll() {
        if let machineEnvironment {
            machineEnvironment.wrappedValue = [:]
            return
        }
        preferences.resetEnvironmentAll()
    }
}

private struct WatchEnvironmentDetail: View {
    let name: String
    @ObservedObject var preferences: WawonaPreferences
    var machineEnvironment: Binding<EnvironmentOverrideMap>?

    @State private var value = ""
    @State private var saved = false

    private var perMachine: Bool { machineEnvironment != nil }

    private var entry: ResolvedEnvironmentEntry? {
        preferences.resolvedEnvironment(
            for: nil,
            machineOverrideMap: perMachine ? (machineEnvironment?.wrappedValue ?? [:]) : [:]
        )
        .first { $0.name == name }
    }

    private var doc: EnvironmentVariableDoc {
        entry?.documentation ?? EnvironmentCatalog.documentation(for: name)
    }

    var body: some View {
        Form {
            Section {
                TextField("Value", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("wwn.settings.environment.edit.value")
                Button("Save") { apply(.set(value)) }
                    .accessibilityIdentifier("wwn.settings.environment.detail.save")
                if saved {
                    Text("Saved")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            } header: {
                Text(watchEnvironmentStatus(entry))
            }

            Button("Unset") { apply(.unset) }
            if entry?.isOverridden == true || entry?.isUnset == true {
                Button("Revert to Default", role: .destructive) { apply(nil) }
            }

            if !doc.typicalDefault.isEmpty {
                Section("Typical Default") {
                    Button(doc.typicalDefault) {
                        value = doc.typicalDefault
                        apply(.set(doc.typicalDefault))
                    }
                }
            }

            if !doc.examples.isEmpty {
                Section("Examples") {
                    ForEach(doc.examples, id: \.self) { example in
                        Button(example) {
                            value = example
                            apply(.set(example))
                        }
                    }
                }
            }

            if !doc.summary.isEmpty || !doc.details.isEmpty {
                Section("Documentation") {
                    if !doc.summary.isEmpty {
                        Text(doc.summary)
                            .font(.caption2)
                    }
                    if !doc.details.isEmpty {
                        Text(doc.details)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(name)
        .onAppear {
            value = entry?.isUnset == true ? "" : (entry?.value ?? "")
        }
    }

    private func apply(_ override: EnvironmentOverride?) {
        watchWriteEnvironment(
            name: name,
            override: override,
            preferences: preferences,
            machineEnvironment: machineEnvironment
        )
        saved = true
    }
}

private struct WatchEnvironmentAdd: View {
    @ObservedObject var preferences: WawonaPreferences
    var machineEnvironment: Binding<EnvironmentOverrideMap>?
    @State private var key = ""
    @State private var value = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("KEY", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Value", text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Set") {
                let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                watchWriteEnvironment(
                    name: name,
                    override: .set(value.trimmingCharacters(in: .whitespacesAndNewlines)),
                    preferences: preferences,
                    machineEnvironment: machineEnvironment
                )
                dismiss()
            }
        }
        .navigationTitle("Add Variable")
    }
}

@MainActor
private func watchWriteEnvironment(
    name: String,
    override: EnvironmentOverride?,
    preferences: WawonaPreferences,
    machineEnvironment: Binding<EnvironmentOverrideMap>?
) {
    if let machineEnvironment {
        var next = machineEnvironment.wrappedValue
        if let override {
            next[name] = override
        } else {
            EnvironmentResolver.resetOne(&next, name: name)
        }
        machineEnvironment.wrappedValue = next
        return
    }
    preferences.setEnvironmentOverride(name: name, override: override)
}

private func watchEnvironmentIcon(_ category: EnvironmentCategory) -> String {
    switch category {
    case .session: return "slider.horizontal.3"
    case .graphics: return "paintpalette"
    case .shell: return "terminal"
    case .xdg: return "folder"
    case .fonts: return "textformat"
    case .input: return "keyboard"
    case .debug: return "ant"
    case .secrets: return "key"
    case .user: return "person"
    }
}

private func watchEnvironmentAccent(_ category: EnvironmentCategory) -> Color {
    switch category {
    case .session: return .blue
    case .graphics: return .purple
    case .shell: return .orange
    case .xdg: return Color(red: 0.35, green: 0.34, blue: 0.84)
    case .fonts: return Color(red: 0.19, green: 0.69, blue: 0.78)
    case .input: return .green
    case .debug: return .red
    case .secrets: return .yellow
    case .user: return Color(red: 0, green: 0.78, blue: 0.75)
    }
}

private func watchEnvironmentCategoryTitle(_ category: EnvironmentCategory) -> String {
    switch category {
    case .session: return "Session"
    case .graphics: return "Graphics"
    case .shell: return "Shell"
    case .xdg: return "XDG"
    case .fonts: return "Fonts"
    case .input: return "Input"
    case .debug: return "Debug"
    case .secrets: return "Secrets"
    case .user: return "User"
    }
}

private func watchEnvironmentStatus(_ row: ResolvedEnvironmentEntry?) -> String {
    guard let row else { return "Default" }
    if row.isUnset { return "Unset" }
    if row.isOverridden {
        return row.displayValue.isEmpty ? "Custom (empty)" : "Custom \(row.displayValue)"
    }
    return row.displayValue.isEmpty ? "Default" : row.displayValue
}
#endif
