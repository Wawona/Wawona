import SwiftUI
import WawonaModel

/// Windows-style environment variable table (global or per-machine).
public struct EnvironmentVariablesView: View {
    @ObservedObject public var preferences: WawonaPreferences
    public var profileStore: MachineProfileStore?
    public var machineID: String?
    /// When true, edits write to the machine's `runtimeOverrides.environment`.
    public var perMachine: Bool
    /// Optional draft map for editors that save later (e.g. `WWNMachineEditorView`).
    public var draftMachineOverrides: Binding<EnvironmentOverrideMap>?

    @State private var filter: String = ""
    @State private var categoryFilter: EnvironmentCategory? = nil
    @State private var editingName: String = ""
    @State private var editingValue: String = ""
    @State private var showEditor = false
    @State private var isNew = false
    @State private var confirmResetAll = false

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

    private var rows: [ResolvedEnvironmentEntry] {
        preferences.resolvedEnvironment(
            for: perMachine ? profile : nil,
            machineOverrideMap: perMachine ? machineOverrides : [:]
        )
        .filter { !$0.isSecret }
        .filter { row in
            if let categoryFilter, row.category != categoryFilter { return false }
            if filter.isEmpty { return true }
            return row.name.localizedCaseInsensitiveContains(filter)
                || (row.value ?? "").localizedCaseInsensitiveContains(filter)
        }
    }

    public var body: some View {
        List {
            Section {
                TextField("Filter", text: $filter)
                    .wawonaTextFieldNoAutocaps()
                    .accessibilityIdentifier("wwn.settings.environment.filter")
                Picker("Category", selection: $categoryFilter) {
                    Text("All").tag(Optional<EnvironmentCategory>.none)
                    ForEach(EnvironmentCategory.allCases.filter { $0 != .secrets }, id: \.self) { cat in
                        Text(cat.rawValue.capitalized).tag(Optional(cat))
                    }
                }
                .accessibilityIdentifier("wwn.settings.environment.category")
            }

            Section {
                ForEach(rows) { row in
                    environmentRow(row)
                }
            } header: {
                Text(perMachine ? "This machine" : "Wawona environment")
            } footer: {
                Text("\(rows.count) variables. Edit or Reset each row. Applies on next Start / Focus. Machine overrides beat global.")
                    .font(.caption2)
            }

            Section {
                Button("New…") {
                    isNew = true
                    editingName = ""
                    editingValue = ""
                    showEditor = true
                }
                .accessibilityIdentifier("wwn.settings.environment.new")
                Button("Reset Wawona-managed") {
                    resetManaged()
                }
                .accessibilityIdentifier("wwn.settings.environment.resetManaged")
                Button("Reset All Overrides", role: .destructive) {
                    confirmResetAll = true
                }
                .accessibilityIdentifier("wwn.settings.environment.resetAll")
            }
        }
        .navigationTitle("Environment Variables")
        .accessibilityIdentifier("wwn.settings.environment")
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                Form {
                    TextField("Name", text: $editingName)
                        .wawonaTextFieldNoAutocaps()
                        .disabled(!isNew)
                        .accessibilityIdentifier("wwn.settings.environment.edit.name")
                    TextField("Value", text: $editingValue)
                        .wawonaTextFieldNoAutocaps()
                        .accessibilityIdentifier("wwn.settings.environment.edit.value")
                    if !isNew {
                        Button("Unset (remove from environment)", role: .destructive) {
                            setOverride(name: editingName, .unset)
                            showEditor = false
                        }
                    }
                }
                .navigationTitle(isNew ? "New Variable" : "Edit \(editingName)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEdit()
                            showEditor = false
                        }
                        .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 180)
            #endif
        }
        .confirmationDialog("Reset all environment overrides?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(perMachine
                ? "Clears this machine's overrides so it inherits global / Wawona defaults."
                : "Clears global overrides. Catalog defaults and first-class Settings still apply.")
        }
    }

    private func environmentRow(_ row: ResolvedEnvironmentEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.monospaced())
                Text(row.displayValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(row.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button("Edit") {
                isNew = false
                editingName = row.name
                editingValue = row.value ?? ""
                showEditor = true
            }
            .accessibilityIdentifier("wwn.settings.environment.edit.\(row.name)")
            if row.mutability != .secret {
                Button("Reset") {
                    resetOne(row.name)
                }
                .accessibilityIdentifier("wwn.settings.environment.reset.\(row.name)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isNew = false
            editingName = row.name
            editingValue = row.value ?? ""
            showEditor = true
        }
        .accessibilityIdentifier("wwn.settings.environment.row.\(row.name)")
        .opacity(perMachine && !row.isOverridden && row.source != .machineOverride ? 0.85 : 1)
    }

    private func saveEdit() {
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setOverride(name: name, .set(editingValue))
    }

    private func setOverride(name: String, _ override: EnvironmentOverride) {
        if let draft = draftMachineOverrides {
            var next = draft.wrappedValue
            next[name] = override
            draft.wrappedValue = next
            return
        }
        if perMachine {
            guard var profile = profile, let profileStore else { return }
            var env = profile.runtimeOverrides.environment ?? [:]
            env[name] = override
            profile.runtimeOverrides.environment = env
            profileStore.upsert(profile)
            MachineRuntimeSettingsApplicator.apply(profile: profile, preferences: preferences)
        } else {
            preferences.setEnvironmentOverride(name: name, override: override)
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

extension ResolvedEnvironmentEntry {
    fileprivate var sourceLabel: String {
        if let ownedBy, source == .firstClassSetting {
            return "Managed by \(ownedBy)"
        }
        return source.rawValue
    }
}
