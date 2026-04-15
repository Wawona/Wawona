import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section("Wawona") {
                Label("Wawona", systemImage: "macwindow")
                Text("SwiftUI-first multi-platform compositor control plane.")
                    .foregroundStyle(.secondary)
            }
            Section("Links") {
                Link("Wawona", destination: URL(string: "https://github.com/Wawona/Wawona")!)
            }
            Section("Dependencies") {
                DependenciesView()
            }
        }
    }
}
