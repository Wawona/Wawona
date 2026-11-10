import SwiftUI
import WawonaModel

extension EnvironmentCategory {
    var iconName: String {
        switch self {
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

    var accentColor: Color {
        switch self {
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

    var displayName: String {
        switch self {
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
}

/// Native SwiftUI environment variables settings view.
/// Follows Apple Human Interface Guidelines and navigation standards.
public struct EnvironmentVariablesView: View {
    @ObservedObject public var preferences: WawonaPreferences
    public var profileStore: MachineProfileStore?
    public var machineID: String?
    /// When true, edits write to the machine's runtimeOverrides.environment.
    public var perMachine: Bool
    /// Optional draft map for editors that save later.
    public var draftMachineOverrides: Binding<EnvironmentOverrideMap>?

    #if os(macOS) || os(iOS) || os(visionOS)
    /// Global Settings chrome owns Add (+ Done / close) when non-nil.
    /// Machine editors leave this nil and keep a local trailing Add.
    @Environment(\.wwnSettingsChromeBridge) private var chromeBridge
    #endif

    @State private var searchText: String = ""
    @State private var selectedCategory: EnvironmentCategory? = nil
    @State private var confirmResetAll: Bool = false
    @State private var isPresentingNewSheet: Bool = false

    public init(
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore? = nil,
        machineID: String? = nil,
        perMachine: Bool = false,
        draftMachineOverrides: Binding<EnvironmentOverrideMap>? = nil
    ) {
        self.preferences = preferences
        self.profileStore = profileStore
        self.machineID = machineID
        self.perMachine = perMachine
        self.draftMachineOverrides = draftMachineOverrides
    }

    private var profile: MachineProfile? {
        guard let profileStore, let machineID else { return nil }
        return profileStore.profile(for: machineID)
    }

    private var machineOverrides: EnvironmentOverrideMap {
        if let draft = draftMachineOverrides {
            return draft.wrappedValue
        }
        return profile?.runtimeOverrides.environment ?? [:]
    }

    private var allRows: [ResolvedEnvironmentEntry] {
        preferences.resolvedEnvironment(
            for: perMachine ? profile : nil,
            machineOverrideMap: perMachine ? machineOverrides : [:]
        )
        .filter { !$0.isSecret }
    }

    private var filteredRows: [ResolvedEnvironmentEntry] {
        allRows.filter { row in
            if let selectedCategory, row.category != selectedCategory { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty { return true }
            return row.name.localizedCaseInsensitiveContains(query)
                || (row.value ?? "").localizedCaseInsensitiveContains(query)
                || (row.help ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var activeCategories: [EnvironmentCategory] {
        let cats = Set(allRows.map(\.category))
        return EnvironmentCategory.allCases.filter { cats.contains($0) && $0 != .secrets }
    }

    /// Global Settings macOS chrome already owns NSToolbar (Done / Add). A
    /// second `.searchable` insert into that bar SIGTRAPs AppKit on macOS 26.
    /// Keep toolbar searchable for machine editors / iOS; in-content field here.
    /// tvOS also searches in content: toolbar `.searchable` there stacks a
    /// second bar over the chip strip and the list.
    private var usesInContentSearch: Bool {
        #if os(macOS)
        chromeBridge != nil
        #elseif os(tvOS)
        true
        #else
        false
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            if usesInContentSearch {
                searchField
            }

            categoryPicker
            #if os(tvOS)
                .focusSection()
            #endif

            Divider()

            List {
                if filteredRows.isEmpty {
                    WawonaEmptyState(
                        "No Variables Found",
                        systemImage: "magnifyingglass",
                        description: Text("No environment variables match your search or filter.")
                    )
                } else if selectedCategory == nil && searchText.isEmpty {
                    ForEach(activeCategories, id: \.self) { category in
                        let categoryRows = filteredRows.filter { $0.category == category }
                        if !categoryRows.isEmpty {
                            Section {
                                ForEach(categoryRows) { row in
                                    rowView(for: row)
                                }
                            } header: {
                                EnvironmentCategorySectionHeader(category: category)
                            }
                        }
                    }
                } else if let selectedCategory {
                    Section {
                        ForEach(filteredRows) { row in
                            rowView(for: row)
                        }
                    } header: {
                        EnvironmentCategorySectionHeader(category: selectedCategory)
                    }
                } else {
                    Section {
                        ForEach(filteredRows) { row in
                            rowView(for: row)
                        }
                    }
                }

                Section {
                    WawonaButton("Reset Wawona Defaults") {
                        resetManaged()
                    }
                    .accessibility(identifier: "wwn.settings.environment.resetManaged")

                    WawonaButton("Reset All Overrides", role: .destructive) {
                        confirmResetAll = true
                    }
                    .accessibility(identifier: "wwn.settings.environment.resetAll")
                } footer: {
                    Text(perMachine
                        ? "Machine overrides take precedence over global environment variables."
                        : "Wawona manages core Wayland and graphics environment variables automatically.")
                }
            }
            #if os(iOS) || os(visionOS)
            .backport.insetGroupedList()
            #elseif os(tvOS)
            .listStyle(.grouped)
            #else
            .listStyle(.inset)
            #endif
        }
        .modifier(EnvironmentVariablesSearchableModifier(
            searchText: $searchText,
            enabled: !usesInContentSearch
        ))
        .backport.navigationTitle("Environment Variables", inline: true)
        .accessibility(identifier: "wwn.settings.environment")
        #if os(macOS) || os(iOS) || os(visionOS)
        .wwnSettingsChromeAddRegistration(onAdd: { isPresentingNewSheet = true })
        .modifier(EnvironmentVariablesLocalAddToolbar(usesLocalAdd: chromeBridge == nil) {
            isPresentingNewSheet = true
        })
        #elseif os(tvOS)
        // One primary item. navigationActions with an empty leading slot
        // rendered two overlapping toolbar buttons on tvOS.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Section tint fills the primary toolbar platter and its label
                // alike (blank cyan pill). Default tint matches Done.
                Button("Add Variable", systemImage: "plus") {
                    isPresentingNewSheet = true
                }
                .tint(nil)
                .accessibility(identifier: "wwn.settings.environment.new")
            }
        }
        #else
        // watch: local trailing Add (no Global Settings chrome bridge).
        .backport.navigationActions(trailingIsPrimary: true, leading: { EmptyView() }, trailing: {
                WawonaButton {
                    isPresentingNewSheet = true
                } label: {
                    WawonaLabel("Add Variable", systemImage: "plus")
                }
                .accessibility(identifier: "wwn.settings.environment.new")
            })
        #endif
        .sheet(isPresented: $isPresentingNewSheet) {
            NewEnvironmentVariableSheet { name, value in
                saveNew(name: name, value: value)
            }
        }
        .alert(isPresented: $confirmResetAll) {
            Alert(title: Text("Reset all environment overrides?"),
                  message: Text(perMachine
                    ? "Clears this machine's overrides so it inherits global defaults."
                    : "Clears global overrides. Catalog defaults still apply."),
                  primaryButton: .destructive(Text("Reset All")) { resetAll() },
                  secondaryButton: .cancel())
        }
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(tvOS)
        TextField("Search variables", text: $searchText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 60)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .accessibility(identifier: "wwn.settings.environment.search")
        #else
        TextField("Search variables", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibility(identifier: "wwn.settings.environment.search")
        #endif
    }

    /// tvOS accentColor is white, which made the selected All chip a white
    /// fill under a white label.
    private var allChipAccent: Color {
        #if os(tvOS)
        Color.blue
        #else
        Color.accentColor
        #endif
    }

    /// Horizontal filter chips (Android Env Vars FilterChip parity). Not a
    /// segmented control: long category lists stay scrollable with color marks.
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                EnvironmentCategoryChip(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    accent: allChipAccent,
                    selected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(activeCategories, id: \.self) { cat in
                    EnvironmentCategoryChip(
                        title: cat.displayName,
                        systemImage: cat.iconName,
                        accent: cat.accentColor,
                        selected: selectedCategory == cat
                    ) {
                        selectedCategory = cat
                    }
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
            #else
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            #endif
            .accessibility(identifier: "wwn.settings.environment.category")
        }
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }

    private func rowView(for row: ResolvedEnvironmentEntry) -> some View {
        NavigationLink {
            EnvironmentVariableDetailView(
                variableName: row.name,
                initialEntry: row,
                preferences: preferences,
                profileStore: profileStore,
                machineID: machineID,
                perMachine: perMachine,
                draftMachineOverrides: draftMachineOverrides
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(row.category.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: row.category.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(row.category.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if row.isUnset {
                        Text("(Unset)")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if row.isOverridden {
                        Text(row.displayValue.isEmpty ? "(Empty)" : row.displayValue)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    } else {
                        Text(row.displayValue.isEmpty ? "(Default)" : row.displayValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if row.isOverridden {
                    Text("Custom")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundColor(.orange)
                } else if row.isUnset {
                    Text("Unset")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.15)))
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .accessibility(identifier: "wwn.settings.environment.row.\(row.name)")
        .backport.supplementarySwipeActions {
            if row.isOverridden || row.isUnset {
                WawonaButton("Reset") {
                    resetOne(row.name)
                }
                .accentColor(.orange)
            }
        }
        .contextMenu {
            WawonaButton {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.name, forType: .string)
                #elseif os(iOS) || os(visionOS)
                UIPasteboard.general.string = row.name
                #endif
            } label: {
                WawonaLabel("Copy Name", systemImage: "doc.on.doc")
            }

            if !row.displayValue.isEmpty {
                WawonaButton {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.displayValue, forType: .string)
                    #elseif os(iOS) || os(visionOS)
                    UIPasteboard.general.string = row.displayValue
                    #endif
                } label: {
                    WawonaLabel("Copy Value", systemImage: "doc.on.clipboard")
                }
            }

            if row.isOverridden || row.isUnset {
                WawonaButton(role: .destructive) {
                    resetOne(row.name)
                } label: {
                    WawonaLabel("Reset to Default", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private func saveNew(name: String, value: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = EnvironmentOverride.set(trimmedValue)

        if let draft = draftMachineOverrides {
            var next = draft.wrappedValue
            next[trimmedName] = override
            draft.wrappedValue = next
            return
        }
        if perMachine {
            guard var profile = profile, let profileStore else { return }
            var env = profile.runtimeOverrides.environment ?? [:]
            env[trimmedName] = override
            profile.runtimeOverrides.environment = env
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.setEnvironmentOverride(name: trimmedName, override: override)
        }
    }

    private func resetOne(_ name: String) {
        if let draft = draftMachineOverrides {
            var next = draft.wrappedValue
            EnvironmentResolver.resetOne(&next, name: name)
            draft.wrappedValue = next
            return
        }
        if perMachine {
            guard var profile = profile, let profileStore else { return }
            var env = profile.runtimeOverrides.environment ?? [:]
            EnvironmentResolver.resetOne(&env, name: name)
            profile.runtimeOverrides.environment = env.isEmpty ? nil : env
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.setEnvironmentOverride(name: name, override: nil)
        }
    }

    private func resetManaged() {
        if let draft = draftMachineOverrides {
            var next = draft.wrappedValue
            EnvironmentResolver.resetWawonaManaged(&next)
            draft.wrappedValue = next
            return
        }
        if perMachine {
            guard var profile = profile, let profileStore else { return }
            var env = profile.runtimeOverrides.environment ?? [:]
            EnvironmentResolver.resetWawonaManaged(&env)
            profile.runtimeOverrides.environment = env.isEmpty ? nil : env
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.resetEnvironmentManaged()
        }
    }

    private func resetAll() {
        if let draft = draftMachineOverrides {
            draft.wrappedValue = [:]
            return
        }
        if perMachine {
            guard var profile = profile, let profileStore else { return }
            profile.runtimeOverrides.environment = nil
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.resetEnvironmentAll()
        }
    }
}

// MARK: - Detail Pageview

/// Dedicated detail pageview displaying documentation, defaults, examples, and live editing.
public struct EnvironmentVariableDetailView: View {
    public let variableName: String
    public let initialEntry: ResolvedEnvironmentEntry?
    @ObservedObject public var preferences: WawonaPreferences
    public var profileStore: MachineProfileStore?
    public var machineID: String?
    public var perMachine: Bool
    public var draftMachineOverrides: Binding<EnvironmentOverrideMap>?
    public var onBack: (() -> Void)?

    @Environment(\.presentationMode) private var presentationMode
    private func dismiss() { presentationMode.wrappedValue.dismiss() }
    @State private var currentValue: String
    @State private var showSaveSuccess: Bool = false

    public init(
        variableName: String,
        initialEntry: ResolvedEnvironmentEntry?,
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore? = nil,
        machineID: String? = nil,
        perMachine: Bool = false,
        draftMachineOverrides: Binding<EnvironmentOverrideMap>? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.variableName = variableName
        self.initialEntry = initialEntry
        self.preferences = preferences
        self.profileStore = profileStore
        self.machineID = machineID
        self.perMachine = perMachine
        self.draftMachineOverrides = draftMachineOverrides
        self.onBack = onBack
        self._currentValue = State(initialValue: initialEntry?.value ?? "")
    }

    public init(
        initialEntry: ResolvedEnvironmentEntry?,
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore? = nil,
        machineID: String? = nil,
        perMachine: Bool = false,
        draftMachineOverrides: Binding<EnvironmentOverrideMap>? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            variableName: initialEntry?.name ?? "",
            initialEntry: initialEntry,
            preferences: preferences,
            profileStore: profileStore,
            machineID: machineID,
            perMachine: perMachine,
            draftMachineOverrides: draftMachineOverrides,
            onBack: onBack
        )
    }

    private var profile: MachineProfile? {
        guard let profileStore, let machineID else { return nil }
        return profileStore.profile(for: machineID)
    }

    private var machineOverrides: EnvironmentOverrideMap {
        if let draft = draftMachineOverrides {
            return draft.wrappedValue
        }
        return profile?.runtimeOverrides.environment ?? [:]
    }

    private var currentEntry: ResolvedEnvironmentEntry? {
        let all = preferences.resolvedEnvironment(
            for: perMachine ? profile : nil,
            machineOverrideMap: perMachine ? machineOverrides : [:]
        )
        return all.first(where: { $0.name == variableName }) ?? initialEntry
    }

    private var doc: EnvironmentVariableDoc {
        if let currentEntry {
            return currentEntry.documentation
        }
        return EnvironmentCatalog.documentation(for: variableName)
    }

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let cat = currentEntry?.category {
                            WawonaLabel(cat.rawValue.capitalized, systemImage: cat.iconName)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(cat.accentColor.opacity(0.15)))
                                .foregroundColor(cat.accentColor)
                        }
                        if currentEntry?.isOverridden == true {
                            Text("Custom Override")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                                .foregroundColor(.orange)
                        } else if currentEntry?.isUnset == true {
                            Text("Unset")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.red.opacity(0.15)))
                                .foregroundColor(.red)
                        } else {
                            Text("Default")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        WawonaTextField(
                            "Value",
                            text: $currentValue,
                            prompt: Text(doc.typicalDefault.isEmpty ? "Enter value" : doc.typicalDefault)
                        )
                        .font(.system(.body, design: .monospaced))
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .backport.onSubmit { applySave() }
                        .accessibility(identifier: "wwn.settings.environment.edit.value")

                        WawonaButton("Save") {
                            applySave()
                        }
                        .backport.borderedButton(prominent: true)
                        .accessibility(identifier: "wwn.settings.environment.detail.save")
                    }

                    if showSaveSuccess {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Saved")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Value")
            } footer: {
                if currentEntry?.isOverridden == true {
                    WawonaButton("Revert to Default", role: .destructive) {
                        revertToDefault()
                    }
                    .font(.caption)
                }
            }

            if !doc.summary.isEmpty || !doc.details.isEmpty {
                Section(header: Text("Documentation")) {
                    if !doc.summary.isEmpty {
                        Text(doc.summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    if !doc.details.isEmpty {
                        Text(doc.details)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .backport.selectableText()
                    }
                }
            }

            if !doc.typicalDefault.isEmpty {
                Section(header: Text("Typical Default")) {
                    HStack {
                        Text(doc.typicalDefault)
                            .font(.system(.body, design: .monospaced))
                            .backport.selectableText()
                        Spacer()
                        WawonaButton("Use Default") {
                            currentValue = doc.typicalDefault
                            applySave()
                        }
                        .font(.caption.weight(.medium))
                        .backport.borderedButton()
                    }
                }
            }

            if !doc.examples.isEmpty {
                Section(header: Text("Examples")) {
                    ForEach(doc.examples, id: \.self) { example in
                        HStack {
                            Text(example)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .backport.selectableText()
                            Spacer()
                            WawonaButton("Use") {
                                currentValue = example
                                applySave()
                            }
                            .font(.caption)
                            .backport.borderedButton()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section(header: Text("Details")) {
                WawonaLabeledContent("Variable Name", value: variableName)
                if let cat = currentEntry?.category {
                    WawonaLabeledContent("Category", value: cat.rawValue.capitalized)
                }
                if let mut = currentEntry?.mutability {
                    WawonaLabeledContent("Mutability", value: mut.rawValue.capitalized)
                }
                if let ownedBy = currentEntry?.ownedBy, !ownedBy.isEmpty {
                    WawonaLabeledContent("Managed By", value: ownedBy)
                }
                WawonaLabeledContent("Scope", value: perMachine ? "Per-Machine Override" : "Global Preference")
            }
        }
        .backport.groupedForm()
        .backport.navigationTitle(variableName, inline: true)
        #if os(tvOS)
        // Explicit Back. Menu alone was unreliable; Settings Done on the root
        // dismissed the whole host instead of popping this push.
        .backport.navigationActions {
            WawonaButton("Back") {
                if let onBack {
                    onBack()
                } else {
                    dismiss()
                }
            }
            .accessibility(identifier: "wwn.settings.environment.detail.back")
        } trailing: {
            EmptyView()
        }
        #endif
        .accessibility(identifier: "wwn.settings.environment.detail")
    }

    private func applySave() {
        let valueToSave = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = EnvironmentOverride.set(valueToSave)
        if let draft = draftMachineOverrides {
            var next = draft.wrappedValue
            next[variableName] = override
            draft.wrappedValue = next
        } else if perMachine {
            guard var profile = profile, let profileStore else { return }
            var env = profile.runtimeOverrides.environment ?? [:]
            env[variableName] = override
            profile.runtimeOverrides.environment = env
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.setEnvironmentOverride(name: variableName, override: override)
        }
        showSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveSuccess = false
        }
    }

    private func revertToDefault() {
        if let draft = draftMachineOverrides {
            var next = draft.wrappedValue
            EnvironmentResolver.resetOne(&next, name: variableName)
            draft.wrappedValue = next
        } else if perMachine {
            guard var profile = profile, let profileStore else { return }
            var env = profile.runtimeOverrides.environment ?? [:]
            EnvironmentResolver.resetOne(&env, name: variableName)
            profile.runtimeOverrides.environment = env.isEmpty ? nil : env
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.setEnvironmentOverride(name: variableName, override: nil)
        }
        currentValue = currentEntry?.value ?? ""
    }
}

// MARK: - New Variable Modal Sheet

struct NewEnvironmentVariableSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    private func dismiss() { presentationMode.wrappedValue.dismiss() }
    @State private var name: String = ""
    @State private var value: String = ""
    var onAdd: (String, String) -> Void

    var body: some View {
        WawonaBackport<Any>.navigation {
            Form {
                Section(header: Text("Variable Identity")) {
                    WawonaTextField("VARIABLE_NAME", text: $name, prompt: Text("e.g. MOZ_ENABLE_WAYLAND"))
                        .font(.system(.body, design: .monospaced))
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                        .accessibility(identifier: "wwn.settings.environment.new.name")
                }
                Section(header: Text("Initial Value")) {
                    WawonaTextField("Value", text: $value, prompt: Text("e.g. 1"))
                        .font(.system(.body, design: .monospaced))
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                        .accessibility(identifier: "wwn.settings.environment.new.value")
                }
            }
            .backport.groupedForm()
            .backport.navigationTitle("New Variable", inline: true)
            .backport.navigationActions(trailingIsPrimary: false, leading: {
                    WawonaButton("Cancel", role: .cancel) { dismiss() }
                }, trailing: {
                    WawonaButton("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onAdd(trimmed, value)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibility(identifier: "wwn.settings.environment.new.confirm")
                })
        }
    }
}

/// Toolbar `.searchable` only when Global Settings is not already owning
/// NSToolbar (macOS). Conditional omit avoids a second bar insert SIGTRAP.
private struct EnvironmentVariablesSearchableModifier: ViewModifier {
    @Binding var searchText: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.backport.searchable(text: $searchText, prompt: "Search variables")
        } else {
            content
        }
    }
}

#if os(macOS) || os(iOS) || os(visionOS)
/// Machine-editor / standalone host: local trailing Add when Global Settings
/// chrome bridge is absent. Inside Global Settings, Add lives on host chrome.
private struct EnvironmentVariablesLocalAddToolbar: ViewModifier {
    let usesLocalAdd: Bool
    let onAdd: () -> Void

    func body(content: Content) -> some View {
        if usesLocalAdd {
            content.backport.navigationActions(
                trailingIsPrimary: true,
                leading: { EmptyView() },
                trailing: {
                    WawonaButton(action: onAdd) {
                        WawonaLabel("Add Variable", systemImage: "plus")
                    }
                    .accessibility(identifier: "wwn.settings.environment.new")
                }
            )
        } else {
            content
        }
    }
}
#endif

/// Section header: tinted icon + title (Android `EnvCategoryHeader` parity).
private struct EnvironmentCategorySectionHeader: View {
    let category: EnvironmentCategory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(category.accentColor)
                .accessibility(hidden: true)
            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(category.accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(category.displayName))
    }
}

/// Colored category chip for Env Vars filter strip (Android FilterChip parity).
/// Accent lives in the capsule fill. Label stays high-contrast: soft accent
/// glyphs wash out on tvOS / visionOS when the chip is unfocused.
private struct EnvironmentCategoryChip: View {
    let title: String
    let systemImage: String
    let accent: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
            }
            .foregroundColor(labelColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .backport.background(fillColor, in: Capsule())
            .overlay(chipStroke)
        }
        #if os(tvOS)
        .buttonStyle(WWNTvChipButtonStyle())
        #else
        .buttonStyle(PlainButtonStyle())
        #endif
        .accessibility(addTraits: selected ? .isSelected : [])
        .accessibility(label: Text(title))
    }

    /// visionOS / tvOS glass vibrancy makes soft accent glyphs disappear. White
    /// on an opaque capsule stays readable; accent is the fill (selected) or
    /// stroke (idle).
    private var labelColor: Color {
        #if os(tvOS) || os(visionOS)
        Color.white
        #else
        accent
        #endif
    }

    private var fillColor: Color {
        #if os(tvOS) || os(visionOS)
        selected ? accent : Color.black.opacity(0.55)
        #else
        selected ? accent.opacity(0.18) : accent.opacity(0.08)
        #endif
    }

    @ViewBuilder
    private var chipStroke: some View {
        #if os(tvOS) || os(visionOS)
        Capsule().strokeBorder(accent, lineWidth: selected ? 0 : 1.5)
        #else
        EmptyView()
        #endif
    }
}
