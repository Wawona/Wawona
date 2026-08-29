import Foundation

// MARK: - Docker Hub models
//
// Decoded from `container search <query> --json` / `container tags <repo> --json`
// (wwn-containers `wwn-oci`). The JSON key casing matches the CLI output exactly.

/// One repository hit from a Docker Hub search.
public struct ContainerSearchHit: Codable, Hashable, Sendable {
    public var repoName: String
    /// The resolved pullable registry reference (e.g. `docker.io/library/python`),
    /// computed by `wwn-oci` so GUI and CLI share one resolution rule.
    public var pullableRef: String
    public var shortDescription: String
    public var starCount: UInt64
    public var pullCount: UInt64
    public var isOfficial: Bool
    public var isAutomated: Bool

    private enum CodingKeys: String, CodingKey {
        case repoName = "repo_name"
        case pullableRef
        case shortDescription = "short_description"
        case starCount = "star_count"
        case pullCount = "pull_count"
        case isOfficial = "is_official"
        case isAutomated = "is_automated"
    }
}

public struct ContainerSearchResponse: Codable, Sendable {
    public var count: UInt64
    public var results: [ContainerSearchHit]
}

/// One tag hit for a Docker Hub repository.
public struct ContainerTagHit: Codable, Hashable, Sendable {
    public var name: String
    public var fullSize: UInt64?
    public var tagLastPushed: String?
    public var images: [ContainerTagImage]

    private enum CodingKeys: String, CodingKey {
        case name
        case fullSize = "full_size"
        case tagLastPushed = "tag_last_pushed"
        case images
    }
}

/// Per-architecture image record inside a tag hit.
public struct ContainerTagImage: Codable, Hashable, Sendable {
    public var architecture: String
    public var os: String
    public var digest: String
    public var size: UInt64
}

public struct ContainerTagsResponse: Codable, Sendable {
    public var count: UInt64
    public var results: [ContainerTagHit]
}

public extension ContainerTagHit {
    /// Architectures available for this tag (unique, in response order).
    var architectures: [String] {
        var seen = Set<String>()
        return images.compactMap { image in
            guard !image.architecture.isEmpty, seen.insert(image.architecture).inserted else {
                return nil
            }
            return image.architecture
        }
    }

    /// Human-readable size (or `-` when the Hub omits it).
    var sizeText: String {
        guard let fullSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(fullSize), countStyle: .file)
    }
}
