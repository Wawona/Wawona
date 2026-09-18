import SwiftUI

/// Consistent two-column settings row for Apple platforms with room for a
/// concise label, one optional summary line, and a native trailing control.
struct NativeSettingsRow<Control: View>: View {
    let title: String
    let summary: String?
    let help: String?
    @ViewBuilder let control: () -> Control

    @State private var showingHelp = false

    init(
        _ title: String,
        summary: String? = nil,
        help: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.summary = summary
        self.help = help
        self.control = control
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                labelColumn
                Spacer(minLength: 12)
                trailingControl
            }
            VStack(alignment: .leading, spacing: 8) {
                labelColumn
                trailingControl
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var labelColumn: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let help, !help.isEmpty {
                helpButton(help)
            }
        }
    }

    private var trailingControl: some View {
        control()
            .accessibilityLabel(title)
            .frame(width: controlWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func helpButton(_ help: String) -> some View {
        let button = Button {
            showingHelp = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Help for \(title)")

        #if os(tvOS) || os(watchOS)
        button.alert(title, isPresented: $showingHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(help)
        }
        #else
        button
            #if os(macOS)
            .help("More information")
            #endif
            .popover(isPresented: $showingHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(help)
                }
                .padding()
                .frame(idealWidth: 320)
            }
        #endif
    }

    private var controlWidth: CGFloat {
        #if os(macOS)
        240
        #elseif os(tvOS)
        300
        #else
        180
        #endif
    }
}

extension View {
    @ViewBuilder
    func nativeSettingsPickerStyle() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.navigationLink)
        #endif
    }
}

struct NativeBoundedIntegerField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        TextField("", value: boundedValue, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(title)
    }

    private var boundedValue: Binding<Int> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}
