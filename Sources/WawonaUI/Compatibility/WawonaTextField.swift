import SwiftUI

struct WawonaTextField: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    @Environment(\.wawonaSubmit) private var submit
    private let prompt: Text?
    private let axis: Axis?

    init(_ title: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil, axis: Axis? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.axis = axis
    }

    init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil, axis: Axis? = nil) {
        self.init(LocalizedStringKey(String(title)), text: text, prompt: prompt, axis: axis)
    }

    @ViewBuilder var body: some View {
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, macOS 13.0, *), let axis {
            TextField(title, text: $text, axis: axis)
        } else if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            TextField(title, text: $text, prompt: prompt)
        } else {
            TextField(prompt == nil ? title : "", text: $text, onCommit: submit)
                .overlay(Group {
                    if text.isEmpty { prompt?.foregroundColor(.secondary) }
                }.allowsHitTesting(false), alignment: .leading)
                .accessibility(label: Text(title))
        }
    }
}

private struct WawonaSubmitKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var wawonaSubmit: () -> Void {
        get { self[WawonaSubmitKey.self] }
        set { self[WawonaSubmitKey.self] = newValue }
    }
}
extension WawonaBackport where Content: View {
    @ViewBuilder
    func onSubmit(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            content.onSubmit(action)
        } else {
            content.environment(\.wawonaSubmit, action)
        }
    }
}
