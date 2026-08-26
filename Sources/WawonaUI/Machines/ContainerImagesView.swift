import SwiftUI
import WawonaModel
import UniformTypeIdentifiers

/// Container image browser: search Docker Hub (with tag picking), pull with
/// live progress, and manage the local catalog (list / inspect / remove).
/// Drives the bundled `container` CLI (wwn-oci) — pure image management, so it
/// works on macOS and every Apple target where the CLI ships.
///
/// `onSelect` is invoked when the user taps "Use" on an image/tag; callers wire
/// that into the container machine's image field.
struct ContainerImagesView: View {
    let onSelect: ((String) -> Void)?

    @State private var mode: Mode = .library
    @State private var images: [ContainerImageEntry] = []
    @State private var loadError: String?

    @State private var searchQuery = ""
    @State private var searchResults: [ContainerSearchHit] = []
    @State private var searchTotal: UInt64 = 0
    @State private var isSearching = false

    @State private var tagRepo = ""
    @State private var tagFilter = ""

    @State private var pullingReference: String?
    @State private var pullLog: [String] = []
    @State private var pullError: String?

    @State private var showingFileImporter = false

    @State private var inspectedEntry: ContainerImageEntry?
    @State private var inspectText: String?

    @State private var pendingRemove: ContainerImageEntry?

