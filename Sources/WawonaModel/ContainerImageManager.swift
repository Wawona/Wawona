import Foundation

// MARK: - Local catalog model (mirrors wwn-oci `catalog::ImageEntry`)

/// One pulled image in the local catalog (`container images --json`).
public struct ContainerImageEntry: Codable, Hashable, Sendable {
    public let reference: String
    public let canonical: String
    public let manifestDigest: String
    public let configDigest: String
    public let layerDigests: [String]
    public let pulledAtUnix: UInt64
    public let rootfs: String?

    enum CodingKeys: String, CodingKey {
        case reference
        case canonical
        case manifestDigest = "manifest_digest"
        case configDigest = "config_digest"
        case layerDigests = "layer_digests"
        case pulledAtUnix = "pulled_at_unix"
        case rootfs
    }

    /// Short manifest digest for display (first 12 hex chars, no `sha256:`).
    public var shortDigest: String {
        let hex = manifestDigest.hasPrefix("sha256:") ? String(manifestDigest.dropFirst(7)) : manifestDigest
        return String(hex.prefix(12))
    }
}

// Docker Hub search/tags models live in ContainerHubModels.swift
// (ContainerSearchHit / ContainerTagHit / ContainerTagImage / *Response).

// MARK: - CLI bridge

/// Throws on any CLI failure (non-zero exit or unparseable output) with a
/// useful message for the UI.
public struct ContainerImageError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Shells out to the bundled `container` CLI (`wwn-oci` underneath) for image
/// management. Pure userspace on every target, so this is safe on iOS/watchOS
/// too (the CLI ships in Resources/bin and is App-Store-compliant for image
/// verbs). Execution (`run`) is handled separately by WWNContainerRunner and
/// is NOT part of this surface.
public enum ContainerImageManager {

    /// Resolve the bundled `container` CLI, or fall back to PATH.
    public static func containerCLIPath() -> String {
        #if !SWIFT_PACKAGE && os(macOS)
        // The app bundles the CLI at Contents/Resources/bin/container.
        if let bundle = Bundle.main.resourceURL {
            let bundled = bundle.appendingPathComponent("bin/container").path
            if FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }
        #endif
        return "container"
    }

    /// Environment for every CLI call: inherit the process env, and pin
    /// `WWN_OCI_ROOT` to the same image store the runner uses
    /// (`MachineContainerImageStore`, Settings → Containers), so imports land
    /// where `container run` looks and the emitted OCI layout dir is stable.
    private static func cliEnvironment() -> [String: String]? {
        var env = ProcessInfo.processInfo.environment
        #if os(macOS)
        if env["WWN_OCI_ROOT"] == nil,
           let store = UserDefaults.standard.string(forKey: "MachineContainerImageStore"),
           !store.isEmpty
        {
            env["WWN_OCI_ROOT"] = (store as NSString).expandingTildeInPath
        }
        #endif
        return env
    }

    // MARK: - operations

    /// List pulled images (returns `[]` when none).
    public static func listImages() throws -> [ContainerImageEntry] {
        let out = try run(["images", "--json"])
        guard let data = out.data(using: .utf8) else {
            throw ContainerImageError("empty output from `container images`")
        }
        return try JSONDecoder().decode([ContainerImageEntry].self, from: data)
    }

    /// Search Docker Hub (metadata only).
    public static func search(_ query: String, limit: Int = 20) async throws -> ContainerSearchResponse {
        let out = try await run(["search", query, "--json", "--limit", String(limit)])
        guard let data = out.data(using: .utf8) else {
            throw ContainerImageError("empty output from `container search`")
        }
        return try JSONDecoder().decode(ContainerSearchResponse.self, from: data)
    }

    /// List tags for a Docker Hub repository, optionally filtered client-side
    /// by a case-insensitive substring on the tag name.
    public static func tags(
        _ repository: String,
        limit: Int = 50,
        matching: String? = nil
    ) async throws -> ContainerTagsResponse {
        var args = ["tags", repository, "--json", "--limit", String(limit)]
        if let matching, !matching.isEmpty {
            args.append(contentsOf: ["--matches", matching])
        }
        let out = try await run(args)
        guard let data = out.data(using: .utf8) else {
            throw ContainerImageError("empty output from `container tags`")
        }
        return try JSONDecoder().decode(ContainerTagsResponse.self, from: data)
    }

