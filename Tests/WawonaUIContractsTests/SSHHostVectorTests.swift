import Foundation
import Testing
import WawonaUIContracts
import SwiftCheck
import XCTest

private func vectorURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("verification/ssh_host_vector.tsv")
}

private func vectorRows() throws -> [(String, String)] {
    let text = try String(contentsOf: vectorURL(), encoding: .utf8)
    return text.split(separator: "\n").compactMap { line in
        if line.isEmpty || line.hasPrefix("#") { return nil }
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

private let sshHostRows: [(String, String)] = {
    (try? vectorRows()) ?? []
}()

@Test(arguments: sshHostRows)
func swiftFallbackMatchesRustVector(row: (String, String)) {
    #expect(MachineEditorValidation.sanitizeSSHHost(row.0) == row.1)
}

struct HostChars: Arbitrary {
    let value: String
    static var arbitrary: Gen<HostChars> {
        Gen<Character>.fromElements(of: Array("abcXYZ.-:[]/ ")).proliferate(withSize: 12)
            .map { HostChars(value: String($0)) }
    }
}

final class SanitizeProperties: XCTestCase {
    func testNoShellMetacharacters() {
        property("sanitize drops shell metacharacters") <- forAll { (sample: HostChars) in
            let out = MachineEditorValidation.sanitizeSSHHost(sample.value)
            return out.allSatisfy { ch in
                !ch.isWhitespace && !"\"'`$;&|<>\\".contains(ch)
            }
        }
    }
}
