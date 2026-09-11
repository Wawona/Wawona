import Foundation

/// How a `wasm` machine picks what Relay runs.
///
/// Matches native-shell `wasm <file|package>` and `wpm` on `repo.wawona.io/wasm/v1`.
/// Never APT, `/jailbreak/`, or `/termux/`.
public enum WasmLaunchMode: String, Codable, CaseIterable, Sendable {
    case file
    case repo
    case command
}

public struct WasmLaunchSpec: Hashable, Sendable {
    public var mode: WasmLaunchMode
    public var modulePath: String
    public var package: String
    public var command: String

    public init(
        mode: WasmLaunchMode = .command,
        modulePath: String = "",
        package: String = "",
        command: String = WasmLaunch.defaultCommand
    ) {
        self.mode = mode
        self.modulePath = modulePath
        self.package = package
        self.command = command
    }
}

/// Shared resolve for Machines kind `wasm` and Native `wawona-wasm`.
public enum WasmLaunch {
    public static let defaultCommand = "wasm hello-wasi-gui"
    public static let defaultPackage = "hello-wasi-gui"
    public static let catalogBase = "https://repo.wawona.io/wasm/v1"
    public static let catalogIndexURL = catalogBase + "/index.json"

    /// Tokens that mean the bundled hello-wasi-gui smoke.
    public static let bundledAliases: Set<String> = [
        "hello-wasi-gui",
        "hello-wasi-gui.wasm",
        "wasi-hello-gui",
        "wasi-hello-gui.wasm",
        "hello-wasi",
    ]