    /// Search tags of a repository by substring, walking multiple pages.
    /// The Hub API has no server-side tag search and caps pages at 100, so
    /// large repos (e.g. linuxserver/webtop: 46k+ tags) need paging; stop
    /// early once `targetMatches` are collected or the last page is reached.
    public static func searchTags(
        _ repository: String,
        matching needle: String,
        maxPages: Int = 5,
        targetMatches: Int = 25,
        pageSize: Int = 100
    ) async throws -> [ContainerTagHit] {
        var collected: [ContainerTagHit] = []
        let normalized = needle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return [] }
        for page in 1...maxPages {
            var args = ["tags", repository, "--json", "--limit", String(pageSize), "--page", String(page)]
            args.append(contentsOf: ["--matches", needle])
            let out = try await run(args)
            guard let data = out.data(using: .utf8) else {
                throw ContainerImageError("empty output from `container tags`")
            }
            let resp = try JSONDecoder().decode(ContainerTagsResponse.self, from: data)
            collected.append(contentsOf: resp.results)
            if resp.results.count < pageSize || collected.count >= targetMatches {
                break
            }
        }
        return collected
    }

    /// Inspect a pulled image (pretty JSON; surfaced verbatim).
    public static func inspect(_ reference: String) throws -> String {
        try run(["inspect", reference])
    }

    /// Remove a pulled image from the local catalog.
    public static func remove(_ reference: String) throws {
        _ = try run(["rmi", reference])
    }

    /// Resolve a reference and print its components (validation hint).
    public static func resolve(_ reference: String) throws -> String {
        try run(["resolve", reference])
    }

    /// Pull an image, streaming progress lines via `onLine`.
    public static func pull(
        _ reference: String,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        try await runStreaming(["pull", reference], onLine: onLine)
    }

    /// Import an image from disk (docker-archive tar.gz, OCI-archive tar, or
    /// OCI layout directory; auto-detected), streaming progress via `onLine`.
    /// Returns the final output block (reference, digests, rootfs, and the
    /// generated OCI layout dir for `run --image-archive`).
    public static func importFromDisk(
        _ path: String,
        reference: String? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var args = ["import", path]
        if let reference, !reference.isEmpty {
            args.append(contentsOf: ["--reference", reference])
        }
        return try await runStreamingCapturing(args, onLine: onLine)
    }

    /// Result of an import: the canonical reference plus the generated OCI
    /// layout directory (what `run --image-archive` boots from).
    public struct ContainerImportResult: Sendable {
        public let canonical: String
        public let ociLayout: String
    }

    /// Import from disk and parse the canonical reference + OCI layout dir out
    /// of the CLI output, so the editor can fill both fields in one step.
    public static func importFromDiskResolved(
        _ path: String,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> ContainerImportResult {
        let out = try await importFromDisk(path, onLine: onLine)
        var canonical = ""
        var layout = ""
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("imported ") {
                canonical = String(line.dropFirst("imported ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("oci-layout: ") {
                layout = String(line.dropFirst("oci-layout: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !canonical.isEmpty else {
            throw ContainerImageError("import succeeded but produced unparseable output")
        }
        return ContainerImportResult(canonical: canonical, ociLayout: layout)
    }

    // MARK: - process plumbing

    private static func run(_ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: containerCLIPath())
        task.arguments = args
        task.environment = cliEnvironment()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            throw ContainerImageError("failed to run `container \(args.joined(separator: " "))`: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if task.terminationStatus != 0 {
            throw ContainerImageError(output.isEmpty ? "`container \(args.first ?? "")` failed (exit \(task.terminationStatus))" : output)
        }
        return output
    }

    private static func run(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try run(args))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Run a long command, forwarding each stdout line to `onLine` (on the
    /// caller's actor via the continuation's thread).
    private static func runStreaming(
        _ args: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: containerCLIPath())
                task.arguments = args
                task.environment = cliEnvironment()
                let pipe = Pipe()
                let errPipe = Pipe()
                task.standardOutput = pipe
                task.standardError = errPipe
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    let chunk = String(decoding: data, as: UTF8.self)
                    let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
                    for line in lines where !line.isEmpty {
                        onLine(String(line))
                    }
                }
                // Box stderr so a single serial queue owns it (no concurrent
                // mutation of a captured var across the readability handler).
                let errBox = ErrorBox()
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    errBox.append(data)
                }
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ContainerImageError("failed to run `container \(args.joined(separator: " "))`: \(error.localizedDescription)"))
                    return
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if task.terminationStatus != 0 {
                    let err = String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ContainerImageError(err.isEmpty ? "`container \(args.first ?? "")` failed (exit \(task.terminationStatus))" : err))
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    /// Run a long command, forwarding each stdout line to `onLine` (on the
    /// caller's actor via the continuation's thread), and returning the
    /// complete stdout at the end (for commands whose final block matters).
    private static func runStreamingCapturing(
        _ args: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: containerCLIPath())
                task.arguments = args
                task.environment = cliEnvironment()
                let pipe = Pipe()
                let errPipe = Pipe()
                task.standardOutput = pipe
                task.standardError = errPipe
                let outBox = OutputBox()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    let chunk = String(decoding: data, as: UTF8.self)
                    let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
                    for line in lines where !line.isEmpty {
                        outBox.append(String(line) + "\n")
                        onLine(String(line))
                    }
                }
                let errBox = ErrorBox()
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    errBox.append(data)
                }
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ContainerImageError("failed to run `container \(args.joined(separator: " "))`: \(error.localizedDescription)"))
                    return
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if task.terminationStatus != 0 {
                    let err = String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ContainerImageError(err.isEmpty ? "`container \(args.first ?? "")` failed (exit \(task.terminationStatus))" : err))
                    return
                }
                continuation.resume(returning: outBox.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Serial queue-owned stdout accumulator for `runStreamingCapturing`.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _text = ""
        func append(_ s: String) {
            lock.lock(); defer { lock.unlock() }
            _text += s
        }
        var text: String {
            lock.lock(); defer { lock.unlock() }
            return _text
        }
    }

    /// Serial queue-owned stderr accumulator for `runStreaming`.
    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _data = Data()
        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            _data.append(data)
        }
        var data: Data {
            lock.lock(); defer { lock.unlock() }
            return _data
        }
    }
}
