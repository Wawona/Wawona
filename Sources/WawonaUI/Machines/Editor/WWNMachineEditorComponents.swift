import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#endif

// MARK: - Card

/// A titled content card with an SF Symbol header. Long explanatory copy stays
/// behind a native info popover on every platform.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorCard<Content: View>: View {
  let icon: String
  let title: String
  var tint: Color
  var info: String?

  @ViewBuilder let content: () -> Content
  @State private var showsInfo = false

  init(
    icon: String,
    title: String,
    tint: Color = .accentColor,
    info: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.icon = icon
    self.title = title
    self.tint = tint
    self.info = info
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .frame(width: 26, height: 26)
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(tint.opacity(0.16))
          )
        Text(title)
          .font(.headline)
        Spacer(minLength: 8)
        if let info {
          WWNEditorInfoButton(text: info)
        }
      }
      content()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.secondary.opacity(0.07))
    )
    .backport.overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(editorCardOutlineColor, lineWidth: 1)
    }
  }

  private var editorCardOutlineColor: Color {
    #if os(macOS)
    Color(nsColor: .separatorColor)
    #else
    Color.primary.opacity(0.12)
    #endif
  }
}

// MARK: - Info presentation

/// Native `info.circle` button that opens explanatory copy without expanding
/// the main settings surface.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorInfoButton: View {
  let text: String

  @State private var showsInfo = false

  var body: some View {
    let button = WawonaButton {
      showsInfo.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.system(size: 12))
    }
    .buttonStyle(.plain)
    .foregroundColor(.secondary.opacity(0.65))
    .backport.accessibilityLabel("More information")

    #if os(tvOS)
    button.alert("More Information", isPresented: $showsInfo) {
      WawonaButton("OK", role: .cancel) {}
    } message: {
      Text(text)
    }
    #else
    button
      #if os(macOS)
      .backport.help(text)
      #endif
      .popover(isPresented: $showsInfo, arrowEdge: .trailing) {
        ScrollView(.vertical) {
          Text(text)
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            #if !os(tvOS) && !os(watchOS)
            .backport.selectableText()
            #endif
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        .frame(maxHeight: 300)
      }
    #endif
  }
}

/// Short operational status or concise secondary text.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorCaption: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
  }
}

// MARK: - Rows

/// Labeled field row: optional leading icon + optional info popover (macOS) /
/// inline caption (iOS/tvOS). Adapts to compact widths by stacking.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorFieldRow<Content: View>: View {
  let label: String
  var icon: String? = nil
  var footnote: String? = nil
  @ViewBuilder let content: () -> Content

  init(
    _ label: String,
    icon: String? = nil,
    footnote: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.label = label
    self.icon = icon
    self.footnote = footnote
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      WawonaFittingRow {
        HStack(alignment: .center, spacing: 10) {
          labelColumn
          Spacer(minLength: 12)
          content()
            .frame(width: controlWidth, alignment: .trailing)
            .backport.accessibilityLabel(label)
        }
      } vertical: {
        VStack(alignment: .leading, spacing: 6) {
          labelColumn
          content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .backport.accessibilityLabel(label)
        }
      }
    }
  }

  private var labelColumn: some View {
    HStack(spacing: 5) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .frame(width: 15)
      }
      Text(label)
        .font(.subheadline.weight(.semibold))
      if let footnote {
        WWNEditorInfoButton(text: footnote)
      }
    }
    .frame(width: 178, alignment: .leading)
  }

  private var controlWidth: CGFloat {
    #if os(macOS)
    300
    #elseif os(tvOS)
    320
    #else
    220
    #endif
  }
}

