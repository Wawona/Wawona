#if os(tvOS)
import SwiftUI

/// tvOS Terminal typing. The Focus Engine never hands first responder to the
/// 1x1 UIKit key host, so a real SwiftUI `TextField` opens the system
/// fullscreen keyboard. That keyboard shows the line being edited, so the
/// whole line goes to the PTY on Return, followed by `\r`. The line goes as a
/// bracketed paste: zle redraws a raw multi-byte burst with the first
/// character twice (`eecho hi`), while a paste inserts as one unit.
struct WWNTvTerminalKeyboardField: View {
  let onInjectData: (Data) -> Void
  let onPasteLine: (String) -> Void

  @State private var text = ""

  var body: some View {
    TextField("Keyboard", text: $text)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .font(.headline)
      .frame(width: 320)
      .onSubmit {
        if text.isEmpty {
          onInjectData(Data([0x0d]))
        } else {
          onPasteLine(text)
        }
        text = ""
      }
      .wwnA11y("wwn.guestConsole.keyboard", label: "Keyboard")
  }
}
#endif
