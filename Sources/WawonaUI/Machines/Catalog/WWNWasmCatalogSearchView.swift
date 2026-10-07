import SwiftUI
import WawonaModel

/// Search `https://repo.wawona.io/wasm/v1`. Never APT / jailbreak / Termux.
struct WWNWasmCatalogSearchView: View {
  let onSelect: (WWNWasmCatalogPackage) -> Void

  @Environment(\.presentationMode) private var presentationMode
  private func dismiss() { presentationMode.wrappedValue.dismiss() }
  @State private var query: String = ""
  @State private var results: [WWNWasmCatalogPackage] = []
  @State private var searchError: String?
  @State private var isSearching = false
  @State private var hasSearched = false

  var body: some View {
    WawonaBackport<Any>.navigation {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          WawonaTextField("Search wasm, e.g. hello-wasi-gui", text: $query)
            .textFieldStyle(.roundedBorder)
            .wawonaTextFieldNoAutocaps()
            .disableAutocorrection(true)
            .backport.onSubmit { Task { await search() } }
          WawonaButton("Search") { Task { await search() } }
            .disabled(isSearching)
        }
        .padding()

        Divider()

        Group {
          if isSearching {
            WawonaProgressView("Searching wasm catalog...")
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if let searchError {
            Text(searchError)
              .foregroundColor(.red)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if !hasSearched {
            Text("repo.wawona.io /wasm/v1. Store-safe bytecode only.")
              .foregroundColor(.secondary)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if results.isEmpty {
            Text("No matches")
              .foregroundColor(.secondary)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            List(results) { pkg in
              WawonaButton {
                onSelect(pkg)
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(pkg.name).font(.headline)
                  Text("\(pkg.version)  \(pkg.summary)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                }
              }
            }
          }
        }
      }
      .backport.navigationTitle("Wasm catalog")
      .backport.navigationActions {
        WawonaButton("Close") { dismiss() }.backport.glassToolbarButton()
      } trailing: { EmptyView() }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 420)
      #endif
    }
    .backport.task { await search() }
  }

  private func search() async {
    isSearching = true
    searchError = nil
    do {
      results = try await WWNWasmCatalogClient.search(query)
      hasSearched = true
    } catch {
      searchError = error.localizedDescription
    }
    isSearching = false
  }
}
