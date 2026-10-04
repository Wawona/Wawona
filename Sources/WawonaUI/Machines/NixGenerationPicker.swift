import Foundation
import SwiftUI
#if canImport(Darwin)
import Darwin
#endif

/// Host boot menu for NixOS system generations. Relay reads the disk profile.
/// Choosing a generation points `system` at `system-N-link` on the next start.
/// The command line stays `init=/init`.
public struct NixGenerationPicker: View {
    let machineId: String
    let vmIdentifier: String
    @Binding var generation: Int?
    @State private var rows: [NixGenerationRow] = []
    @State private var note = "NixOS boots the disk's current generation."

    public init(machineId: String, vmIdentifier: String, generation: Binding<Int?>) {
        self.machineId = machineId
        self.vmIdentifier = vmIdentifier
        _generation = generation
    }

    public var body: some View {
        #if os(watchOS) || os(tvOS)
        EmptyView()
        #else
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Picker("NixOS generation", selection: selection) {
                    Text("Current profile").tag(0)
                    ForEach(rows) { row in
                        Text(row.title).tag(row.number)
                    }
                    if let generation, generation > 0, !rows.contains(where: { $0.number == generation }) {
                        Text("Generation \(generation)").tag(generation)
                    }
                }
                .accessibility(identifier: "wwn.vm.generation")
                Text("Start points the NixOS system profile at this generation and boots init=/init.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear(perform: reload)
        .backport.onChange(of: machineId) { _, _ in reload() }
        .backport.onChange(of: vmIdentifier) { _, _ in reload() }
        #endif
    }

    private var selection: Binding<Int> {
        Binding(
            get: { generation ?? 0 },
            set: { generation = $0 > 0 ? $0 : nil }
        )
    }

    private func reload() {
        guard let path = NixGenerationDisk.path(machineId: machineId, vmIdentifier: vmIdentifier) else {
            note = "Save the machine before choosing a NixOS generation."
            rows = []
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            note = "The NixOS disk is created on the first start. It boots generation 1."
            rows = []
            return
        }
        guard let document = NixGenerationDisk.load(path) else {
            note = "NixOS generations could not be read from this disk."
            rows = []
            return
        }
        rows = document.generations.map { entry in
            let marker = entry.current ? " (current)" : ""
            return NixGenerationRow(
                number: entry.number,
                title: "Generation \(entry.number): \(entry.label)\(marker)"
            )
        }
        if rows.isEmpty {
            note = "This disk has no NixOS generation profile."
        }
    }
}

struct NixGenerationRow: Identifiable {
    var number: Int
    var title: String
    var id: Int { number }
}

enum NixGenerationDisk {
    struct Document: Decodable {
        struct Entry: Decodable {
            let number: Int
            let label: String
            let current: Bool
        }
        let present: Bool
        let generations: [Entry]
    }

    static func path(machineId: String, vmIdentifier: String) -> String? {
        let override = vmIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = override.isEmpty ? machineId : override
        guard !id.isEmpty, id.count <= 128 else { return nil }
        guard id.allSatisfy({ character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
        }), id != ".", id != ".." else { return nil }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("Wawona/relay-state/machines", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("rootfs.img")
            .path
    }

    static func load(_ path: String) -> Document? {
        #if canImport(Darwin)
        typealias List = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
        typealias Free = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(handle, "relay_nixos_generations"),
              let freeSymbol = dlsym(handle, "relay_string_free") else { return nil }
        let list = unsafeBitCast(symbol, to: List.self)
        let release = unsafeBitCast(freeSymbol, to: Free.self)
        var output: UnsafeMutablePointer<CChar>?
        let result = path.withCString { list($0, &output) }
        guard result == 0, let output else { return nil }
        defer { release(output) }
        return try? JSONDecoder().decode(Document.self, from: Data(String(cString: output).utf8))
        #else
        _ = path
        return nil
        #endif
    }
}
