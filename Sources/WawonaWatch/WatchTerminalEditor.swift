#if os(watchOS)
import SwiftUI

/// System text input for the shell prompt line. The field and the prompt
/// stay the same string: each edit is written to the PTY as it happens.
/// watchOS opens the keyboard when this field takes focus.
struct WatchTerminalEditor: View {
    @Binding var draft: String
    var onSync: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            TextField("Command", text: $draft)
                .focused($focused)
                .defaultFocus($focused, true)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { focused = false }
                .onChange(of: draft) { _, next in
                    onSync(next)
                }
                .accessibilityIdentifier("wwn.watch.terminal.edit")
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
