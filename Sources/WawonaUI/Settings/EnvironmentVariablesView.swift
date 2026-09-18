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
    @State private var confirmResetAll = false
    @State private var activeDetailEntry: ResolvedEnvironmentEntry? = nil
    @State private var isCreatingNew: Bool = false

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
        if let entry = activeDetailEntry {
            EnvironmentVariableDetailView(
                initialEntry: entry,
                preferences: preferences,
                profileStore: profileStore,
                machineID: machineID,
                perMachine: perMachine,
                draftMachineOverrides: draftMachineOverrides,
                onBack: {
                    DispatchQueue.main.async {
                        activeDetailEntry = nil
                    }
                }
            )
        } else if isCreatingNew {
            EnvironmentVariableDetailView(
                initialEntry: nil,
                preferences: preferences,
                profileStore: profileStore,
                machineID: machineID,
                perMachine: perMachine,
                draftMachineOverrides: draftMachineOverrides,
                onBack: {
                    DispatchQueue.main.async {
                        isCreatingNew = false
                    }
                }
            )
        } else {
            listView
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            List {
                Section {
                    ForEach(rows) { row in
                        Button {
                            DispatchQueue.main.async {
                                activeDetailEntry = row
                            }
                        } label: {
                            environmentRow(row)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wwn.settings.environment.row.\(row.name)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if row.isOverridden || row.isUnset {
                                Button("Reset") {
                                    resetOne(row.name)
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    Text(perMachine ? "This machine" : "Wawona environment")
                } footer: {
                    Text("\(rows.count) variables. Select any variable to view documentation, typical defaults, and examples. Machine overrides beat global.")
                        .font(.caption2)
                }

                Section {
                    Button {
                        DispatchQueue.main.async {
                            isCreatingNew = true
                        }
                    } label: {
                        Label("New Variable…", systemImage: "plus")
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
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
        .navigationTitle("Env Vars")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("wwn.settings.environment")
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
        .confirmationDialog("Reset all environment overrides?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(perMachine
                ? "Clears this machine's overrides so it inherits global / Wawona defaults."
                : "Clears global overrides. Catalog defaults and first-class Settings still apply.")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Filter variables…", text: $filter)
                    .wawonaTextFieldNoAutocaps()
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("wwn.settings.environment.filter")
                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .systemFill))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Picker("Category", selection: $categoryFilter) {
                Text("All Categories").tag(Optional<EnvironmentCategory>.none)
                ForEach(EnvironmentCategory.allCases.filter { $0 != .secrets }, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(Optional(cat))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("wwn.settings.environment.category")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }

    private func environmentRow(_ row: ResolvedEnvironmentEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.body.weight(.medium).monospaced())
                        .foregroundStyle(.primary)
                    if row.isOverridden {
                        Text("Overridden")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    } else if row.isUnset {
                        Text("Unset")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
                Text(row.displayValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)

            #if os(macOS)
            Text("Edit")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("wwn.settings.environment.edit.\(row.name)")
            #endif

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .opacity(perMachine && !row.isOverridden && row.source != .machineOverride ? 0.85 : 1)
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

/// Dedicated detail pageview displaying comprehensive documentation, typical default,
/// override examples, and live editing controls for an environment variable.
public struct EnvironmentVariableDetailView: View {
    public let initialEntry: ResolvedEnvironmentEntry?
    @ObservedObject public var preferences: WawonaPreferences
    public var profileStore: MachineProfileStore?
    public var machineID: String?
    public var perMachine: Bool
    public var draftMachineOverrides: Binding<EnvironmentOverrideMap>?
    public var onBack: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode

    @State private var variableName: String
    @State private var currentValue: String
    @State private var isCustomNew: Bool
    @State private var statusFeedback: String?

    public init(
        initialEntry: ResolvedEnvironmentEntry?,
        preferences: WawonaPreferences,
        profileStore: MachineProfileStore? = nil,
        machineID: String? = nil,
        perMachine: Bool = false,
        draftMachineOverrides: Binding<EnvironmentOverrideMap>? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.initialEntry = initialEntry
        self.preferences = preferences
        self.profileStore = profileStore
        self.machineID = machineID
        self.perMachine = perMachine
        self.draftMachineOverrides = draftMachineOverrides
        self.onBack = onBack

        if let initialEntry {
            self._variableName = State(initialValue: initialEntry.name)
            self._currentValue = State(initialValue: initialEntry.value ?? "")
            self._isCustomNew = State(initialValue: false)
        } else {
            self._variableName = State(initialValue: "")
            self._currentValue = State(initialValue: "")
            self._isCustomNew = State(initialValue: true)
        }
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

    private var activeEntry: ResolvedEnvironmentEntry? {
        let all = preferences.resolvedEnvironment(
            for: perMachine ? profile : nil,
            machineOverrideMap: perMachine ? machineOverrides : [:]
        )
        if let match = all.first(where: { $0.name == variableName }) {
            return match
        }
        return initialEntry
    }

    private var doc: EnvironmentVariableDoc {
        if let activeEntry {
            return activeEntry.documentation
        }
        return EnvironmentCatalog.documentation(for: variableName)
    }

    public var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            navigationHeader
            Divider()
            #endif

            Form {
                overviewSection
                valueEditorSection
                descriptionSection
                typicalDefaultSection
                overrideExamplesSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
        #if !os(macOS)
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    navigateBack()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text(isCustomNew ? "New Variable" : variableName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("wwn.settings.environment.back")
            }
        }
        #endif
    }

    #if os(macOS)
    private var navigationHeader: some View {
        HStack(spacing: 8) {
            Button {
                navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("wwn.settings.environment.back")

            Text(isCustomNew ? "New Variable" : variableName)
                .font(.headline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    #endif

    private var overviewSection: some View {
        Section {
            if isCustomNew {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Variable Name")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("VARIABLE_NAME", text: $variableName)
                        .font(.headline.monospaced())
                        .wawonaTextFieldNoAutocaps()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wwn.settings.environment.edit.name")
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 8) {
                    if let cat = activeEntry?.category {
                        badge(label: cat.rawValue.capitalized, color: .blue)
                    }
                    if let mut = activeEntry?.mutability {
                        badge(label: mut.rawValue.capitalized, color: .secondary)
                    }
                    if activeEntry?.isOverridden == true {
                        badge(label: "Overridden", color: .orange)
                    } else if activeEntry?.isUnset == true {
                        badge(label: "Unset", color: .red)
                    } else {
                        badge(label: "Default", color: .green)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("wwn.settings.environment.detail.title")
            }
        }
    }

    private var valueEditorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Configured Value")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if activeEntry?.isUnset == true {
                        Text("(Currently Unset)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if activeEntry?.isOverridden == true {
                        Text("(Active Override)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text("(Inherited Default)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Value", text: $currentValue)
                        .font(.body.monospaced())
                        .wawonaTextFieldNoAutocaps()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applySave() }
                        .accessibilityIdentifier("wwn.settings.environment.edit.value")

                    Button(isCustomNew ? "Add" : "Save") {
                        applySave()
                    }
                    .backport.glassProminentToolbarButton()
                    .disabled(variableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("wwn.settings.environment.detail.save")
                }

                if let statusFeedback {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(statusFeedback)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity)
                }

                if !isCustomNew {
                    HStack(spacing: 12) {
                        if activeEntry?.isOverridden == true || activeEntry?.isUnset == true {
                            Button("Reset to Default") {
                                applyReset()
                            }
                            .backport.glassToolbarButton()
                            .accessibilityIdentifier("wwn.settings.environment.reset.\(variableName)")
                        }

                        Button(role: .destructive) {
                            applyUnset()
                        } label: {
                            Text("Unset Variable")
                        }
                        .backport.glassToolbarButton()
                        .accessibilityIdentifier("wwn.settings.environment.detail.unset")

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Value & Override")
        }
    }

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(doc.details)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wwn.settings.environment.detail.description")

                if let ownedBy = activeEntry?.ownedBy {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.blue)
                        Text("Managed by first-class setting: \(ownedBy). Setting an override here takes precedence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Description")
        }
    }

    private var typicalDefaultSection: some View {
        Section {
            HStack(alignment: .center) {
                Text(doc.typicalDefault)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer()
                if !doc.typicalDefault.isEmpty && doc.typicalDefault != "(unset)" && doc.typicalDefault != "(none, user defined)" {
                    Button {
                        currentValue = doc.typicalDefault
                        withAnimation {
                            statusFeedback = "Copied typical default into value field."
                        }
                    } label: {
                        Text("Use Default")
                            .font(.caption.weight(.medium))
                    }
                    .backport.glassToolbarButton()
                    .accessibilityIdentifier("wwn.settings.environment.detail.useDefault")
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Typical Default Value")
        }
    }

    @ViewBuilder
    private var overrideExamplesSection: some View {
        if !doc.examples.isEmpty {
            Section {
                ForEach(doc.examples, id: \.self) { example in
                    HStack(alignment: .center) {
                        Text(example)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            currentValue = example
                            withAnimation {
                                statusFeedback = "Copied example into value field."
                            }
                        } label: {
                            Text("Use Example")
                                .font(.caption.weight(.medium))
                        }
                        .backport.glassToolbarButton()
                        .accessibilityIdentifier("wwn.settings.environment.detail.useExample.\(example)")
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Override Examples")
            } footer: {
                Text("Click \"Use Example\" to copy into the value editor above.")
                    .font(.caption2)
            }
        }
    }

    private func navigateBack() {
        if let onBack {
            onBack()
        } else {
            dismiss()
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func badge(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func applySave() {
        let name = variableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setOverride(name: name, .set(currentValue))
        withAnimation {
            statusFeedback = "Saved override for \(name)."
        }
    }

    private func applyReset() {
        let name = variableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        resetOne(name)
        if let entry = activeEntry {
            currentValue = entry.value ?? ""
        }
        withAnimation {
            statusFeedback = "Reset \(name) to default."
        }
    }

    private func applyUnset() {
        let name = variableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setOverride(name: name, .unset)
        currentValue = ""
        withAnimation {
            statusFeedback = "\(name) marked unset."
        }
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
}

extension ResolvedEnvironmentEntry {
    fileprivate var sourceLabel: String {
        if let ownedBy, source == .firstClassSetting {
            return "Managed by \(ownedBy)"
        }
        return source.rawValue
    }
}

