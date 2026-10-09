#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaModel

/// Watch Global Settings live in the wrist app (`wawona-global-settings-exclusive`).
/// Same `wawona.pref.*` keys as other targets. Container is `UserDefaults.standard`.
enum WatchKitGlobalSettings {
    static let fallbackPresentationNeeded = Notification.Name("WWNWatchSettingsFallbackNeeded")

    static func registerHost() {}

    @discardableResult
    static func open() -> Bool {
        NotificationCenter.default.post(name: fallbackPresentationNeeded, object: nil)
        return true
    }
}

/// Compact in-app Global Settings for watchOS. Sole host on this target.
struct WatchGlobalSettingsView: View {
    @ObservedObject private var preferences = WawonaPreferences.shared
    @Environment(\.dismiss) private var dismiss

    private let touchOptions = ["Multi-Touch", "Touchpad"]
    private let logLevels = ["debug", "info", "warn", "error"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Enable HDR", isOn: Binding(
                        get: { preferences.colorOperations },
                        set: {
                            preferences.colorOperations = $0
                            preferences.save()
                        }
                    ))
                    .accessibilityIdentifier("wwn.settings.display.hdr")
                }

                Section("Machines") {
                    Toggle("Shake to Exit Machine", isOn: Binding(
                        get: { preferences.shakeToCloseEnabled },
                        set: {
                            preferences.shakeToCloseEnabled = $0
                            preferences.save()
                        }
                    ))
                    Toggle("Swipe Back to Exit Machine", isOn: Binding(
                        get: { preferences.swipeBackToCloseEnabled },
                        set: {
                            preferences.swipeBackToCloseEnabled = $0
                            preferences.save()
                        }
                    ))
                    Toggle("Session Thumbnails", isOn: Binding(
                        get: { preferences.machineSessionThumbnailsEnabled },
                        set: {
                            preferences.machineSessionThumbnailsEnabled = $0
                            preferences.save()
                        }
                    ))
                }

                Section("Input") {
                    Picker("Touch Input Type", selection: Binding(
                        get: {
                            WawonaPreferences.normalizedTouchInputType(
                                preferences.defaultInputProfile
                            )
                        },
                        set: {
                            preferences.defaultInputProfile =
                                WawonaPreferences.normalizedTouchInputType($0)
                            preferences.save()
                        }
                    )) {
                        ForEach(touchOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("About") {
                    Picker("Log Level", selection: Binding(
                        get: { preferences.logLevel },
                        set: {
                            preferences.logLevel = $0
                            preferences.save()
                        }
                    )) {
                        ForEach(logLevels, id: \.self) { level in
                            Text(level.capitalized).tag(level)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Wawona Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .accessibilityIdentifier("wwn.settings.watch.catalog")
        }
    }
}
#endif