/// Toggle row with optional leading icon and explanatory copy (popover on
/// macOS, inline caption elsewhere).
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorToggleRow: View {
  let title: String
  var icon: String? = nil
  var footnote: String? = nil
  @Binding var isOn: Bool
  var disabled = false

  init(
    _ title: String,
    icon: String? = nil,
    footnote: String? = nil,
    isOn: Binding<Bool>,
    disabled: Bool = false
  ) {
    self.title = title
    self.icon = icon
    self.footnote = footnote
    self._isOn = isOn
    self.disabled = disabled
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        titleBar
        Spacer(minLength: 12)
        // Toggle knob pinned to the trail; hidden label keeps VoiceOver.
        Toggle(isOn: $isOn) { Text(title) }
          .labelsHidden()
          .toggleStyle(.switch)
          .fixedSize()
      }
      #if os(macOS)
      .contentShape(Rectangle())
      .onTapGesture {
        guard !disabled else { return }
        isOn.toggle()
      }
      #endif
    }
    .disabled(disabled)
  }

  /// macOS leading content: icon + title + optional info button.
  private var titleBar: some View {
    HStack(spacing: 8) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .frame(width: 18)
      }
      Text(title)
        .font(.body)
      if let footnote {
        WWNEditorInfoButton(text: footnote)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Bounded numeric storage for legacy string-backed machine fields.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorNumberField: View {
  @Binding var text: String
  let range: ClosedRange<Int>
  var step: Int = 1
  var automaticWhenEmpty = false

  var body: some View {
    HStack(spacing: 6) {
      WawonaTextField(automaticWhenEmpty ? "Auto" : "\(range.lowerBound)", text: sanitizedText)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .backport.onSubmit { normalizeFinalValue() }
        .onDisappear { normalizeFinalValue() }

      #if !os(tvOS)
      Stepper(
        "",
        value: Binding(
          get: {
            let parsed = Int(text) ?? range.lowerBound
            return min(max(parsed, range.lowerBound), range.upperBound)
          },
          set: {
            text = String(min(max($0, range.lowerBound), range.upperBound))
          }
        ),
        in: range,
        step: step
      )
      .labelsHidden()
      #endif
    }
  }

  private var sanitizedText: Binding<String> {
    Binding(
      get: { text },
      set: { newValue in
        let digits = newValue.filter(\.isNumber)
        guard let parsed = Int(digits) else {
          text = ""
          return
        }
        text = String(min(parsed, range.upperBound))
      }
    )
  }

  private func normalizeFinalValue() {
    if automaticWhenEmpty && text.isEmpty {
      return
    }
    let parsed = Int(text) ?? range.lowerBound
    text = String(min(max(parsed, range.lowerBound), range.upperBound))
  }
}

/// Text field for code-like input (hosts, paths, commands): rounded border,
/// no autocapitalization or autocorrection.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorCodeField: View {
  let prompt: String
  @Binding var text: String

  init(_ prompt: String, text: Binding<String>) {
    self.prompt = prompt
    self._text = text
  }

  var body: some View {
    WawonaTextField(prompt, text: $text)
      .textFieldStyle(.roundedBorder)
      .wwnDisableAutocapitalization()
      .disableAutocorrection(true)
  }
}

/// Secure field with a macOS-style reveal toggle.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorSecureField: View {
  let prompt: String
  @Binding var text: String

  @State private var revealed = false

  init(_ prompt: String, text: Binding<String>) {
    self.prompt = prompt
    self._text = text
  }

  var body: some View {
    HStack(spacing: 6) {
      Group {
        if revealed {
          WawonaTextField(prompt, text: $text)
        } else {
          SecureField(prompt, text: $text)
        }
      }
      .textFieldStyle(.roundedBorder)
      #if os(macOS)
      WawonaButton {
        revealed.toggle()
      } label: {
        Image(systemName: revealed ? "eye.slash" : "eye")
          .foregroundColor(.secondary)
      }
      .buttonStyle(.borderless)
      .backport.help(revealed ? "Hide password" : "Show password")
      #endif
    }
  }
}

/// Monospaced command preview block with a copy button.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNEditorCommandBlock: View {
  let command: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "terminal")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .padding(.top, 2)
      Text(command)
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.secondary)
        #if !os(tvOS)
        .backport.selectableText()
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
      #if !os(tvOS)
      WawonaButton {
        wwnCopyToPasteboard(command)
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.borderless)
      .foregroundColor(.secondary)
      .backport.help("Copy command")
      #endif
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}

// MARK: - Helpers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

func wwnCopyToPasteboard(_ string: String) {
  #if os(macOS)
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(string, forType: .string)
  #elseif os(iOS)
  UIPasteboard.general.string = string
  #endif
}

extension View {
  @ViewBuilder
  func wwnPlatformPickerStyle() -> some View {
    #if os(macOS)
    self.backport.menuPicker()
    #elseif os(tvOS) || os(visionOS)
    self.pickerStyle(.navigationLink)
    #else
    self.backport.navigationPicker()
    #endif
  }

  @ViewBuilder
  func wwnDisableAutocapitalization() -> some View {
    #if os(iOS)
    self.autocapitalization(.none)
    #else
    self
    #endif
  }
}
