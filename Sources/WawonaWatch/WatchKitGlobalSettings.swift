#if os(watchOS)
import SwiftUI
import WatchKit
import WawonaModel
import WawonaUIContracts

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
/// Section accents tint detail controls (`WawonaSettingsHubChrome.accentColor`).
struct WatchGlobalSettingsView: View {
    @ObservedObject private var preferences = WawonaPreferences.shared
    @Environment(\.dismiss) private var dismiss

    private let touchOptions = ["Multi-Touch", "Touchpad"]
    private let logLevels = ["debug", "info", "warn", "error"]

    private var displayAccent: Color {
        WawonaSettingsHubChrome.accentColor(for: .display)
    }
    private var machinesAccent: Color {
        WawonaSettingsHubChrome.accentColor(for: .machines)
    }
    private var inputAccent: Color {
        WawonaSettingsHubChrome.accentColor(for: .input)
    }
    private var aboutAccent: Color {
        WawonaSettingsHubChrome.accentColor(for: .about)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Color Operations / HDR", isOn: Binding(
                        get: { preferences.colorOperations },
                        set: {
                            preferences.colorOperations = $0
                            preferences.save()
                        }
                    ))
                    .accentColor(displayAccent)
                    .accessibilityIdentifier("wwn.settings.display.hdr")
                } header: {
                    Text("Display")
                        .foregroundColor(displayAccent)
                }

                Section {
                    Toggle("Shake to Exit Machine", isOn: Binding(
                        get: { preferences.shakeToCloseEnabled },
                        set: {
                            preferences.shakeToCloseEnabled = $0
                            preferences.save()
                        }
                    ))
                    .accentColor(machinesAccent)
                    Toggle("Swipe Back to Exit Machine", isOn: Binding(
                        get: { preferences.swipeBackToCloseEnabled },
                        set: {
                            preferences.swipeBackToCloseEnabled = $0
                            preferences.save()
                        }
                    ))
                    .accentColor(machinesAccent)
                    Toggle("Session Thumbnails", isOn: Binding(
                        get: { preferences.machineSessionThumbnailsEnabled },
                        set: {
                            preferences.machineSessionThumbnailsEnabled = $0
                            preferences.save()
                        }
                    ))
                    .accentColor(machinesAccent)
                } header: {
                    Text("Machines")
                        .foregroundColor(machinesAccent)
                }

                Section {
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
                    .accentColor(inputAccent)
                } header: {
                    Text("Input")
                        .foregroundColor(inputAccent)
                }

                Section {
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
                    .accentColor(aboutAccent)
                } header: {
                    Text("About")
                        .foregroundColor(aboutAccent)
                }
            }
            .navigationTitle("Wawona Settings")
            // watchOS HIG: text Done on the trailing confirmation slot (not
            // an SF Symbol xmark; crown/focus chrome expects a word).
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("wwn.settings.close")
                }
            }
            .accessibilityIdentifier("wwn.settings.watch.catalog")
        }
    }
}
#endif
