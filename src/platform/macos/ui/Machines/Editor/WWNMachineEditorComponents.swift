import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#endif

// MARK: - Card

/// A titled content card with an SF Symbol header. Long explanatory copy stays
/// behind a native info popover on every platform.
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
          .foregroundStyle(tint)
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
    .overlay {
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
struct WWNEditorInfoButton: View {
  let text: String

  @State private var showsInfo = false

  var body: some View {
    Button {
      showsInfo.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.system(size: 12))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.tertiary)
    #if os(macOS)
    .help(text)
    #endif
    .accessibilityLabel("More information")
    .popover(isPresented: $showsInfo, arrowEdge: .trailing) {
      Text(text)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Compatibility placeholder. Detailed help now lives in info popovers.
struct WWNEditorCaption: View {
  let text: String

  var body: some View {
    EmptyView()
  }
}

// MARK: - Rows

/// Labeled field row: optional leading icon + optional info popover (macOS) /
/// inline caption (iOS/tvOS). Adapts to compact widths by stacking.
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
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 10) {
          labelColumn
          Spacer(minLength: 12)
          content()
            .frame(width: controlWidth, alignment: .trailing)
        }
        VStack(alignment: .leading, spacing: 6) {
          labelColumn
          content()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if let footnote {
        EmptyView()
      }
    }
  }

  private var labelColumn: some View {
    HStack(spacing: 5) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
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
struct WWNEditorNumberStepper: View {
  @Binding var text: String
  let range: ClosedRange<Int>
  let step: Int
  var automaticWhenEmpty = false

  var body: some View {
    Stepper(value: value, in: range, step: step) {
      Text(automaticWhenEmpty && text.isEmpty ? "Auto" : value.wrappedValue.formatted())
        .monospacedDigit()
    }
  }

  private var value: Binding<Int> {
    Binding(
      get: {
        guard let parsed = Int(text) else { return range.lowerBound }
        return min(max(parsed, range.lowerBound), range.upperBound)
      },
      set: { newValue in
        text = String(min(max(newValue, range.lowerBound), range.upperBound))
      }
    )
  }
}

/// Text field for code-like input (hosts, paths, commands): rounded border,
/// no autocapitalization or autocorrection.
struct WWNEditorCodeField: View {
  let prompt: String
  @Binding var text: String

  init(_ prompt: String, text: Binding<String>) {
    self.prompt = prompt
    self._text = text
  }

  var body: some View {
    TextField(prompt, text: $text)
      .textFieldStyle(.roundedBorder)
      .wwnDisableAutocapitalization()
      .autocorrectionDisabled()
  }
}

/// Secure field with a macOS-style reveal toggle.
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
          TextField(prompt, text: $text)
        } else {
          SecureField(prompt, text: $text)
        }
      }
      .textFieldStyle(.roundedBorder)
      #if os(macOS)
      Button {
        revealed.toggle()
      } label: {
        Image(systemName: revealed ? "eye.slash" : "eye")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help(revealed ? "Hide password" : "Show password")
      #endif
    }
  }
}

/// Monospaced command preview block with a copy button.
struct WWNEditorCommandBlock: View {
  let command: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "terminal")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
      Text(command)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        #if !os(tvOS)
        .textSelection(.enabled)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
      #if !os(tvOS)
      Button {
        wwnCopyToPasteboard(command)
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help("Copy command")
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
    self.pickerStyle(.menu)
    #else
    self.pickerStyle(.navigationLink)
    #endif
  }

  @ViewBuilder
  func wwnDisableAutocapitalization() -> some View {
    #if os(iOS)
    self.textInputAutocapitalization(.never)
    #else
    self
    #endif
  }
}
