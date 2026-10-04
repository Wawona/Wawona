import SwiftUI

enum WawonaButtonRole {
    case cancel, destructive

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    var native: ButtonRole { self == .cancel ? .cancel : .destructive }
}

struct WawonaButton<Label: View>: View {
    private let role: WawonaButtonRole?
    private let action: () -> Void
    private let label: Label

    init(role: WawonaButtonRole? = nil, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = role
        self.action = action
        self.label = label()
    }

    init(_ title: LocalizedStringKey, role: WawonaButtonRole? = nil, action: @escaping () -> Void) where Label == Text {
        self.init(role: role, action: action) { Text(title) }
    }

    init<S: StringProtocol>(_ title: S, role: WawonaButtonRole? = nil, action: @escaping () -> Void) where Label == Text {
        self.init(role: role, action: action) { Text(title) }
    }

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) where Label == WawonaLabel<Text, Image> {
        self.init(action: action) { WawonaLabel(title, systemImage: systemImage) }
    }

    init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping () -> Void) where Label == WawonaLabel<Text, Image> {
        self.init(action: action) { WawonaLabel(title, systemImage: systemImage) }
    }

    @ViewBuilder var body: some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            Button(role: role?.native, action: action) { label }
        } else {
            Button(action: action) { label }
                .foregroundColor(role == .destructive ? .red : nil)
        }
    }
}

extension WawonaBackport where Content: View {
    @ViewBuilder
    func borderedButton(prominent: Bool = false) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        } else {
            content.buttonStyle(DefaultButtonStyle())
        }
    }
}
