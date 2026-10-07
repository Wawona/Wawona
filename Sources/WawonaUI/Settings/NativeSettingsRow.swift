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
        if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
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
        } else {
            VStack(alignment: .leading, spacing: 8) {
                labelColumn
                trailingControl.frame(maxWidth: .infinity, alignment: .trailing)
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
                        .foregroundColor(.secondary)
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
            .accessibility(label: Text(title))
            .frame(width: controlWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func helpButton(_ help: String) -> some View {
        let button = WawonaButton {
            showingHelp = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibility(label: Text("Help for \(title)"))

        #if os(tvOS) || os(watchOS)
        button.alert(title, isPresented: $showingHelp) {
            WawonaButton("OK", role: .cancel) {}
        } message: {
            Text(help)
        }
        #else
        button
            #if os(macOS)
            .help("More information")
            #endif
            .popover(isPresented: $showingHelp) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(help)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            #if !os(tvOS) && !os(watchOS)
                            .backport.selectableText()
                            #endif
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 400)
                .frame(maxHeight: 320)
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
        if #available(iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            self.pickerStyle(.navigationLink)
        } else {
            self.pickerStyle(DefaultPickerStyle())
        }
        #endif
    }
}

struct NativeBoundedIntegerField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var prompt: String? = nil

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        return formatter
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: boundedValue, formatter: integerFormatter)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .accessibility(label: Text(title))

            #if !os(tvOS)
            Stepper(
                "",
                value: boundedValue,
                in: range,
                step: step
            )
            .labelsHidden()
            .accessibility(label: Text("\(title) stepper"))
            #endif
        }
    }

    private var boundedValue: Binding<Int> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}
