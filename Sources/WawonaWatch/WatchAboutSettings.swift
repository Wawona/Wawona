#if os(watchOS)
import AuthenticationServices
import SwiftUI
import WatchKit
import WawonaModel
import WawonaUIContracts

/// About page. Same rows and favicon URLs as iOS Settings.
struct WatchAboutSettingsPage: View {
    @ObservedObject var preferences: WawonaPreferences
    @State private var logText = ""

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    WatchAboutIcon()
                        .frame(width: 52, height: 52)
                    Text("Wawona")
                        .font(.headline)
                    Text(watchBundleString("CFBundleShortVersionString"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section {
                ForEach(WawonaAboutLinks.rows, id: \.url) { row in
                    WatchSettingsLinkRow(row: row)
                }
            }
            Section {
                LabeledContent("Version", value: watchBundleString("CFBundleShortVersionString"))
                LabeledContent("Build", value: watchBundleString("CFBundleVersion"))
                LabeledContent("Platform", value: "watchOS")
                Picker("Log Level", selection: $preferences.logLevel) {
                    ForEach(["error", "warn", "info", "debug", "trace"], id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: preferences.logLevel) { _, _ in preferences.save() }
                ShareLink(item: logText) {
                    Text("Copy Logs")
                }
                .accessibilityIdentifier("wwn.settings.copyRecentLogs")
                .disabled(logText.isEmpty)
            }
        }
        .navigationTitle("About")
        .onAppear {
            logText = watchDiagnosticText()
        }
    }

}

struct WatchSettingsLinkRow: View {
    let row: WawonaAboutLink

    var body: some View {
        Button {
            guard let destination = URL(string: row.url) else { return }
            WatchWebPage.open(destination)
        } label: {
            HStack(spacing: 8) {
                WatchFavicon(iconURL: row.iconURL)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title)
                        .foregroundStyle(.primary)
                    Text(row.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wwn.settings.about.link.\(row.title).\(row.subtitle)")
    }
}

/// Shows a web page in the system web view. watchOS has no Safari, so
/// `openURL`, `Link`, and `openSystemURL` fail for http(s) with
/// "URL failed to load". The web authentication session is the public
/// in-app web view. Its callback scheme is never loaded, so the page stays
/// up until the user closes it.
@MainActor
enum WatchWebPage {
    private static var session: ASWebAuthenticationSession?
    private static let unusedCallbackScheme = "wawona-watch-web"

    static func open(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else {
            WKApplication.shared().openSystemURL(url)
            return
        }
        session?.cancel()
        let done: ASWebAuthenticationSession.CompletionHandler = { _, _ in
            Task { @MainActor in session = nil }
        }
        let next: ASWebAuthenticationSession
        if #available(watchOS 10.4, *) {
            next = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(unusedCallbackScheme),
                completionHandler: done
            )
        } else {
            next = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: unusedCallbackScheme,
                completionHandler: done
            )
        }
        next.prefersEphemeralWebBrowserSession = true
        session = next
        if !next.start() { session = nil }
    }
}

private struct WatchFavicon: View {
    let iconURL: String
    @StateObject private var loader: WatchFaviconLoader

    init(iconURL: String) {
        self.iconURL = iconURL
        _loader = StateObject(wrappedValue: WatchFaviconLoader(iconURL: iconURL))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "link")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private final class WatchFaviconLoader: ObservableObject {
    @Published private(set) var image: Image?

    init(iconURL: String) {
        if let file = WawonaAboutLinks.bundleFile(for: iconURL),
           let image = Self.image(from: WawonaFaviconCache.bundleData(named: file)) {
            self.image = image
            return
        }
        guard let url = URL(string: iconURL) else { return }
        if let image = Self.image(from: WawonaFaviconCache.cachedData(for: url)) {
            self.image = image
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, Self.image(from: data) != nil else { return }
            guard WawonaFaviconCache.storeIfChanged(remoteURL: url, data: data) else { return }
            guard let image = Self.image(from: data) else { return }
            DispatchQueue.main.async { self?.image = image }
        }.resume()
    }

    private static func image(from data: Data?) -> Image? {
        guard let data, let platformImage = UIImage(data: data) else { return nil }
        return Image(uiImage: platformImage)
    }
}

private struct WatchAboutIcon: View {
    var body: some View {
        if let image = watchAboutImage() {
            image
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private func watchAboutImage() -> Image? {
    if let data = WawonaFaviconCache.bundleData(named: "WawonaAbout.png"),
       let image = UIImage(data: data) {
        return Image(uiImage: image)
    }
    return nil
}

private func watchBundleString(_ key: String) -> String {
    Bundle.main.infoDictionary?[key] as? String ?? ""
}

@_silgen_name("wwn_log_ring_dump")
private func wwn_log_ring_dump(_ machineId: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("WWNStringFree")
private func wwnWatchStringFree(_ s: UnsafeMutablePointer<CChar>?)

private func watchDiagnosticText() -> String {
    let version = watchBundleString("CFBundleShortVersionString")
    let build = watchBundleString("CFBundleVersion")
    var out = "### Wawona diagnostics\n"
    out += "Wawona: \(version)\n"
    if !build.isEmpty { out += "Build: \(build)\n" }
    out += "Platform: watchOS\n"
    if let ptr = wwn_log_ring_dump(nil) {
        out += String(cString: ptr)
        wwnWatchStringFree(ptr)
    }
    return out
}
#endif
