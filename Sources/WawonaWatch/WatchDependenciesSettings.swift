#if os(watchOS)
import SwiftUI
import WawonaUIContracts

struct WatchDependencyPackage: Hashable, Identifiable {
    var name: String
    var version: String
    var role: String
    var license: String
    var url: String
    var id: String { name }
}

/// Bundled `SettingsDependencies.json` (same inventory as iOS).
struct WatchDependenciesPage: View {
    private let packages = WatchDependencyPackage.load()
    @State private var selected: WatchDependencyPackage?

    var body: some View {
        List {
            if packages.isEmpty {
                Text("Dependency inventory is unavailable. Rebuild so SettingsDependencies.json is embedded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(packages) { package in
                    // NavigationLink on this list pushes Dependencies again.
                    Button {
                        selected = package
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.name)
                                .lineLimit(1)
                            Text("\(package.version) · \(package.role)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityIdentifier("wwn.settings.dependencies.row.\(package.name)")
                }
            }
        }
        .navigationTitle("Dependencies")
        .navigationDestination(item: $selected) { package in
            WatchDependencyDetail(package: package)
        }
    }
}

private struct WatchDependencyDetail: View {
    let package: WatchDependencyPackage

    var body: some View {
        List {
            LabeledContent("Version", value: package.version)
            Text(package.role)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("License", value: package.license.isEmpty ? "Unknown" : package.license)
            if let url = URL(string: package.url), !package.url.isEmpty {
                WatchSettingsLinkRow(
                    row: WawonaAboutLink(
                        title: "Homepage",
                        subtitle: url.host ?? "",
                        url: url.absoluteString,
                        iconURL: watchFaviconURL(for: url)
                    )
                )
            }
        }
        .navigationTitle(package.name)
    }
}

private func watchFaviconURL(for page: URL) -> String {
    guard let host = page.host else { return "" }
    var parts = URLComponents()
    parts.scheme = page.scheme ?? "https"
    parts.host = host
    parts.path = "/favicon.ico"
    return parts.string ?? ""
}

extension WatchDependencyPackage {
    static func load() -> [WatchDependencyPackage] {
        guard let url = Bundle.main.url(forResource: "SettingsDependencies", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["packages"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"] as? String, !name.isEmpty else { return nil }
            return WatchDependencyPackage(
                name: name,
                version: row["version"] as? String ?? "",
                role: row["role"] as? String ?? "",
                license: row["license"] as? String ?? "",
                url: row["url"] as? String ?? ""
            )
        }
    }
}
#endif
