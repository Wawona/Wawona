#if !SWIFT_PACKAGE && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS))
import SwiftUI

/// System Settings-style text / password editor: push a page, type, Save, back.
/// Matches General → About → Name on iOS (HIG hierarchical settings).
struct WWNSettingsTextEditorView: View {
    enum Kind {
        case text
        case password
    }

    let title: String
    let helpText: String
    let prompt: String
    let kind: Kind
    let initialValue: String
    let onSave: (String) -> Void

    @State private var text: String = ""
    @State private var revealed = false
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        Form {
            Section(footer: Text(helpText)) {
                Group {
                    if kind == .password && !revealed {
                        SecureField(prompt.isEmpty ? title : prompt, text: $text)
                    } else {
                        WawonaTextField(
                            "",
                            text: $text,
                            prompt: prompt.isEmpty ? nil : Text(prompt)
                        )
                    }
                }
                .backport.doneSubmitLabel()
                .autocapitalizationCompatOff()
                .disableAutocorrectionCompat()
                #if os(iOS) || os(visionOS)
                .textContentType(kind == .password ? .password : .none)
                #endif

                if kind == .password {
                    Toggle("Show Password", isOn: $revealed)
                }
            }
        }
        #if os(macOS)
        .backport.groupedForm()
        #endif
        .backport.navigationTitle(title, inline: true)
        .backport.navigationActions {
            WawonaButton("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
        } trailing: {
            WawonaButton("Save") {
                onSave(text)
                presentationMode.wrappedValue.dismiss()
            }
            .backport.borderedButton(prominent: true)
        }
        .onAppear {
            if text.isEmpty {
                text = initialValue
            }
        }
        #if os(iOS) || os(visionOS)
        .onDisappear { WWNHostKeyboard.dismiss() }
        #endif
    }
}

private extension View {
    @ViewBuilder
    func autocapitalizationCompatOff() -> some View {
        #if os(iOS) || os(visionOS)
        if #available(iOS 15.0, *) {
            self.textInputAutocapitalization(.never)
        } else {
            self.autocapitalization(.none)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func disableAutocorrectionCompat() -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        self.disableAutocorrection(true)
        #else
        self
        #endif
    }
}
#endif
