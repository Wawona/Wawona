import Foundation
import WawonaModel

struct WWNWasmCatalogPackage: Identifiable, Hashable, Sendable {
  var name: String
  var version: String
  var digest: String
  var url: String
  var summary: String

  var id: String { "\(name)@\(version)" }
}

enum WWNWasmCatalogClient {
  static func search(_ query: String) async throws -> [WWNWasmCatalogPackage] {
    try await Task.detached {
      try WasmLaunch.searchCatalog(query).map(Self.wrap)
    }.value
  }

  static func fetchIndex() async throws -> [WWNWasmCatalogPackage] {
    try await Task.detached {
      try WasmLaunch.fetchCatalogIndex().map(Self.wrap)
    }.value
  }

  /// Download a catalog package into Documents/Wawona/wasm-modules. Wasm channel only.
  static func download(_ package: WWNWasmCatalogPackage) async throws -> String {
    try await Task.detached {
      try WasmLaunch.downloadPackage(
        WasmCatalogPackage(
          name: package.name,
          version: package.version,
          digest: package.digest,
          url: package.url,
          summary: package.summary
        )
      )
    }.value
  }

  private static func wrap(_ pkg: WasmCatalogPackage) -> WWNWasmCatalogPackage {
    WWNWasmCatalogPackage(
      name: pkg.name,
      version: pkg.version,
      digest: pkg.digest,
      url: pkg.url,
      summary: pkg.summary
    )
  }
}

/// ObjC Start path. Resolves `wpm install` / catalog names to a file when needed.
@objc(WWNWasmLaunchBridge)
final class WWNWasmLaunchBridge: NSObject {
  @objc static func ensureArgWithModulePath(_ modulePath: String, package: String, command: String) -> String {
    WasmLaunch.ensureArg(
      spec: WasmLaunchSpec(
        mode: .command,
        modulePath: modulePath,
        package: package,
        command: command
      )
    )
  }
}

enum WWNWasmCatalogError: LocalizedError {
  case refusedURL
  case http(Int)
  case notWasm

  var errorDescription: String? {
    switch self {
    case .refusedURL:
      return "Wasm catalog only. Refusing a non /wasm/v1 URL."
    case .http(let code):
      return "Wasm catalog HTTP \(code)"
    case .notWasm:
      return "Download is not a Wasm module"
    }
  }
}
