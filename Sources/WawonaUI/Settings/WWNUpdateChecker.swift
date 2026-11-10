import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Compare the running CalVer against the latest GitHub Release for Wawona.
/// Permissions → Check for Updates. Download opens the release asset (DMG /
/// APK / AppImage) or the Releases page when the asset is missing.
@MainActor
final class WWNUpdateChecker: ObservableObject {
    static let shared = WWNUpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String, downloadURL: URL?, releaseURL: URL)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    static let releasesAPI =
        URL(string: "https://api.github.com/repos/Wawona/Wawona/releases/latest")!
    static let releasesPage =
        URL(string: "https://github.com/Wawona/Wawona/releases/latest")!

    var checkForUpdatesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.prefsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.prefsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.prefsKey)
        }
    }

    private static let prefsKey = "CheckForUpdatesEnabled"
    private var inFlight: Task<Void, Never>?

    var currentVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let trimmed = short?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let path = Bundle.main.path(forResource: "VERSION", ofType: nil),
           let raw = try? String(contentsOfFile: path, encoding: .utf8) {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "0"
    }

    func checkNow() {
        inFlight?.cancel()
        status = .checking
        let current = currentVersion
        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: Self.releasesAPI)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Wawona-UpdateCheck", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        self.status = .failed("GitHub returned HTTP \(http.statusCode).")
                    }
                    return
                }
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let tag = (payload?["tag_name"] as? String) ?? ""
                let latest = Self.normalizeVersion(tag)
                let htmlURL = (payload?["html_url"] as? String).flatMap(URL.init(string:))
                    ?? Self.releasesPage
                let download = Self.pickDownloadURL(assets: payload?["assets"] as? [[String: Any]])
                await MainActor.run {
                    if Task.isCancelled { return }
                    if Self.isNewer(latest: latest, current: current) {
                        self.status = .updateAvailable(
                            current: current,
                            latest: latest,
                            downloadURL: download,
                            releaseURL: htmlURL
                        )
                    } else {
                        self.status = .upToDate(current: current)
                    }
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled { return }
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Open the release asset when known; otherwise the Releases page.
    func installOrOpenUpdate() {
        guard case let .updateAvailable(_, _, downloadURL, releaseURL) = status else {
            openURL(Self.releasesPage)
            return
        }
        openURL(downloadURL ?? releaseURL)
    }

    func openReleasesPage() {
        openURL(Self.releasesPage)
    }

    private func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s = String(s.dropFirst())
        }
        return s
    }

    /// CalVer `YY.M.D` (and optional build suffix). Numeric segment compare.
    static func isNewer(latest: String, current: String) -> Bool {
        let a = parse(latest)
        let b = parse(current)
        guard !a.isEmpty, !b.isEmpty else {
            return latest != current && !latest.isEmpty
        }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func parse(_ version: String) -> [Int] {
        normalizeVersion(version)
            .split(whereSeparator: { $0 == "." || $0 == "-" })
            .compactMap { Int($0.filter(\.isNumber)) }
    }

    private static func pickDownloadURL(assets: [[String: Any]]?) -> URL? {
        guard let assets, !assets.isEmpty else { return nil }
        #if os(macOS)
        let prefer = ["macOS", ".dmg"]
        #elseif os(iOS)
        let prefer = ["iOS", ".ipa", ".tipa"]
        #else
        let prefer = [".AppImage", "Linux", ".apk"]
        #endif
        for token in prefer {
            if let hit = assets.first(where: {
                (($0["name"] as? String) ?? "").localizedCaseInsensitiveContains(token)
            }),
            let urlString = hit["browser_download_url"] as? String,
            let url = URL(string: urlString) {
                return url
            }
        }
        if let first = assets.first,
           let urlString = first["browser_download_url"] as? String {
            return URL(string: urlString)
        }
        return nil
    }
}
