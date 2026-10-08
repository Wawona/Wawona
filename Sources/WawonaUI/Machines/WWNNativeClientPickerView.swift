import SwiftUI
import WawonaModel

/// Bundled Wayland software picker for the native machine editor.
/// Order: Compositors, then client types (Terminals, Graphics, Demos), then Other.
/// Custom commands belong under Native Shell → Terminal, not here.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNNativeClientPickerView: View {
  @Environment(\.presentationMode) private var presentationMode
  @Binding var selectedClientId: String
  var onPicked: (() -> Void)? = nil
  @State private var draftId: String = ""

  private func dismiss() {
    presentationMode.wrappedValue.dismiss()
  }

  private var shownId: String {
    draftId.isEmpty ? selectedClientId : draftId
  }

  private var groupedClients: [(kind: BundledWaylandSoftwareKind, clients: [BundledClient])] {
    kBundledClients.waylandPickerGrouped()
  }

  var body: some View {
    List {
      ForEach(groupedClients, id: \.kind) { group in
        Section(header: Text(group.kind.sectionTitle)) {
          ForEach(group.clients) { client in
            clientOption(client)
          }
        }
      }
    }
    #if os(macOS)
    .listStyle(.inset)
    #else
    .listStyle(.insetGrouped)
    #endif
    .navigationTitle("Wayland Software")
    .onAppear {
      if draftId.isEmpty {
        draftId = selectedClientId == kNativeClientCustomId
          ? "weston-simple-shm"
          : selectedClientId
      }
    }
    #if os(tvOS)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          selectedClientId = shownId
          dismiss()
        }
      }
    }
    .background {
      Color(white: 0.07).ignoresSafeArea()
    }
    #endif
  }

  private func choose(_ id: String) {
    #if os(tvOS)
    draftId = id
    #else
    selectedClientId = id
    if let onPicked {
      onPicked()
    } else {
      dismiss()
    }
    #endif
  }

  @ViewBuilder
  private func clientOption(_ client: BundledClient) -> some View {
    let isSelected = shownId == client.id
    Button {
      choose(client.id)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 28, alignment: .center)
        Image(systemName: client.icon)
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .frame(width: 28, alignment: .center)
        VStack(alignment: .leading, spacing: 2) {
          Text(client.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text(client.description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
    .contentShape(Rectangle())
    .buttonStyle(.plain)
  }
}