    public static func wawonaFolder() -> URL {
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs.appendingPathComponent("Wawona", isDirectory: true)
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("Wawona", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Wawona", isDirectory: true)
    }

    public static func localModulesDirectory() -> URL {
        wawonaFolder().appendingPathComponent("wasm-modules", isDirectory: true)
    }

    public static func inboxDirectory() -> URL {
        wawonaFolder().appendingPathComponent("inbox", isDirectory: true)
    }

    public static func wpmStoreDirectory() -> URL {
        if let env = ProcessInfo.processInfo.environment["WAWONA_WASM_STORE"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("Wawona/wasm-packages", isDirectory: true)
        }
        return wawonaFolder().appendingPathComponent("wasm-packages", isDirectory: true)
    }

    public static func listLocalModules() -> [URL] {
        let fm = FileManager.default
        let dirs = [localModulesDirectory(), inboxDirectory()]
        var out: [URL] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            out.append(contentsOf: items.filter { $0.pathExtension.lowercased() == "wasm" })
        }
        return out.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func listInstalledWpmPackages() -> [(name: String, path: String)] {
        let indexURL = wpmStoreDirectory().appendingPathComponent("installed.json")
        guard
            let data = try? Data(contentsOf: indexURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let packages = obj["packages"] as? [String: [String: Any]]
        else {
            return []
        }
        return packages.keys.sorted().compactMap { name in
            guard let resolved = resolveInstalledWpm(name: name) else { return nil }
            return (name, resolved)
        }
    }

    public static func resolveInstalledWpm(name: String) -> String? {
        let indexURL = wpmStoreDirectory().appendingPathComponent("installed.json")
        guard
            let data = try? Data(contentsOf: indexURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let packages = obj["packages"] as? [String: [String: Any]],
            let pkg = packages[name],
            let digest = pkg["digest"] as? String
        else {
            return nil
        }
        let hex = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
        let path = wpmStoreDirectory()
            .appendingPathComponent("blobs/\(hex)/component.wasm")
            .path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// First token after `wasm` / `wpm …`, or a bare package / path.
    public static func wasmArg(fromCommand raw: String) -> String {
        let tokens = tokenize(raw)
        if tokens.isEmpty { return defaultPackage }
        let first = tokens[0]
        if first == "wasm" {
            return normalizeAlias(tokens.dropFirst().first ?? defaultPackage)
        }
        if first == "wpm" {
            if tokens.count >= 3, ["install", "path", "show", "run"].contains(tokens[1]) {
                return normalizeAlias(tokens[2].split(separator: "@").first.map(String.init) ?? tokens[2])
            }
            if tokens.count >= 2 {
                return normalizeAlias(tokens[1])
            }
            return defaultPackage
        }
        return normalizeAlias(first)
    }

    public static func normalizeAlias(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultPackage }
        if bundledAliases.contains(trimmed) { return defaultPackage }
        return trimmed
    }

    public static func commandRequestsInstall(_ raw: String) -> Bool {
        let tokens = tokenize(raw)
        return tokens.count >= 2 && tokens[0] == "wpm" && tokens[1] == "install"
    }

    public static func localModuleNamed(_ name: String) -> String? {
        let dest = localModulesDirectory().appendingPathComponent("\(normalizeAlias(name)).wasm")
        return FileManager.default.fileExists(atPath: dest.path) ? dest.path : nil
    }

    public static func resolveArg(spec: WasmLaunchSpec) -> String {
        let path = spec.modulePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        let pkg = spec.package.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pkg.isEmpty {
            let name = normalizeAlias(pkg)
            if let installed = resolveInstalledWpm(name: name) { return installed }
            if let local = localModuleNamed(name) { return local }
            return name
        }
        let fromCommand = wasmArg(fromCommand: spec.command)
        if fromCommand.contains("/") || fromCommand.hasSuffix(".wasm") {
            let expanded = (fromCommand as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        if let installed = resolveInstalledWpm(name: fromCommand) { return installed }
        if let local = localModuleNamed(fromCommand) { return local }
        return fromCommand
    }

    /// Resolve, then fetch `/wasm/v1` when `wpm install` or a missing package needs a file.
    /// Bundled aliases stay names so Relay can use hello-wasi-gui.
    public static func ensureArg(spec: WasmLaunchSpec) -> String {
        let resolved = resolveArg(spec: spec)
        if FileManager.default.fileExists(atPath: resolved) { return resolved }
        if bundledAliases.contains(resolved) || resolved == defaultPackage { return resolved }
        if let installed = resolveInstalledWpm(name: resolved) { return installed }
        if let local = localModuleNamed(resolved) { return local }
        if commandRequestsInstall(spec.command) || !spec.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !resolved.contains("/") {
            return downloadPackageSync(name: resolved) ?? resolved
        }
        return resolved
    }

    public static func fetchCatalogIndex() throws -> [WasmCatalogPackage] {
        let urlString = catalogIndexURL
        guard isAllowedCatalogURL(urlString), let url = URL(string: urlString) else {
            throw WasmCatalogError.refusedURL
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(CatalogIndexFile.self, from: data)
        return decoded.packages.map {
            WasmCatalogPackage(
                name: $0.name,
                version: $0.version,
                digest: $0.digest,
                url: $0.url,
                summary: $0.summary ?? ""
            )
        }
    }

    public static func searchCatalog(_ query: String) throws -> [WasmCatalogPackage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try fetchCatalogIndex().filter { pkg in
            q.isEmpty || pkg.name.lowercased().contains(q) || pkg.summary.lowercased().contains(q)
        }
    }

    public static func downloadPackage(name: String) throws -> String {
        let wanted = normalizeAlias(name)
        if let local = localModuleNamed(wanted) { return local }
        let match = try fetchCatalogIndex().first { $0.name == wanted || $0.name.lowercased() == wanted.lowercased() }
        guard let pkg = match else { throw WasmCatalogError.notFound(wanted) }
        return try downloadPackage(pkg)
    }

    public static func downloadPackage(_ package: WasmCatalogPackage) throws -> String {
        let urlString: String
        if package.url.hasPrefix("https://") || package.url.hasPrefix("http://") {
            urlString = package.url
        } else {
            urlString = catalogBase + "/" + package.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard isAllowedCatalogURL(urlString), let url = URL(string: urlString) else {
            throw WasmCatalogError.refusedURL
        }
        let data = try Data(contentsOf: url)
        guard data.count >= 4, data.prefix(4) == Data([0x00, 0x61, 0x73, 0x6d]) else {
            throw WasmCatalogError.notWasm
        }
        let dir = localModulesDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(package.name).wasm")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try data.write(to: dest)
        return dest.path
    }

    public static func downloadPackageSync(name: String) -> String? {
        try? downloadPackage(name: name)
    }

    public static func displaySummary(spec: WasmLaunchSpec) -> String {
        switch spec.mode {
        case .file:
            let path = spec.modulePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty { return "wasm hello-wasi-gui (bundled)" }
            return (path as NSString).lastPathComponent
        case .repo:
            let pkg = spec.package.trimmingCharacters(in: .whitespacesAndNewlines)
            return pkg.isEmpty ? "Search wasm repo" : "wasm \(pkg)"
        case .command:
            let cmd = spec.command.trimmingCharacters(in: .whitespacesAndNewlines)
            return cmd.isEmpty ? defaultCommand : cmd
        }
    }

    public static func isAllowedCatalogURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.contains("/jailbreak/") || lower.contains("/termux/") { return false }
        if lower.contains("/packages") && !lower.contains("/wasm/") { return false }
        if lower.hasSuffix(".deb") { return false }
        return lower.hasPrefix(catalogBase) || lower.contains("/wasm/v1") || lower.contains("/wasm/")
    }

    static func tokenize(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

public struct WasmCatalogPackage: Identifiable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var digest: String
    public var url: String
    public var summary: String

    public var id: String { "\(name)@\(version)" }

    public init(name: String, version: String, digest: String, url: String, summary: String) {
        self.name = name
        self.version = version
        self.digest = digest
        self.url = url
        self.summary = summary
    }
}

public enum WasmCatalogError: Error, LocalizedError, Sendable {
    case refusedURL
    case notWasm
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .refusedURL:
            return "Wasm catalog only. Refusing a non /wasm/v1 URL."
        case .notWasm:
            return "Download is not a Wasm module"
        case .notFound(let name):
            return "Wasm package not in /wasm/v1: \(name)"
        }
    }
}

private struct CatalogIndexFile: Decodable {
    var packages: [Package]
    struct Package: Decodable {
        var name: String
        var version: String
        var digest: String
        var url: String
        var summary: String?
    }
}
