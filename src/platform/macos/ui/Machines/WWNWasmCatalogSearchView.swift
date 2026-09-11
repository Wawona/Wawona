import SwiftUI
import WawonaModel

/// Search `https://repo.wawona.io/wasm/v1`. Never APT / jailbreak / Termux.
struct WWNWasmCatalogSearchView: View {
  let onSelect: (WWNWasmCatalogPackage) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query: String = ""
  @State private var results: [WWNWasmCatalogPackage] = []
  @State private var searchError: String?
  @State private var isSearching = false
  @State private var hasSearched = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          TextField("Search wasm, e.g. hello-wasi-gui", text: $query)
            .textFieldStyle(.roundedBorder)
            .wawonaTextFieldNoAutocaps()
            .autocorrectionDisabled()
            .onSubmit { Task { await search() } }
          Button("Search") { Task { await search() } }
            .disabled(isSearching)
        }
        .padding()

        Divider()

        Group {
          if isSearching {
            ProgressView("Searching wasm catalog...")
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if let searchError {
            Text(searchError)
              .foregroundStyle(.red)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if !hasSearched {
            Text("repo.wawona.io /wasm/v1. Store-safe bytecode only.")
              .foregroundStyle(.secondary)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if results.isEmpty {
            Text("No matches")
              .foregroundStyle(.secondary)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            List(results) { pkg in
              Button {
                onSelect(pkg)
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(pkg.name).font(.headline)
                  Text("\(pkg.version)  \(pkg.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Wasm catalog")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 420)
      #endif
    }
    .task { await search() }
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
