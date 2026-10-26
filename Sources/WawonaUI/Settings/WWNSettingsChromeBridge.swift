import SwiftUI

/// Connects the Environment Variables detail action to the host settings toolbar.
@MainActor
final class WWNSettingsChromeBridge: ObservableObject {
    static let inactive = WWNSettingsChromeBridge()

    @Published private(set) var showsAddEnvironmentVariable = false
    private var addEnvironmentVariable: (() -> Void)?

    func registerAddEnvironmentVariable(_ action: @escaping () -> Void) {
        addEnvironmentVariable = action
        showsAddEnvironmentVariable = true
    }

    func unregisterAddEnvironmentVariable() {
        addEnvironmentVariable = nil
        showsAddEnvironmentVariable = false
    }

    func performAddEnvironmentVariable() {
        addEnvironmentVariable?()
    }
}

private struct WWNSettingsChromeBridgeKey: EnvironmentKey {
    static let defaultValue: WWNSettingsChromeBridge? = nil
}

extension EnvironmentValues {
    var wwnSettingsChromeBridge: WWNSettingsChromeBridge? {
        get { self[WWNSettingsChromeBridgeKey.self] }
        set { self[WWNSettingsChromeBridgeKey.self] = newValue }
    }
}

private struct WWNSettingsChromeAddRegistration: ViewModifier {
    @Environment(\.wwnSettingsChromeBridge) private var chromeBridge
    let onAdd: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { chromeBridge?.registerAddEnvironmentVariable(onAdd) }
            .onDisappear { chromeBridge?.unregisterAddEnvironmentVariable() }
    }
}

extension View {
    func wwnSettingsChromeAddRegistration(onAdd: @escaping () -> Void) -> some View {
        modifier(WWNSettingsChromeAddRegistration(onAdd: onAdd))
    }
}
