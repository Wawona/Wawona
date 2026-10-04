import SwiftUI

/// Preserve native label styling when available and its content on iOS 13.
struct WawonaLabel<Title: View, Icon: View>: View {
    private let title: Title
    private let icon: Icon

    init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    init(_ title: LocalizedStringKey, systemImage: String) where Title == Text, Icon == Image {
        self.title = Text(title)
        self.icon = Image(systemName: systemImage)
    }

    init<S: StringProtocol>(_ title: S, systemImage: String) where Title == Text, Icon == Image {
        self.title = Text(title)
        self.icon = Image(systemName: systemImage)
    }

    @ViewBuilder var body: some View {
        if #available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *) {
            Label { title } icon: { icon }
        } else {
            HStack { icon; title }.accessibilityElement(children: .combine)
        }
    }
}

struct WawonaLabeledContent<Title: View, Content: View>: View {
    private let title: Title
    private let content: Content

    init(_ title: LocalizedStringKey, value: String) where Title == Text, Content == Text {
        self.title = Text(title)
        self.content = Text(verbatim: value)
    }

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) where Title == Text {
        self.title = Text(title)
        self.content = content()
    }

    @ViewBuilder var body: some View {
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, macOS 13.0, *) {
            LabeledContent { content } label: { title }
        } else {
            HStack { title; Spacer(); content }.accessibilityElement(children: .combine)
        }
    }
}
