import SwiftUI
import WawonaModel

struct SettingsDiagnosticsView: View {
    @ObservedObject var preferences: WawonaPreferences

    var body: some View {
        List {
            if preferences.diagnostics.isEmpty {
                Text("No diagnostics yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preferences.diagnostics) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.category.rawValue.uppercased())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.mode == .runtimeProbe ? "RUNTIME" : "CONFIG")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.success ? "PASS" : "FAIL")
                                .font(.caption2)
                                .foregroundStyle(entry.success ? Color.green : Color.red)
                        }
                        Text(entry.target)
                            .font(.caption)
                        Text(entry.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !entry.details.isEmpty {
                            Text(entry.details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
