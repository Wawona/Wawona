import SwiftUI
import WawonaModel

/// Docker Hub search sheet for the container machine editor. Two levels:
/// repo search results, then a per-repo tag drill-in. Selecting a tag hands
/// back a fully qualified reference built by the CLI (`pullableRef:tag`),
/// so the GUI and `container run` share one resolution rule.
struct WWNContainerHubSearchView: View {
  /// Called with the chosen image reference, e.g.
  /// `docker.io/library/python:3.12-slim`.
  let onSelect: (String) -> Void

  @Environment(\.dismiss) private var dismiss

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
    NavigationStack {
      Group {
        if let repo = tagsRepo {
          tagsView(for: repo)
        } else {
          searchView
        }
      }
      .navigationTitle(tagsRepo?.repoName ?? "Docker Hub")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if tagsRepo != nil {
            Button("Back") {
              tagsRepo = nil
              tags = []
              tagsError = nil
            }
          } else {
            Button("Close") { dismiss() }
          }
        }
      }
      .frame(minWidth: 560, minHeight: 460)
    }
  }

  // MARK: - Search level

  private var searchView: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        TextField("Search images, e.g. python", text: $query)
          .textFieldStyle(.roundedBorder)
          .wawonaTextFieldNoAutocaps()
          .autocorrectionDisabled()
          .onSubmit { Task { await search() } }
        Button("Search") { Task { await search() } }
          .disabled(
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || isSearching)
      }
      .padding()

      Divider()

      Group {
        if isSearching {
          centered {
            ProgressView("Searching Docker Hub...")
          }
        } else if let searchError {
          centered { errorView(searchError) }
        } else if !hasSearched {
          centered {
            VStack(spacing: 10) {
              Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
              Text("Search Docker Hub for OCI images, then pick a tag to use "
                + "in this machine's Image field.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            }
          }
        } else if results.isEmpty {
          centered {
            VStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
              Text("No repositories matched \"\(query)\".")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        } else {
          List(results, id: \.repoName) { hit in
            Button { Task { await loadTags(for: hit) } } label: {
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
              .foregroundStyle(.blue)
          }
        }
        Text(hit.pullableRef)
          .font(.caption)
          .foregroundStyle(.secondary)
        if !hit.shortDescription.isEmpty {
          Text(hit.shortDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 3) {
        Text("\(hit.starCount.formatted(.number.notation(.compactName))) stars")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("\(hit.pullCount.formatted(.number.notation(.compactName))) pulls")
          .font(.caption)
          .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
        if tagsTotalCount > tags.count {
          Text("Showing \(tags.count) of \(tagsTotalCount) tags")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 10)

      Divider()

      Group {
        if tagsLoading {
          centered { ProgressView("Loading tags...") }
        } else if let tagsError {
          centered { errorView(tagsError) }
        } else {
          List {
            // Convenience row: use the repo reference as-is (default tag).
            Button {
              onSelect(repo.pullableRef)
              dismiss()
            } label: {
              HStack {
                Text("Default tag (latest)")
                  .font(.headline)
                Spacer()
                Image(systemName: "arrow.right.circle")
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            ForEach(Array(tags.prefix(60)), id: \.name) { tag in
              Button {
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
          .foregroundStyle(.secondary)
      }
      Spacer()
      ForEach(Array(tag.architectures.prefix(4)), id: \.self) { arch in
        Text(arch)
          .font(.caption2.monospaced())
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(
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
        .foregroundStyle(.orange)
      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
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
