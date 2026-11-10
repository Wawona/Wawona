import SwiftUI

#if os(tvOS)
/// tvOS Form choice row. System `Picker` + `.navigationLink` often traps focus
/// (Menu cannot pop) and draws overscan-wide menu rows that clip. This pushes a
/// plain List with explicit Back and dismiss-on-select.
struct WWNTvChoicePicker<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [(value: Value, label: String)]
  /// When false, label is only the current value (Settings rows already paint
  /// the title in `titleStack`). Machine editor Form rows keep the title.
  var showsTitleInLabel: Bool = true
  /// Caption under the title. Inside the label so it darkens on the focus platter.
  var subtitle: String = ""

  var body: some View {
    NavigationLink {
      WWNTvChoiceList(title: title, selection: $selection, options: options)
    } label: {
      if showsTitleInLabel {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .lineLimit(1)
              .truncationMode(.tail)
            if !subtitle.isEmpty {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 16)
          Text(selectedLabel)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      } else {
        Text(selectedLabel.isEmpty ? "Choose…" : selectedLabel)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .accessibilityLabel(Text(title))
    .accessibilityValue(Text(selectedLabel))
  }

  private var selectedLabel: String {
    options.first(where: { $0.value == selection })?.label ?? ""
  }
}

private struct WWNTvChoiceList<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [(value: Value, label: String)]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Button {
          selection = option.value
          dismiss()
        } label: {
          HStack(spacing: 16) {
            Text(option.label)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
            if option.value == selection {
              Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .navigationTitle(title)
    .backport.tvOverscanContentMargins()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Back") { dismiss() }
      }
    }
  }
}
#endif
