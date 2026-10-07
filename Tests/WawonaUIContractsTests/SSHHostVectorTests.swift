import Foundation
import Testing
import WawonaUIContracts

private func vectorURL() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<10 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent("verification/ssh_host_vector.tsv")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("ssh_host_vector.tsv")
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

@Test
func swiftFallbackMatchesRustVector() throws {
    let rows = try vectorRows()
    #expect(!rows.isEmpty)
    for row in rows {
        #expect(MachineEditorValidation.sanitizeSSHHost(row.0) == row.1)
    }
}

@Test
func sanitizeDropsShellMetacharactersFromSamples() {
    let alphabet = Array("abcXYZ.-:[]/ \"$`'&|;<>\\")
    var seed: UInt64 = 0xC0FFEE
    for _ in 0..<64 {
        seed = seed &* 6364136223846793005 &+ 1
        let len = Int(seed % 13)
        var chars: [Character] = []
        chars.reserveCapacity(len)
        var s = seed
        for _ in 0..<len {
            s = s &* 6364136223846793005 &+ 1
            chars.append(alphabet[Int(s % UInt64(alphabet.count))])
        }
        let sample = String(chars)
        let out = MachineEditorValidation.sanitizeSSHHost(sample)
        #expect(out.allSatisfy { ch in
            !ch.isWhitespace && !"\"'`$;&|<>\\".contains(ch)
        })
    }
}
