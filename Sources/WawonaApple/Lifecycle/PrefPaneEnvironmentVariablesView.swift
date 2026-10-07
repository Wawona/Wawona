#if WWN_PREFPANE && os(macOS)
import SwiftUI
import WawonaModel

/// Full Env Vars editor inside System Settings → Wawona.
/// Uses the same `WawonaPreferences` / `EnvironmentResolver` catalog as the app.
struct PrefPaneEnvironmentVariablesView: View {
    @ObservedObject private var preferences = WawonaPreferences.shared
    @State private var searchText = ""
    @State private var selectedCategory: EnvironmentCategory?
    @State private var editingName: String?
    @State private var draftValue = ""
    @State private var isPresentingNew = false
    @State private var newName = ""
    @State private var newValue = ""
    @State private var confirmResetAll = false

    private var rows: [ResolvedEnvironmentEntry] {
        preferences.resolvedEnvironment(for: nil, machineOverrideMap: [:])
            .filter { !$0.isSecret }
    }

    private var filtered: [ResolvedEnvironmentEntry] {
        rows.filter { row in
            if let selectedCategory, row.category != selectedCategory { return false }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            return row.name.localizedCaseInsensitiveContains(q)
                || (row.value ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var categories: [EnvironmentCategory] {
        let present = Set(rows.map(\.category))
        return EnvironmentCategory.allCases.filter { present.contains($0) && $0 != .secrets }
    }

    var body: some View {
        Form {
            Section {
                TextField("Search", text: $searchText)
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(Optional<EnvironmentCategory>.none)
                    ForEach(categories, id: \.self) { cat in
                        Text(cat.rawValue.capitalized).tag(Optional(cat))
                    }
                }
            }

            Section {
                ForEach(filtered) { row in
                    Button {
                        editingName = row.name
                        draftValue = row.value ?? ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.body.monospaced())
                                .foregroundStyle(.primary)
                            Text(row.value?.isEmpty == false ? row.value! : "(unset)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Variables")
            } footer: {
                Text("Edits write to the Wawona preferences suite (same as the app).")
            }

            Section {
                Button("Add Variable…") {
                    newName = ""
                    newValue = ""
                    isPresentingNew = true
                }
                Button("Reset Wawona Defaults") {
                    var map = preferences.environmentOverrides
                    EnvironmentResolver.resetWawonaManaged(&map)
                    preferences.environmentOverrides = map
                    preferences.save()
                }
                Button("Reset All Overrides", role: .destructive) {
                    confirmResetAll = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: Binding(
            get: { editingName.map { EditIdentity(name: $0) } },
            set: { editingName = $0?.name }
        )) { item in
            NavigationStack {
                Form {
                    Section("Value") {
                        TextField("Value", text: $draftValue)
                            .textFieldStyle(.roundedBorder)
                    }
                    Section {
                        Button("Save") {
                            preferences.setEnvironmentOverride(
                                name: item.name,
                                override: .set(draftValue)
                            )
                            editingName = nil
                        }
                        Button("Revert to Default", role: .destructive) {
                            preferences.setEnvironmentOverride(name: item.name, override: nil)
                            editingName = nil
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(item.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { editingName = nil }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
        .sheet(isPresented: $isPresentingNew) {
            NavigationStack {
                Form {
                    TextField("VARIABLE_NAME", text: $newName)
                    TextField("Value", text: $newValue)
                }
                .formStyle(.grouped)
                .navigationTitle("New Variable")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresentingNew = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            preferences.setEnvironmentOverride(
                                name: name,
                                override: .set(newValue)
                            )
                            isPresentingNew = false
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 240)
        }
        .alert("Reset all environment overrides?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) {
                var map = preferences.environmentOverrides
                EnvironmentResolver.resetAll(&map)
                preferences.environmentOverrides = map
                preferences.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears global overrides. Catalog defaults still apply.")
        }
    }
}

private struct EditIdentity: Identifiable {
    let name: String
    var id: String { name }
}
#endif
