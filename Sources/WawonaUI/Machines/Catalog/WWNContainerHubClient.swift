import Foundation

/// Runs the wwn-containers `container` CLI for read-only Docker Hub queries
/// (`search` / `tags --json`). The CLI is the single source of truth for
/// registry reference resolution (`pullableRef`); the GUI renders its JSON
/// verbatim and never re-implements registry rules.
///
/// Resolution order: the bundled `Contents/Resources/bin/container` first
/// (works in the signed app without a system install), then the user's PATH
/// via env(1). No hardcoded fallback paths.
enum WWNContainerHubClient {

  struct CLIError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
  }

  enum Request: Sendable {
    case search(String)
    case tags(String)

    var arguments: [String] {
      switch self {
      case .search(let query): return ["search", query, "--json"]
      case .tags(let repo): return ["tags", repo, "--json"]
      }
    }
  }

  /// Runs the command and returns raw stdout JSON, or throws a user-facing
  /// error. The command is bounded by a 45 second watchdog so a wedged
  /// network fetch cannot leave a zombie process behind.
  static func run(_ request: Request) async throws -> Data {
    #if os(macOS)
    let (executablePath, prefixArguments) = resolveExecutable()
    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.executableURL = URL(fileURLWithPath: executablePath)
      process.arguments = prefixArguments + request.arguments
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      process.environment = ProcessInfo.processInfo.environment.merging(
        ["WAWONA_CONTAINER_BACKEND": "containerization"],
        uniquingKeysWith: { _, new in new }
      )

      do {
        try process.run()
      } catch {
        throw CLIError(
          "Could not launch the container CLI: \(error.localizedDescription)")
      }

      let watchdog = DispatchWorkItem {
        if process.isRunning {
          process.terminate()
        }
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)

      // Reading stdout to EOF first is safe here: the CLI's stderr volume for
      // these queries stays far below the pipe buffer, so this cannot
      // deadlock. The CLI itself page-limits hub responses.
      let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      watchdog.cancel()

      guard process.terminationStatus == 0 else {
        let detail =
          String(data: stderrData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if detail.isEmpty {
          throw CLIError(
            "The container CLI exited with status \(process.terminationStatus).")
        }
        throw CLIError(detail)
      }
      return stdoutData
    }.value
    #else
    _ = request
    throw CLIError("Docker Hub search is available on macOS only.")
    #endif
  }

  #if os(macOS)
  private static func resolveExecutable() -> (path: String, prefix: [String]) {
    if let resourcePath = Bundle.main.resourcePath {
      let bundled =
        (resourcePath as NSString).appendingPathComponent("bin/container")
      if FileManager.default.isExecutableFile(atPath: bundled) {
        return (bundled, [])
      }
    }
    // PATH lookup via env(1): the same resolution the in-app terminal uses.
    return ("/usr/bin/env", ["container"])
  }
  #endif
}
