import SwiftUI
import WawonaModel

#if os(tvOS)
/// Dedicated Machines search on tvOS. Toggling `.searchable` on the split
/// detail remounts the NavigationStack and breaks Liquid Glass chrome, so the
/// native search field lives here. The query is local: the Machines grid is
/// never filtered, and Done always returns to the full grid.
struct WWNTvMachinesSearchCover<Card: View>: View {
  let results: (String) -> [WWNMachineProfile]
  @ViewBuilder let card: (WWNMachineProfile, String) -> Card
  var onClose: () -> Void

  @State private var query = ""

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        resultsContent
          .padding(60)
      }
      .scrollClipDisabled()
      .background {
        Color(white: 0.07).ignoresSafeArea()
      }
      .searchable(text: $query, prompt: "Search machines")
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .navigationTitle("Search")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: close)
            .backport.glassProminentToolbarButton()
            .wwnA11y(WWNA11y.machinesSearch, label: "Done searching")
        }
      }
      .onExitCommand(perform: close)
    }
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private var resultsContent: some View {
    let matches = results(trimmedQuery)
    if matches.isEmpty {
      ContentUnavailableView.search(text: trimmedQuery)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    } else {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 420), spacing: 48, alignment: .top)],
        alignment: .leading,
        spacing: 48
      ) {
        ForEach(matches, id: \.machineId) { profile in
          card(profile, trimmedQuery)
        }
      }
      .focusSection()
    }
  }

  private func close() {
    query = ""
    onClose()
  }
}
#endif