    enum Mode { case library, search }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .library: libraryView
                case .search: searchView
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("", selection: $mode) {
                        Label("Library", systemImage: "shippingbox").tag(Mode.library)
                        Label("Discover", systemImage: "magnifyingglass").tag(Mode.search)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            .task { refreshLibrary() }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .directory]
            ) { result in
                handleImportResult(result)
            }
            .alert(item: $pendingRemove) { entry in
                Alert(
                    title: Text("Remove image?"),
                    message: Text("\(entry.canonical)\n\nThe unpacked rootfs is deleted; shared blobs are kept."),
                    primaryButton: .destructive(Text("Remove")) {
                        do {
                            try ContainerImageManager.remove(entry.canonical)
                            refreshLibrary()
                        } catch {
                            removeError = error.localizedDescription
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Error", isPresented: Binding(get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(removeError ?? "")
            }
            .sheet(item: $inspectedEntry) { entry in
                inspectSheet(entry)
            }
            .sheet(item: $tagBrowser) { request in
                TagBrowserSheet(repository: request.repo, filter: request.filter) { ref in
                    tagBrowser = nil
                    Task { await startPull(ref) }
                }
            }
        }
    }

    @State private var removeError: String?

    private var navigationTitle: String {
        switch mode {
        case .library: return "Container Images"
        case .search: return "Discover Images"
        }
    }

    // MARK: - Library

    private var libraryView: some View {
        List {
            if let loadError {
                errorRow(loadError)
            }

            if pullingReference != nil {
                Section("Pulling") {
                    pullingRow
                }
            }

            Section {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from disk…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Imports a docker-archive (tar/tar.gz), OCI-archive, or OCI layout directory — format is detected automatically.")
            }

            Section {
                if images.isEmpty && pullingReference == nil && loadError == nil {
                    emptyLibraryRow
                }
                ForEach(images, id: \.canonical) { entry in
                    imageRow(entry)
                }
            } header: {
                if !images.isEmpty {
                    Text("\(images.count) image\(images.count == 1 ? "" : "s")")
                }
            }
        }
        .refreshable { refreshLibrary() }
    }

    private var emptyLibraryRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No images pulled")
                    .foregroundStyle(.secondary)
                Text("Use Discover to find an image, then pull it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }

    private var pullingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView().controlSize(.small)
                Text(pullingReference ?? "").monospaced().textSelection(.enabled)
            }
            if let pullError {
                Text(pullError).font(.caption).foregroundStyle(.red)
            } else {
                Text(pullLog.last ?? "Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func imageRow(_ entry: ContainerImageEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.canonical)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(entry.shortDigest)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(pulledDate(entry.pulledAtUnix))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Info") { inspectedEntry = entry }
                Button("Remove", role: .destructive) { pendingRemove = entry }
                if let onSelect {
                    Button("Use") { onSelect(entry.canonical); dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func pulledDate(_ unix: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func refreshLibrary() {
        do {
            images = try ContainerImageManager.listImages()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Search

    private var searchView: some View {
        List {
            Section {
                HStack {
                    TextField("Search Docker Hub", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await runSearch() } }
                    Button {
                        Task { await runSearch() }
                    } label: {
                        Label("Search", systemImage: "arrow.right")
                    }
                    .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
            }

            Section("Search tags of a repository") {
                TextField("Repository (e.g. linuxserver/webtop)", text: $tagRepo)
                    .textFieldStyle(.roundedBorder)
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                HStack {
                    TextField("Tag filter (optional)", text: $tagFilter)
                        .textFieldStyle(.roundedBorder)
                        .wawonaTextFieldNoAutocaps()
                        .autocorrectionDisabled()
                    Button {
                        tagBrowser = TagBrowserRequest(repo: tagRepo, filter: tagFilter)
                    } label: {
                        Label("List Tags", systemImage: "tag")
                    }
                    .disabled(tagRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if isSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !searchResults.isEmpty {
                Section("Results (\(searchResults.count) of \(searchTotal))") {
                    ForEach(searchResults, id: \.pullableRef) { result in
                        searchRow(result)
                    }
                }
            } else if !searchQuery.isEmpty && !isSearching {
                Text("No results.").foregroundStyle(.secondary)
            }
        }
    }

    private func searchRow(_ result: ContainerSearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.pullableRef)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if result.isOfficial {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                }
                Spacer()
                Label("\(result.starCount)", systemImage: "star")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.shortDescription.isEmpty {
                Text(result.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Text(pullCountString(result.pullCount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Pull…") { tagBrowser = TagBrowserRequest(repo: result.pullableRef, filter: "") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private func pullCountString(_ n: UInt64) -> String {
        if n >= 1_000_000_000 { return "\(n / 1_000_000_000)B pulls" }
        if n >= 1_000_000 { return "\(n / 1_000_000)M pulls" }
        if n >= 1_000 { return "\(n / 1_000)K pulls" }
        return "\(n) pulls"
    }

    private func runSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let resp = try await ContainerImageManager.search(q)
            searchResults = resp.results
            searchTotal = resp.count
        } catch {
            searchResults = []
            loadError = error.localizedDescription
        }
    }

    // MARK: - Pull: browse a repository's tags, then pull

    /// A request to browse a repository's tags (from a search hit or direct
    /// input). Identifiable so it drives a sheet.
    struct TagBrowserRequest: Identifiable {
        let repo: String
        let filter: String
        var id: String { repo + "|" + filter }
    }

    @State private var tagBrowser: TagBrowserRequest?

    /// Tag browser for a repository: fetches tags (optionally filtered),
    /// shows arches, and pulls the selected one.
    private struct TagBrowserSheet: View {
        let repository: String
        let filter: String
        let onPull: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var tags: [ContainerTagHit] = []
        @State private var tagError: String?
        @State private var isLoading = true

        var body: some View {
            NavigationStack {
                List {
                    if let tagError {
                        Text(tagError).foregroundStyle(.red)
                    }
                    if isLoading && tags.isEmpty && tagError == nil {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    if !isLoading && tags.isEmpty {
                        Text(filter.isEmpty ? "No tags found." : "No tags match \"\(filter)\".")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tags, id: \.name) { tag in
                        Button {
                            let ref = tag.name == "latest"
                                ? repository
                                : "\(repository):\(tag.name)"
                            onPull(ref)
                        } label: {
                            HStack {
                                Text(tag.name).monospaced()
                                Spacer()
                                Text(tag.architectures.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Tags · \(repository)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .task {
                    do {
                        if filter.trimmingCharacters(in: .whitespaces).isEmpty {
                            tags = try await ContainerImageManager.tags(repository, limit: 100).results
                        } else {
                            tags = try await ContainerImageManager.searchTags(repository, matching: filter)
                        }
                    } catch {
                        tagError = error.localizedDescription
                    }
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Pull

    private func startPull(_ reference: String) async {
        pullingReference = reference
        pullLog = []
        pullError = nil
        mode = .library
        do {
            try await ContainerImageManager.pull(reference) { line in
                Task { @MainActor in
                    pullLog.append(line)
                    if pullLog.count > 200 { pullLog.removeFirst(pullLog.count - 200) }
                }
            }
            refreshLibrary()
        } catch {
            pullError = error.localizedDescription
        }
        pullingReference = nil
    }

    // MARK: - Import from disk

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            removeError = error.localizedDescription
        case .success(let url):
            Task { await startImport(url.path) }
        }
    }

    private func startImport(_ path: String) async {
        pullingReference = "import \(path)"
        pullLog = []
        pullError = nil
        mode = .library
        do {
            _ = try await ContainerImageManager.importFromDisk(path) { line in
                Task { @MainActor in
                    pullLog.append(line)
                    if pullLog.count > 200 { pullLog.removeFirst(pullLog.count - 200) }
                }
            }
            refreshLibrary()
        } catch {
            pullError = error.localizedDescription
        }
        pullingReference = nil
    }

    private func inspectSheet(_ entry: ContainerImageEntry) -> some View {
        NavigationStack {
            ScrollView {
                Text(inspectText ?? "Loading…")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("\(entry.canonical) — details")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { inspectedEntry = nil } } }
            .task {
                do {
                    inspectText = try ContainerImageManager.inspect(entry.canonical)
                } catch {
                    inspectText = "Inspect failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    @Environment(\.dismiss) private var dismiss
}

extension ContainerSearchHit: Identifiable {
    public var id: String { pullableRef }
}

extension ContainerImageEntry: Identifiable {
    public var id: String { canonical }
}
