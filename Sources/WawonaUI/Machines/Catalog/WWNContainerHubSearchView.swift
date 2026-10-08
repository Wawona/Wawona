import SwiftUI
import WawonaModel

/// Docker Hub search sheet for the container machine editor. Two levels:
/// repo search results, then a per-repo tag drill-in. Selecting a tag hands
/// back a fully qualified reference built by the CLI (`pullableRef:tag`),
/// so the GUI and `container run` share one resolution rule.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNContainerHubSearchView: View {
  /// Called with the chosen image reference, e.g.
  /// `docker.io/library/python:3.12-slim`.
  let onSelect: (String) -> Void

  @Environment(\.presentationMode) private var presentationMode
  private func dismiss() { presentationMode.wrappedValue.dismiss() }

  @State private var query: String = ""
  @State private var results: [ContainerSearchHit] = []
  @State private var searchError: String?
  @State private var isSearching = false
  @State private var hasSearched = false

  @State private var tagsRepo: ContainerSearchHit?
  @State private var tags: [ContainerTagHit] = []
  @State private var tagsTotalCount: UInt64 = 0
  @State private var tagsError: String?
  @State private var tagsLoading = false

  var body: some View {
    WawonaBackport<Any>.navigation {
      Group {
        if let repo = tagsRepo {
          tagsView(for: repo)
        } else {
          searchView
        }
      }
      .backport.navigationTitle(tagsRepo?.repoName ?? "Docker Hub")
      .backport.navigationActions {
        if tagsRepo != nil {
          WawonaButton("Back") { tagsRepo = nil; tags = []; tagsError = nil }
            .backport.glassToolbarButton()
        } else {
          WawonaButton("Close") { dismiss() }.backport.glassToolbarButton()
        }
      } trailing: { EmptyView() }
      #if os(macOS)
      .frame(minWidth: 560, minHeight: 460)
      #endif
    }
  }

  // MARK: - Search level

  private var searchView: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        WawonaTextField("Search images, e.g. python", text: $query)
          .textFieldStyle(.roundedBorder)
          .wawonaTextFieldNoAutocaps()
          .disableAutocorrection(true)
          .backport.onSubmit { Task { await search() } }
        WawonaButton("Search") { Task { await search() } }
          .disabled(
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || isSearching)
      }
      .padding()

      Divider()

      Group {
        if isSearching {
          centered {
            WawonaProgressView("Searching Docker Hub...")
          }
        } else if let searchError {
          centered { errorView(searchError) }
        } else if !hasSearched {
          centered {
            VStack(spacing: 10) {
              Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundColor(.secondary)
              Text("Search Docker Hub for OCI images, then pick a tag to use "
                + "in this machine's Image field.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            }
          }
        } else if results.isEmpty {
          centered {
            VStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
              Text("No repositories matched \"\(query)\".")
                .font(.callout)
                .foregroundColor(.secondary)
            }
          }
        } else {
          List(results, id: \.repoName) { hit in
            WawonaButton { Task { await loadTags(for: hit) } } label: {
              repoRow(hit)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func repoRow(_ hit: ContainerSearchHit) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(hit.repoName)
            .font(.headline)
          if hit.isOfficial {
            Image(systemName: "checkmark.seal.fill")
              .foregroundColor(.blue)
          }
        }
        Text(hit.pullableRef)
          .font(.caption)
          .foregroundColor(.secondary)
        if !hit.shortDescription.isEmpty {
          Text(hit.shortDescription)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 3) {
        Text("\(WawonaBackport<Any>.compactCount(hit.starCount)) stars")
          .font(.caption)
          .foregroundColor(.secondary)
        Text("\(WawonaBackport<Any>.compactCount(hit.pullCount)) pulls")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  // MARK: - Tags level

  private func tagsView(for repo: ContainerSearchHit) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(repo.pullableRef)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(1)
        Spacer()
        if tagsTotalCount > tags.count {
          Text("Showing \(tags.count) of \(tagsTotalCount) tags")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 10)

      Divider()

      Group {
        if tagsLoading {
          centered { WawonaProgressView("Loading tags...") }
        } else if let tagsError {
          centered { errorView(tagsError) }
        } else {
          List {
            // Convenience row: use the repo reference as-is (default tag).
            WawonaButton {
              onSelect(repo.pullableRef)
              dismiss()
            } label: {
              HStack {
                Text("Default tag (latest)")
                  .font(.headline)
                Spacer()
                Image(systemName: "arrow.right.circle")
                  .foregroundColor(.secondary)
              }
              .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            ForEach(Array(tags.prefix(60)), id: \.name) { tag in
              WawonaButton {
                onSelect("\(repo.pullableRef):\(tag.name)")
                dismiss()
              } label: {
                tagRow(tag)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private func tagRow(_ tag: ContainerTagHit) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(tag.name)
          .font(.headline)
        Text(tag.sizeText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      ForEach(Array(tag.architectures.prefix(4)), id: \.self) { arch in
        Text(arch)
          .font(.system(size: 11, design: .monospaced))
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .backport.background(
            arch == "arm64"
              ? Color.blue.opacity(0.25)
              : Color.secondary.opacity(0.15),
            in: Capsule()
          )
      }
    }
    .padding(.vertical, 2)
  }

  // MARK: - Helpers

  private func centered<Content: View>(
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    VStack {
      Spacer()
      content()
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private func errorView(_ message: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundColor(.orange)
      Text(message)
        .font(.callout)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 48)
    }
  }

  @MainActor
  private func search() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isSearching = true
    searchError = nil
    hasSearched = true
    defer { isSearching = false }
    do {
      let data = try await WWNContainerHubClient.run(.search(trimmed))
      let response = try JSONDecoder().decode(
        ContainerSearchResponse.self, from: data)
      results = response.results
    } catch is DecodingError {
      searchError = "The container CLI returned unexpected output."
    } catch {
      searchError = error.localizedDescription
    }
  }

  @MainActor
  private func loadTags(for repo: ContainerSearchHit) async {
    tagsRepo = repo
    tags = []
    tagsError = nil
    tagsLoading = true
    defer { tagsLoading = false }
    do {
      let data = try await WWNContainerHubClient.run(.tags(repo.pullableRef))
      let response = try JSONDecoder().decode(
        ContainerTagsResponse.self, from: data)
      tags = response.results
      tagsTotalCount = response.count
    } catch is DecodingError {
      tagsError = "The container CLI returned unexpected output."
    } catch {
      tagsError = error.localizedDescription
    }
  }
}
