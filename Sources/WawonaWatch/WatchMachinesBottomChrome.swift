#if os(watchOS)
import SwiftUI

/// Search sits bottom-left. Add sits bottom-right in primary blue.
struct WatchMachinesBottomChrome: View {
    @Binding var searchPresented: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack {
            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
            .accessibilityIdentifier("wwn.watch.search")

            Spacer(minLength: 0)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.blue))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Machine")
            .accessibilityIdentifier("wwn.watch.add")
        }
        .padding(.horizontal, 4)
    }

    private func toggleSearch() {
        searchPresented.toggle()
    }
}
#endif
