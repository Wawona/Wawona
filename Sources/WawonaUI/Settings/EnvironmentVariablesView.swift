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
        case .xdg: return .indigo
        case .fonts: return .teal
        case .input: return .green
        case .debug: return .red
        case .secrets: return .yellow
        case .user: return .mint
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

    public var body: some View {
        List {
            Section {
                categoryPicker
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if filteredRows.isEmpty {
                ContentUnavailableView(
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
                            Label(category.rawValue.capitalized, systemImage: category.iconName)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(filteredRows) { row in
                        rowView(for: row)
                    }
                }
            }

            Section {
                Button("Reset Wawona Defaults") {
                    resetManaged()
                }
                .accessibilityIdentifier("wwn.settings.environment.resetManaged")

                Button("Reset All Overrides", role: .destructive) {
                    confirmResetAll = true
                }
                .accessibilityIdentifier("wwn.settings.environment.resetAll")
            } footer: {
                Text(perMachine
                    ? "Machine overrides take precedence over global environment variables."
                    : "Wawona manages core Wayland and graphics environment variables automatically.")
            }
        }
        .searchable(text: $searchText, prompt: "Search variables")
        .navigationTitle("Environment Variables")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("wwn.settings.environment")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNewSheet = true
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
                .accessibilityIdentifier("wwn.settings.environment.new")
            }
        }
        .sheet(isPresented: $isPresentingNewSheet) {
            NewEnvironmentVariableSheet { name, value in
                saveNew(name: name, value: value)
            }
        }
        .confirmationDialog("Reset all environment overrides?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(perMachine
                ? "Clears this machine's overrides so it inherits global defaults."
                : "Clears global overrides. Catalog defaults still apply.")
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                categoryChip(title: "All", category: nil)
                ForEach(EnvironmentCategory.allCases.filter { $0 != .secrets }, id: \.self) { cat in
                    categoryChip(title: cat.rawValue.capitalized, category: cat)
                }
            }
            .padding(.vertical, 8)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func categoryChip(title: String, category: EnvironmentCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 5) {
                if let category {
                    Image(systemName: category.iconName)
                        .font(.caption.weight(.medium))
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
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
                        .foregroundStyle(row.category.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if row.isUnset {
                        Text("(Unset)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if row.isOverridden {
                        Text(row.displayValue.isEmpty ? "(Empty)" : row.displayValue)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text(row.displayValue.isEmpty ? "(Default)" : row.displayValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if row.isOverridden {
                    Text("Custom")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                } else if row.isUnset {
                    Text("Unset")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("wwn.settings.environment.row.\(row.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.isOverridden || row.isUnset {
                Button("Reset") {
                    resetOne(row.name)
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.name, forType: .string)
                #elseif os(iOS) || os(visionOS)
                UIPasteboard.general.string = row.name
                #endif
            } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }

            if !row.displayValue.isEmpty {
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.displayValue, forType: .string)
                    #elseif os(iOS) || os(visionOS)
                    UIPasteboard.general.string = row.displayValue
                    #endif
                } label: {
                    Label("Copy Value", systemImage: "doc.on.clipboard")
                }
            }

            if row.isOverridden || row.isUnset {
                Button(role: .destructive) {
                    resetOne(row.name)
                } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
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

    @Environment(\.dismiss) private var dismiss
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
                            Label(cat.rawValue.capitalized, systemImage: cat.iconName)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(cat.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(cat.accentColor)
                        }
                        if currentEntry?.isOverridden == true {
                            Text("Custom Override")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        } else if currentEntry?.isUnset == true {
                            Text("Unset")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        } else {
                            Text("Default")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        TextField(
                            "Value",
                            text: $currentValue,
                            prompt: Text(doc.typicalDefault.isEmpty ? "Enter value" : doc.typicalDefault)
                        )
                        .font(.system(.body, design: .monospaced))
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applySave() }
                        .accessibilityIdentifier("wwn.settings.environment.edit.value")

                        Button("Save") {
                            applySave()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("wwn.settings.environment.detail.save")
                    }

                    if showSaveSuccess {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Value")
            } footer: {
                if currentEntry?.isOverridden == true {
                    Button("Revert to Default", role: .destructive) {
                        revertToDefault()
                    }
                    .font(.caption)
                }
            }

            if !doc.summary.isEmpty || !doc.details.isEmpty {
                Section("Documentation") {
                    if !doc.summary.isEmpty {
                        Text(doc.summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    if !doc.details.isEmpty {
                        Text(doc.details)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if !doc.typicalDefault.isEmpty {
                Section("Typical Default") {
                    HStack {
                        Text(doc.typicalDefault)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Use Default") {
                            currentValue = doc.typicalDefault
                            applySave()
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.bordered)
                    }
                }
            }

            if !doc.examples.isEmpty {
                Section("Examples") {
                    ForEach(doc.examples, id: \.self) { example in
                        HStack {
                            Text(example)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Use") {
                                currentValue = example
                                applySave()
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Details") {
                LabeledContent("Variable Name", value: variableName)
                if let cat = currentEntry?.category {
                    LabeledContent("Category", value: cat.rawValue.capitalized)
                }
                if let mut = currentEntry?.mutability {
                    LabeledContent("Mutability", value: mut.rawValue.capitalized)
                }
                if let ownedBy = currentEntry?.ownedBy, !ownedBy.isEmpty {
                    LabeledContent("Managed By", value: ownedBy)
                }
                LabeledContent("Scope", value: perMachine ? "Per-Machine Override" : "Global Preference")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(variableName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("wwn.settings.environment.detail")
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
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var value: String = ""
    var onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Variable Identity") {
                    TextField("VARIABLE_NAME", text: $name, prompt: Text("e.g. MOZ_ENABLE_WAYLAND"))
                        .font(.system(.body, design: .monospaced))
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wwn.settings.environment.new.name")
                }
                Section("Initial Value") {
                    TextField("Value", text: $value, prompt: Text("e.g. 1"))
                        .font(.system(.body, design: .monospaced))
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wwn.settings.environment.new.value")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Variable")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onAdd(trimmed, value)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("wwn.settings.environment.new.confirm")
                }
            }
        }
    }
}
